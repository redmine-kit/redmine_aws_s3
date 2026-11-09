# frozen_string_literal: true

module RedmineServerlessS3
  # Compares the attachments in the database with the objects under files/
  # (docs/admin.md). The result is kept in the plugin settings, so that every
  # environment shows the latest one.
  module Reconciliation
    LIMIT = 100
    # Redmine's derived cache (Markdown previews) under files/, not attachments.
    DERIVED_PREFIX = 'files/derived_cache/'

    module_function

    def run
      started_at = result&.fetch('started_at', nil) || Time.now.utc.iso8601
      in_s3 = RedmineServerlessS3.storage.keys('files/')
                                 .reject { |key| key.start_with?(DERIVED_PREFIX) }.to_set
      in_db = attachment_keys
      save({ 'started_at' => started_at, 'finished_at' => Time.now.utc.iso8601,
             'attachments' => in_db.size, 'objects' => in_s3.size }
             .merge(listing('missing', in_db - in_s3), listing('unused', in_s3 - in_db)))
    end

    # The S3 keys of the files of all attachments.
    def attachment_keys
      Attachment.where.not(disk_filename: [nil, '']).distinct.pluck(:disk_directory, :disk_filename)
                .to_set { |dir, name| RedmineServerlessS3.file_key(dir, name) }
    end

    def listing(name, keys)
      { "#{name}_count" => keys.size, name => keys.sort.first(LIMIT) }
    end

    def started
      save('started_at' => Time.now.utc.iso8601)
    end

    def result
      settings = Setting.plugin_redmine_serverless_s3
      settings.is_a?(Hash) ? settings['reconciliation'] : nil
    end

    def save(result)
      RedmineServerlessS3.update_settings('reconciliation' => result)
    end
  end
end
