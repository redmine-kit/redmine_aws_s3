# frozen_string_literal: true

module RedmineServerlessS3
  # Prepended to Attachment (docs/attachments.md#replaced-code). Each method
  # calls Redmine's own code when the plugin is off.
  module AttachmentPatch
    # The S3 key of the file.
    def s3_key
      RedmineServerlessS3.file_key(disk_directory, disk_filename)
    end

    # The path under attachments_storage_path, without fetching anything.
    def local_diskfile
      File.join(self.class.storage_path, disk_directory.to_s, disk_filename.to_s)
    end

    # Uploads through Lambda (REST API, mail, forms): after Redmine has
    # written the file and computed its SHA256, put it to S3, through the
    # malware scan when it is on. If PutObject fails, the exception stops the
    # save; a file the scan refuses is a validation error.
    def files_to_final_location
      had_file = instance_variable_get(:@temp_file).present?
      super
      return unless had_file && RedmineServerlessS3.enabled? && disk_filename.present?

      if RedmineServerlessS3::MalwareScan.required?
        RedmineServerlessS3::MalwareScan.put_scanned(local_diskfile, s3_key, filename: filename, user: author)
      else
        RedmineServerlessS3.storage.put_file(s3_key, local_diskfile)
      end
    rescue RedmineServerlessS3::MalwareScan::Error => e
      FileUtils.rm_f(local_diskfile)
      errors.add(:base, e.message)
      throw :abort
    end

    # The path in the /tmp cache, fetched from S3 for a saved attachment
    # whose file is not local.
    def diskfile
      path = super
      return path unless RedmineServerlessS3.enabled? && persisted? && !destroyed? && disk_filename.present?

      RedmineServerlessS3::Cache.fetch(s3_key, path)
      path
    end

    # The object in S3, without fetching the file.
    def readable?
      return super unless RedmineServerlessS3.enabled?
      return false if disk_filename.blank?
      return true if File.readable?(local_diskfile)
      return @s3_readable if defined?(@s3_readable)

      @s3_readable = RedmineServerlessS3.storage.exists?(s3_key)
    end

    # No thumbnail for files larger than the cache.
    def thumbnailable?
      return super unless RedmineServerlessS3.enabled?

      super && filesize.to_i <= RedmineServerlessS3.cache_size
    end

    # Creates the thumbnail as Redmine does, from the file in the /tmp cache,
    # and stores it in S3.
    def thumbnail(options = {})
      target = super
      return target unless RedmineServerlessS3.enabled? && target

      RedmineServerlessS3.storage.put_file(s3_thumbnail_key(thumbnail_size(options)), target)
      target
    end

    # The S3 key of the thumbnail, made if it is not in S3 yet; nil if there
    # is none.
    def s3_thumbnail(options = {})
      return nil unless thumbnailable? && readable?

      key = s3_thumbnail_key(thumbnail_size(options))
      return key if RedmineServerlessS3.storage.exists?(key)

      key if thumbnail(options)
    end

    def s3_thumbnail_key(size)
      "thumbnails/#{File.basename(thumbnail_path(size))}"
    end

    # The size Redmine's Attachment#thumbnail computes.
    def thumbnail_size(options)
      size = options[:size].to_i
      if size.positive?
        size = (size / 50.0).ceil * 50
        size = 800 if size > 800
      else
        size = Setting.thumbnails_size.to_i
      end
      size.positive? ? size : 100
    end

    private

    # Shares a file with the same SHA256 and size, deciding by the digest
    # instead of comparing local files, and deletes the newer object.
    def reuse_existing_file_if_possible
      return super unless RedmineServerlessS3.enabled?

      original_key = s3_key
      original_path = local_diskfile
      original_filename = disk_filename
      return unless with_lock { share_existing_file(original_filename) }
      return unless Attachment.where(disk_filename: original_filename).none?

      RedmineServerlessS3.storage.delete(original_key)
      FileUtils.rm_f(original_path)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordNotFound
      nil
    end

    # Points this attachment at the file of the newest other attachment with
    # the same SHA256 and size. Returns that attachment, or nil.
    def share_existing_file(original_filename)
      return nil unless digest.to_s.size == 64

      existing = Attachment.where(digest: digest, filesize: filesize)
                           .where.not(disk_filename: original_filename).order(:id).last
      return nil unless existing&.readable?

      update_columns(disk_directory: existing.disk_directory, disk_filename: existing.disk_filename)
      existing
    end

    # Deletes the file and its thumbnails in S3, then the local copies.
    def delete_from_disk!
      if RedmineServerlessS3.enabled? && disk_filename.present?
        storage = RedmineServerlessS3.storage
        storage.delete(s3_key)
        storage.delete_prefix("thumbnails/#{digest}_#{filesize}_") if digest.present?
      end
      super
    end
  end
end
