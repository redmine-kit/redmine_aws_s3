# frozen_string_literal: true

module RedmineAws
  module S3
    # Writes to the plugin settings, which hold the administrator's values and
    # the results that the plugin keeps (the consistency check, the malware
    # findings).
    module PluginSettings
      NAME = 'plugin_redmine_aws_s3'

      module_function

      # Merges values into the plugin settings, keeping the other keys. Merged
      # into the row read again under a lock, not into Setting's cache, which a
      # process without requests (the job worker) never refreshes: an
      # administrator's newer change stays. With a block, the values are made
      # from the row read under the lock (two results written at the same time
      # both stay).
      def update(values = nil)
        create_row
        Setting.transaction do
          settings = Setting.where(name: NAME).order(id: :desc).lock.first.value
          settings = settings.is_a?(Hash) ? settings.to_h.stringify_keys : {}
          values = yield(settings) if block_given?
          Setting.plugin_redmine_aws_s3 = settings.merge(values.to_h.stringify_keys)
        end
      end

      # Creates the row when there is none yet, so that update locks a row
      # (not a gap, which deadlocks on MySQL when two first writes come at
      # once). Another process may create it first (Setting's uniqueness
      # validation); Redmine reads the newest row.
      def create_row
        return if Setting.exists?(name: NAME)

        Setting.create!(name: NAME, value: RedmineAws::S3::DEFAULT_SETTINGS)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
