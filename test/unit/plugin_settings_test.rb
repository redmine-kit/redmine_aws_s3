# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The plugin settings hold the administrator's values and the results that
    # the plugin writes (the consistency check, the malware findings).
    class PluginSettingsTest < ActiveSupport::TestCase
      NAME = 'plugin_redmine_aws_s3'

      def setup
        Setting.plugin_redmine_aws_s3 = { 'download_url_expiry' => '300' }
      end

      def teardown
        Setting.plugin_redmine_aws_s3 = {}
      end

      # A process without requests (the job worker) never refreshes Setting's
      # cache; a result it writes must not bring back an older value.
      def test_a_newer_change_of_another_process_stays
        assert_equal '300', Setting.plugin_redmine_aws_s3['download_url_expiry']
        change_in_another_process('download_url_expiry' => '600')
        RedmineAws::S3.update_settings('reconciliation' => { 'objects' => 1 })

        saved = Setting.find_by(name: NAME).value
        assert_equal '600', saved['download_url_expiry']
        assert_equal({ 'objects' => 1 }, saved['reconciliation'])
      end

      private

      # Saves the row without touching this process's cache of Setting.
      def change_in_another_process(values)
        setting = Setting.find_by(name: NAME)
        setting.value = setting.value.to_h.merge(values)
        setting.save!
      end
    end
  end
end
