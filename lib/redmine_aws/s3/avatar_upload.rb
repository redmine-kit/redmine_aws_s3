# frozen_string_literal: true

module RedmineAws
  module S3
    # Avatars of Redmine 7.1 sent through CloudFront (docs/attachments.md#avatars):
    # the same signed URL and ticket as an attachment (Upload#presign), then
    # Redmine's own AvatarsController#update registers the upload as the file
    # of its form, so that User#update_avatar applies all of Redmine's rules.
    class AvatarUpload < Upload
      # Returns when the upload can be used: the ticket is valid and the
      # malware scan, when it is on, found it clean. Raises Pending while the
      # scan runs.
      def check!(ticket)
        data = verify!(ticket)
        scan!(data['key'], data)
      end

      # Yields the upload as a file sent in a form. The upload is deleted
      # afterwards, in every case but Pending. At most one byte more than the
      # declared size is read: a signed URL cannot limit what is PUT to it,
      # and a larger object would otherwise fill /tmp before the size check.
      def open(ticket)
        data = verify!(ticket)
        key = data['key']
        scan!(key, data)
        begin
          Tempfile.create(['redmine-s3-upload', File.extname(data['filename'].to_s)], binmode: true) do |file|
            yield uploaded_file(file, data)
          end
        ensure
          storage.delete(key)
        end
      end

      private

      # The upload read into file, as a file sent in a form.
      def uploaded_file(file, data)
        raise Error, ::I18n.t(:error_aws_s3_upload_not_found) unless read(data['key'], file, data['size'])
        raise Error, ::I18n.t(:error_aws_s3_upload_size_mismatch) unless file.size == data['size']

        file.rewind
        ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: data['filename'], type: data['content_type'])
      end

      # An empty upload has nothing to read (S3 refuses a range of an empty
      # object); Redmine refuses it as an image.
      def read(key, file, size)
        size.zero? || storage.read(key, file, bytes: size + 1)
      rescue ::Aws::S3::Errors::AccessDenied => e
        raise Error, access_denied(e)
      end
    end
  end
end
