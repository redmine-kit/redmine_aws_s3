# frozen_string_literal: true

require 'securerandom'

module RedmineAws
  module S3
    # Uploads from the browser through CloudFront (docs/attachments.md#upload).
    # presign checks the request and returns a CloudFront signed URL for a PUT
    # to tmp/incoming/<UUID>, with a ticket that keeps the declared name, size
    # and content type signed by Redmine. complete copies the upload to its
    # files/ key, where S3 computes the SHA256 that becomes the digest, and
    # registers the attachment without reading the file.
    class Upload
      class Error < StandardError; end

      # The malware scan has not finished; the client calls complete again.
      class Pending < Error
        def initialize(message = ::I18n.t(:error_aws_s3_malware_scanning))
          super
        end
      end

      TICKET_PURPOSE = :redmine_aws_s3_upload
      INCOMING = RedmineAws::S3::INCOMING_PREFIX

      attr_reader :user

      def initialize(user)
        @user = user
      end

      # Returns { url:, ticket: } for the browser.
      def presign(filename:, size:, content_type: nil)
        data = { 'key' => "#{RedmineAws::S3::INCOMING_PREFIX}#{SecureRandom.uuid}", 'filename' => filename.to_s,
                 'size' => Integer(size, exception: false), 'content_type' => content_type.to_s.presence,
                 'user_id' => user.id }
        UploadCheck.check!(data['filename'], data['size'])
        expiry = RedmineAws::S3.upload_url_expiry
        { url: RedmineAws::S3.url_signer.url_for(data['key'], expires_in: expiry),
          ticket: verifier.generate(data, purpose: TICKET_PURPOSE, expires_in: expiry) }
      end

      # Registers the uploaded object and returns the attachment, saved unless
      # its validations fail. The upload is deleted in every case but Pending.
      def complete(ticket)
        data = verify!(ticket)
        scan!(data['key'], data)
        attachment = copied_attachment(data)
        copied = attachment.s3_key
        return attachment if attachment.save

        storage.delete(copied) if attachment.s3_key == copied
        attachment
      end

      private

      def verify!(ticket)
        data = verifier.verified(ticket.to_s, purpose: TICKET_PURPOSE)
        # A ticket that Redmine did not sign never gets here; both are "expired".
        raise Error, ::I18n.t(:error_aws_s3_upload_expired) unless data && data['user_id'] == user.id
        raise Error, ::I18n.t(:error_aws_s3_upload_expired) unless data['key'].to_s.start_with?(INCOMING)

        data
      end

      # A new attachment with the upload copied to its key.
      def copied_attachment(data)
        attachment = Attachment.new(author: user, filesize: data['size'])
        attachment.filename = data['filename']
        copy!(attachment, data['key'])
        attachment.content_type = content_type_of(attachment, data['content_type'])
        attachment
      end

      # Waits for GuardDuty's tag when the scan is on (docs/attachments.md#malware-scan).
      def scan!(key, data)
        return unless RedmineAws::S3::MalwareScan.required?

        RedmineAws::S3::MalwareScan.check!(key, filename: data['filename'], user: user)
      rescue RedmineAws::S3::MalwareScan::Pending
        raise Pending
      rescue RedmineAws::S3::MalwareScan::Error => e
        raise Error, e.message
      end

      # Copies the upload to a new files/<year>/<month>/<name> key, where S3
      # computes the SHA256 of the whole object, and deletes the upload. The
      # SHA256 becomes the digest; a size other than the declared one fails.
      def copy!(attachment, key)
        directory = attachment.disk_directory = Time.zone.now.strftime('%Y/%m')
        begin
          attachment.disk_filename = DiskName.claim(attachment.filename, directory) do |name|
            storage.copy(key, RedmineAws::S3.file_key(directory, name), new_only: true)
          end
        rescue ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::NotFound
          raise Error, ::I18n.t(:error_aws_s3_upload_not_found)
        end
        storage.delete(key)
        attachment.digest = digest!(attachment)
      end

      def digest!(attachment)
        head = storage.head(attachment.s3_key, checksum: true)
        error = digest_error(head, attachment)
        return Base64.strict_decode64(head.checksum_sha256).unpack1('H*') unless error

        storage.delete(attachment.s3_key)
        raise Error, ::I18n.t(error)
      end

      # The message key when the copy is not the declared file, or nil.
      def digest_error(head, attachment)
        return :error_aws_s3_upload_size_mismatch if head&.content_length != attachment.filesize
        return if head.checksum_type == 'FULL_OBJECT' && head.checksum_sha256.present?

        # A bucket or S3 problem that the user cannot fix.
        Rails.logger.error("[redmine_aws_s3] no full-object SHA256 for #{attachment.s3_key}")
        :error_aws_s3_upload_failed
      end

      # Redmine 7.1 detects the type from the contents and the name when it
      # saves an attachment (Attachment#set_content_type) and ignores the type
      # the client declares; the same here, from the first 64 KB of the copy,
      # which is enough for the magic numbers Marcel knows.
      # Redmine 7.0 takes the declared type, as its POST /uploads does.
      def content_type_of(attachment, declared)
        return declared unless RedmineAws::S3.detects_content_type?

        head = storage.read_start(attachment.s3_key, 64.kilobytes) if attachment.filesize.to_i.positive?
        Marcel::MimeType.for(StringIO.new(head.to_s), name: attachment.filename)
      end

      def storage
        @storage ||= RedmineAws::S3.storage
      end

      def verifier
        Rails.application.message_verifier(TICKET_PURPOSE)
      end
    end
  end
end
