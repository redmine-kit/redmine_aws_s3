# frozen_string_literal: true

module RedmineAws
  module S3
    # The largest value of each plugin setting: an expiry of 7 days, a cache
    # of 10 GB (Lambda's largest /tmp). Checked when the settings are saved,
    # and applied again when they are used.
    module SettingLimits
      MAXIMA = {
        'download_url_expiry' => 7.days.to_i,
        'upload_url_expiry' => 7.days.to_i,
        'cache_size_mb' => 10_240
      }.freeze

      module_function

      # The value of the setting as a whole number within 1 and its maximum.
      def limit(name, value)
        value.to_i.clamp(1, MAXIMA.fetch(name))
      end
    end
  end
end
