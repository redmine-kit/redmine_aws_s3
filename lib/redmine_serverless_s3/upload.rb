# frozen_string_literal: true

require 'securerandom'

module RedmineServerlessS3
  # Uploads from the browser through CloudFront (docs/attachments.md#upload).
  # presign checks the request and returns a CloudFront signed URL for a PUT
  # to incoming/<UUID>, with a ticket that keeps the declared name, size and
  # SHA256 signed by Redmine. complete reads the checksum S3 has checked and
  # registers the attachment without reading the file.
  class Upload
    class Error < StandardError; end

    SHA256_BASE64 = %r{\A[A-Za-z0-9+/]{43}=\z}
    TICKET_PURPOSE = :redmine_serverless_s3_upload

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Returns { url:, ticket:, headers: } for the browser.
    def presign(filename:, size:, sha256:, content_type: nil)
      filename = filename.to_s
      size = Integer(size, exception: false)
      raise Error, 'filename is missing' if filename.blank?
      raise Error, 'size is invalid' if size.nil? || size.negative?
      raise Error, 'sha256 is invalid' unless SHA256_BASE64.match?(sha256.to_s)

      check_attachment(filename, size)
      key = "incoming/#{SecureRandom.uuid}"
      expiry = RedmineServerlessS3.upload_url_expiry
      ticket = verifier.generate(
        { 'key' => key, 'filename' => filename, 'size' => size, 'sha256' => sha256,
          'content_type' => content_type.to_s.presence, 'user_id' => user.id },
        purpose: TICKET_PURPOSE, expires_in: expiry
      )
      { url: RedmineServerlessS3.url_signer.url_for(key, expires_in: expiry),
        ticket: ticket, headers: { 'x-amz-checksum-sha256' => sha256 } }
    end

    # Registers the uploaded object and returns the saved attachment. On a
    # mismatch the object is deleted and Error is raised.
    def complete(ticket)
      data = verifier.verified(ticket.to_s, purpose: TICKET_PURPOSE)
      raise Error, 'the upload ticket is invalid or expired' unless data && data['user_id'] == user.id

      key = data['key']
      raise Error, 'the key is not an upload' unless key.to_s.start_with?('incoming/')

      head = storage.head(key, checksum: true)
      raise Error, 'the upload is not in S3' unless head

      verify!(head, data, key)
      register(key, data)
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

    def verify!(head, data, key)
      return if head.checksum_sha256 == data['sha256'] && head.checksum_type == 'FULL_OBJECT' &&
                head.content_length == data['size']

      storage.delete(key)
      raise Error, 'the uploaded file does not match its SHA256 or size'
    end

    def register(key, data)
      digest = Base64.strict_decode64(data['sha256']).unpack1('H*')
      attachment = Attachment.new(author: user, filesize: data['size'], digest: digest)
      attachment.filename = data['filename']
      attachment.content_type = data['content_type'] if data['content_type']
      copied = place(attachment, key)
      return attachment if attachment.save

      storage.delete(attachment.s3_key) if copied
      attachment
    end

    # Shares an existing file with the same SHA256 and size, or copies the
    # upload to files/<year>/<month>/<name>; the upload is deleted either way.
    # Returns true if the upload was copied.
    def place(attachment, key)
      existing = Attachment.where(digest: attachment.digest, filesize: attachment.filesize)
                           .where.not(disk_filename: [nil, '']).order(:id).last
      copied = if existing&.readable?
                 attachment.disk_directory = existing.disk_directory
                 attachment.disk_filename = existing.disk_filename
                 false
               else
                 attachment.disk_directory = Time.zone.now.strftime('%Y/%m')
                 attachment.disk_filename = free_name(attachment.filename, attachment.disk_directory)
                 storage.copy(key, attachment.s3_key)
                 true
               end
      storage.delete(key)
      copied
    end

    # A name like Redmine's Attachment.create_diskfile, not used in S3 yet.
    def free_name(filename, directory)
      timestamp = Time.zone.now.strftime('%y%m%d%H%M%S')
      ascii = if /\A[a-zA-Z0-9_.-]*\z/.match?(filename) && filename.length <= 50
                filename
              else
                hashed = ActiveSupport::Digest.hexdigest(filename)
                ext = filename[/(\.[a-zA-Z0-9]+)\z/, 1]
                ext && (hashed.length + ext.length) <= 50 ? hashed + ext : hashed
              end
      loop do
        name = "#{timestamp}_#{ascii}"
        return name unless storage.exists?(RedmineServerlessS3.file_key(directory, name)) ||
                           Attachment.exists?(disk_directory: directory, disk_filename: name)

        timestamp = timestamp.succ
      end
    end

    def storage
      @storage ||= RedmineServerlessS3.storage
    end

    def verifier
      Rails.application.message_verifier(TICKET_PURPOSE)
    end
  end
end
