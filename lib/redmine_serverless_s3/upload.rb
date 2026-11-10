# frozen_string_literal: true

require 'securerandom'

module RedmineServerlessS3
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

    TICKET_PURPOSE = :redmine_serverless_s3_upload

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Returns { url:, ticket: } for the browser.
    def presign(filename:, size:, content_type: nil)
      filename = filename.to_s
      size = Integer(size, exception: false)
      raise Error, 'filename is missing' if filename.blank?
      raise Error, 'size is invalid' if size.nil? || size.negative?

      check_attachment(filename, size)
      key = "#{RedmineServerlessS3::INCOMING_PREFIX}#{SecureRandom.uuid}"
      expiry = RedmineServerlessS3.upload_url_expiry
      ticket = verifier.generate(
        { 'key' => key, 'filename' => filename, 'size' => size,
          'content_type' => content_type.to_s.presence, 'user_id' => user.id },
        purpose: TICKET_PURPOSE, expires_in: expiry
      )
      { url: RedmineServerlessS3.url_signer.url_for(key, expires_in: expiry), ticket: ticket }
    end

    # Registers the uploaded object and returns the attachment, saved unless
    # its validations fail. The upload is deleted in every case but Pending.
    def complete(ticket)
      data = verifier.verified(ticket.to_s, purpose: TICKET_PURPOSE)
      raise Error, 'the upload ticket is invalid or expired' unless data && data['user_id'] == user.id

      key = data['key']
      raise Error, 'the key is not an upload' unless key.to_s.start_with?(RedmineServerlessS3::INCOMING_PREFIX)

      scan!(key, data)
      attachment = Attachment.new(author: user, filesize: data['size'])
      attachment.filename = data['filename']
      attachment.content_type = data['content_type'] if data['content_type']
      copy!(attachment, key)
      copied = attachment.s3_key
      share_existing(attachment)
      return attachment if attachment.save

      storage.delete(copied) if attachment.s3_key == copied
      attachment
    end

    private

    def check_attachment(filename, size)
      unless Attachment.valid_extension?(File.extname(filename))
        raise Error, ::I18n.t(:error_attachment_extension_not_allowed, extension: File.extname(filename))
      end

      max = Setting.attachment_max_size.to_i.kilobytes
      return unless size > max

      raise Error, ::I18n.t(:error_attachment_too_big, max_size: max)
    end

    # Waits for GuardDuty's tag when the scan is on (docs/attachments.md#malware-scan).
    def scan!(key, data)
      return unless RedmineServerlessS3::MalwareScan.required?

      RedmineServerlessS3::MalwareScan.check!(key, filename: data['filename'], user: user)
    rescue RedmineServerlessS3::MalwareScan::Pending
      raise Pending
    rescue RedmineServerlessS3::MalwareScan::Error => e
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
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
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
      @storage ||= RedmineServerlessS3.storage
    end

    def verifier
      Rails.application.message_verifier(TICKET_PURPOSE)
    end
  end
end
