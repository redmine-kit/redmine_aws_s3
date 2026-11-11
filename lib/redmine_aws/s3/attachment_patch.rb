# frozen_string_literal: true

module RedmineAws
  module S3
    # Prepended to Attachment (docs/attachments.md#replaced-code). Each method
    # calls Redmine's own code when the plugin is off.
    module AttachmentPatch
      # The S3 key of the file.
      def s3_key
        RedmineAws::S3.file_key(disk_directory, disk_filename)
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
        RedmineAws::S3::AttachmentFile.put(self) if had_file && RedmineAws::S3.enabled? && disk_filename.present?
      rescue RedmineAws::S3::MalwareScan::Error => e
        FileUtils.rm_f(local_diskfile)
        errors.add(:base, e.message)
        throw :abort
      end

      # The path in the /tmp cache, fetched from S3 for a saved attachment
      # whose file is not local.
      def diskfile
        path = super
        return path unless RedmineAws::S3.enabled? && persisted? && !destroyed? && disk_filename.present?

        RedmineAws::S3::Cache.fetch(s3_key, path)
        path
      end

      # The object in S3, without fetching the file.
      def readable?
        return super unless RedmineAws::S3.enabled?
        return false if disk_filename.blank?
        return true if File.readable?(local_diskfile)
        return @s3_readable if defined?(@s3_readable)

        @s3_readable = RedmineAws::S3.storage.exists?(s3_key)
      end

      # No thumbnail for files larger than the cache.
      def thumbnailable?
        return super unless RedmineAws::S3.enabled?

        super && filesize.to_i <= RedmineAws::S3.cache_size
      end

      # The thumbnail at Redmine's path: the local one, else the one in S3, else
      # one created as Redmine does from the file in the /tmp cache and stored
      # in S3. Avatars (Redmine 7.1) are served this way, cropped.
      def thumbnail(options = {})
        return super unless RedmineAws::S3.enabled? && thumbnailable? && readable?

        path = thumbnail_path(thumbnail_name(options))
        return path if RedmineAws::S3::Cache.fetch(RedmineAws::S3.thumbnail_key(path), path)

        super.tap { |made| RedmineAws::S3.storage.put_file(RedmineAws::S3.thumbnail_key(made), made) if made }
      end

      # Keeps the Markdown preview in S3 (MarkdownizedPreview).
      def markdownized_preview_content
        return super unless RedmineAws::S3.enabled? && markdownized_previewable?

        RedmineAws::S3::MarkdownizedPreview.around(self) { super }
      end

      # The S3 key of the thumbnail, made if it is not in S3 yet; nil if there
      # is none.
      def s3_thumbnail(options = {})
        return nil unless thumbnailable? && readable?

        key = RedmineAws::S3.thumbnail_key(thumbnail_path(thumbnail_name(options)))
        return key if RedmineAws::S3.storage.exists?(key)

        (target = thumbnail(options)) && RedmineAws::S3.thumbnail_key(target)
      end

      # The part of the thumbnail's name after the digest and size, as
      # Redmine's Attachment#thumbnail makes it: the size, then _crop for a
      # cropped one where Redmine crops (from 7.1, for avatars).
      def thumbnail_name(options)
        "#{thumbnail_size(options)}#{'_crop' if options[:crop] && RedmineAws::S3.thumbnail_crop?}"
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
        return super unless RedmineAws::S3.enabled?

        original_key = s3_key
        original_path = local_diskfile
        original_filename = disk_filename
        return unless with_lock { share_existing_file(original_filename) }
        return unless Attachment.where(disk_filename: original_filename).none?

        RedmineAws::S3.storage.delete(original_key)
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

      # Deletes the file, its thumbnails and its Markdown preview in S3, then
      # the local copies.
      def delete_from_disk!
        if RedmineAws::S3.enabled? && disk_filename.present?
          storage = RedmineAws::S3.storage
          storage.delete(s3_key)
          if digest.present?
            storage.delete_prefix("#{RedmineAws::S3::THUMBNAILS_PREFIX}#{digest}_#{filesize}_")
            storage.delete(RedmineAws::S3::MarkdownizedPreview.key(self))
          end
        end
        super
      end
    end
  end
end
