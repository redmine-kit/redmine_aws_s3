# frozen_string_literal: true

module RedmineAwsS3
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
    # afterwards, in every case but Pending.
    def open(ticket)
      data = verify!(ticket)
      key = data['key']
      scan!(key, data)
      begin
        Tempfile.create(['redmine-s3-upload', File.extname(data['filename'].to_s)], binmode: true) do |file|
          raise Error, 'the upload is not in S3' unless storage.read(key, file)
          raise Error, 'the uploaded file does not match its size' unless file.size == data['size']

          file.rewind
          yield ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: data['filename'],
                                                       type: data['content_type'])
        end
      ensure
        storage.delete(key)
      end
    end
  end
end
