# frozen_string_literal: true

module RedmineServerlessS3
  # Prepended to Import (docs/attachments.md#the-tmp-cache): the CSV file is
  # also stored at imports/<filename>, so that an import can continue in
  # another environment whose /tmp does not have it.
  module ImportPatch
    def file=(arg)
      super
      return unless RedmineServerlessS3.enabled? && filepath.present? && File.exist?(filepath)

      RedmineServerlessS3.storage.put_file(s3_import_key, filepath)
    end

    def file_exists?
      return super unless RedmineServerlessS3.enabled? && filepath.present?
      return true if File.exist?(filepath)

      RedmineServerlessS3.storage.download(s3_import_key, filepath)
    end

    def s3_import_key
      "imports/#{filename}"
    end

    private

    # Deletes the object and the local file, without fetching it first.
    def remove_file
      return super unless RedmineServerlessS3.enabled? && filepath.present?

      RedmineServerlessS3.storage.delete(s3_import_key)
      FileUtils.rm_f(filepath)
    end
  end
end
