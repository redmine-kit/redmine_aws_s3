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
        def initialize(message = 'the file is still being scanned for malware')
          super
        end
      end

      TICKET_PURPOSE = :redmine_aws_s3_upload

      attr_reader :user

      def initialize(user)
        @user = user
      end

      # Returns { url:, ticket: } for the browser.
      def presign(filename:, size:, content_type: nil)
        data = { 'key' => "#{RedmineAws::S3::INCOMING_PREFIX}#{SecureRandom.uuid}", 'filename' => filename.to_s,
                 'size' => Integer(size, exception: false), 'content_type' => content_type.to_s.presence,
                 'user_id' => user.id }
        check_attachment(data['filename'], data['size'])
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
        share_existing(attachment)
        return attachment if attachment.save

        storage.delete(copied) if attachment.s3_key == copied
        attachment
      end

      private

      def verify!(ticket)
        data = verifier.verified(ticket.to_s, purpose: TICKET_PURPOSE)
        raise Error, 'the upload ticket is invalid or expired' unless data && data['user_id'] == user.id
        raise Error, 'the key is not an upload' unless data['key'].to_s.start_with?(RedmineAws::S3::INCOMING_PREFIX)

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

      def check_attachment(filename, size)
        raise Error, 'filename is missing' if filename.blank?
        raise Error, 'size is invalid' if size.nil? || size.negative?

        unless Attachment.valid_extension?(File.extname(filename))
          raise Error, ::I18n.t(:error_attachment_extension_not_allowed, extension: File.extname(filename))
        end

        max = Setting.attachment_max_size.to_i.kilobytes
        return unless size > max

        raise Error, ::I18n.t(:error_attachment_too_big, max_size: max)
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
        attachment.disk_directory = Time.zone.now.strftime('%Y/%m')
        attachment.disk_filename = DiskName.free(attachment.filename, attachment.disk_directory)
        begin
          storage.copy(key, attachment.s3_key)
        rescue ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::NotFound
          raise Error, 'the upload is not in S3'
        end
        storage.delete(key)
        attachment.digest = digest!(attachment)
      end

      def digest!(attachment)
        head = storage.head(attachment.s3_key, checksum: true)
        error = if head&.content_length != attachment.filesize
                  'the uploaded file does not match its size'
                elsif head.checksum_type != 'FULL_OBJECT' || head.checksum_sha256.blank?
                  'S3 returned no SHA256 of the whole file'
                end
        return Base64.strict_decode64(head.checksum_sha256).unpack1('H*') unless error

        storage.delete(attachment.s3_key)
        raise Error, error
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

      # Shares an existing file with the same SHA256 and size instead of the
      # copy, as Redmine's reuse_existing_file_if_possible does.
      def share_existing(attachment)
        existing = Attachment.where(digest: attachment.digest, filesize: attachment.filesize)
                             .where.not(disk_filename: [nil, '']).order(:id).last
        return unless existing&.readable?

        storage.delete(attachment.s3_key)
        attachment.disk_directory = existing.disk_directory
        attachment.disk_filename = existing.disk_filename
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
