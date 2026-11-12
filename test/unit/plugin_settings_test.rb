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

      # Two files refused at the same time: the finding of the other process,
      # saved after this one read its cache, stays.
      def test_findings_written_at_the_same_time_both_stay
        Setting.plugin_redmine_aws_s3
        change_in_another_process('malware_findings' => [{ 'key' => 'other' }])
        MalwareScan.record(key: 'this', filename: 'a.exe', user: nil, status: 'THREATS_FOUND')

        assert_equal %w[this other], Setting.find_by(name: NAME).value['malware_findings'].pluck('key')
      end

      # The start that another process saved (the button) is kept by the run.
      def test_a_run_keeps_the_start_saved_by_another_process
        Setting.plugin_redmine_aws_s3
        change_in_another_process('reconciliation' => { 'started_at' => '2026-11-06T22:40:00Z' })
        Reconciliation.stubs(:object_keys).returns(Set.new)
        Reconciliation.run

        assert_equal '2026-11-06T22:40:00Z', Setting.find_by(name: NAME).value.dig('reconciliation', 'started_at')
      end

      # The first write creates the row (with the defaults) before locking
      # it, so that two first writes lock a row, not a gap.
      def test_the_first_write_creates_the_row
        Setting.where(name: NAME).delete_all
        RedmineAws::S3.update_settings('reconciliation' => { 'objects' => 1 })

        rows = Setting.where(name: NAME).to_a
        assert_equal 1, rows.size
        assert_equal ['300', { 'objects' => 1 }], rows.first.value.values_at('download_url_expiry', 'reconciliation')
      end

      # Two first writes at once can leave two rows; Redmine reads the newest,
      # and so does update_settings.
      def test_the_newest_row_is_merged
        newest = Setting.new(name: NAME, value: { 'upload_url_expiry' => '600' })
        newest.save!(validate: false)
        RedmineAws::S3.update_settings('reconciliation' => { 'objects' => 1 })

        value = newest.reload.value
        assert_equal '600', value['upload_url_expiry']
        assert_equal({ 'objects' => 1 }, value['reconciliation'])
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
