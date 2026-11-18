# frozen_string_literal: true

module RedmineKit
  module Aws
    module S3
      # Prepended to Import (docs/attachments.md#the-tmp-cache): the CSV file is
      # also stored at imports/<filename>, so that an import can continue in
      # another environment whose /tmp does not have it.
      module ImportPatch
        def file=(arg)
          super
          return unless RedmineKit::Aws::S3.enabled? && filepath.present? && File.exist?(filepath)

          RedmineKit::Aws::S3.storage.put_file(s3_import_key, filepath)
        end

        # The file is read only after the malware scan has found it clean, when
        # the scan is on; it is fetched from S3 if this environment does not
        # have it.
        def file_exists?
          return super unless RedmineKit::Aws::S3.enabled? && filepath.present?
          return false unless malware_scanned?
          return true if File.exist?(filepath)

          RedmineKit::Aws::S3.storage.download(s3_import_key, filepath)
        end

        def malware_scanned?
          return true if @s3_malware_scanned || !RedmineKit::Aws::S3::MalwareScan.required?

          RedmineKit::Aws::S3::MalwareScan.check!(s3_import_key, filename: filename, user: user)
          @s3_malware_scanned = true
        rescue RedmineKit::Aws::S3::MalwareScan::Pending
          false
        rescue RedmineKit::Aws::S3::MalwareScan::Error
          FileUtils.rm_f(filepath)
          false
        end

        def s3_import_key
          "imports/#{filename}"
        end

        private

        # Deletes the object and the local file, without fetching it first.
        def remove_file
          return super unless RedmineKit::Aws::S3.enabled? && filepath.present?

          RedmineKit::Aws::S3.storage.delete(s3_import_key)
          FileUtils.rm_f(filepath)
        end
      end
    end
  end
end
