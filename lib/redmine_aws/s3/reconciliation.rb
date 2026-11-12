# frozen_string_literal: true

module RedmineAws
  module S3
    # Compares the attachments in the database with the objects under files/
    # (docs/admin.md). The result is kept in the plugin settings, so that every
    # environment shows the latest one.
    module Reconciliation
      LIMIT = 100
      # A run not finished after this stopped (a timeout of the job, a killed
      # worker); it is shown as timed out. Listing files/ takes minutes.
      RUN_LIMIT = 1.hour
      # Redmine's derived cache (Markdown previews) under files/, not attachments.
      DERIVED_PREFIX = 'files/derived_cache/'

      module_function

      def run
        in_s3 = object_keys
        found = summary(attachment_keys, in_s3)
        save { |last| { 'started_at' => last&.fetch('started_at', nil) || found['finished_at'] }.merge(found) }
      end

      # Keeps the class of the error that stopped the run; the job logs the
      # message.
      def failed(error)
        save { |last| { 'started_at' => last&.fetch('started_at', nil), 'error' => error.class.name }.compact }
      end

      # :running, :failed (with an error, or not finished within RUN_LIMIT),
      # or :finished.
      def state(result)
        return :finished if result['finished_at'].present?
        return :failed if result['error'].present?

        started = started_at(result)
        started && started > RUN_LIMIT.ago ? :running : :failed
      end

      def started_at(result)
        Time.iso8601(result['started_at'].to_s)
      rescue ArgumentError
        nil
      end

      # The keys of the objects under files/, without Redmine's derived cache.
      def object_keys
        RedmineAws::S3.storage.keys('files/').reject { |key| key.start_with?(DERIVED_PREFIX) }.to_set
      end

      def summary(in_db, in_s3)
        { 'finished_at' => Time.now.utc.iso8601, 'attachments' => in_db.size, 'objects' => in_s3.size }
          .merge(listing('missing', in_db - in_s3), listing('unused', in_s3 - in_db))
      end

      # The S3 keys of the files of all attachments.
      def attachment_keys
        Attachment.where.not(disk_filename: [nil, '']).distinct.pluck(:disk_directory, :disk_filename)
                  .to_set { |dir, name| RedmineAws::S3.file_key(dir, name) }
      end

      def listing(name, keys)
        { "#{name}_count" => keys.size, name => keys.sort.first(LIMIT) }
      end

      def started
        save { { 'started_at' => Time.now.utc.iso8601 } }
      end

      def result
        settings = Setting.plugin_redmine_aws_s3
        settings.is_a?(Hash) ? settings['reconciliation'] : nil
      end

      # Saves the result that the block makes from the last one, read again
      # under the lock of update_settings.
      def save
        RedmineAws::S3.update_settings { |settings| { 'reconciliation' => yield(settings['reconciliation']) } }
      end
    end
  end
end
