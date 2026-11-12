# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/admin_controller_setup'

module RedmineAws
  module S3
    # The "S3" tab: what it shows, and its settings.
    class AwsS3AdminControllerTest < Redmine::ControllerTest
      include S3::TestHelper
      include AdminControllerSetup

      def test_show_without_the_bucket
        get :show

        assert_response :success
        assert_select '.tabs a', text: 'S3'
        assert_select 'p.warning', text: /REDMINE_S3_BUCKET/
        assert_select 'input[name=?][value=?]', 'settings[download_url_expiry]', '300'
        assert_select 'a[href=?]', '/admin/aws/s3/read_write', count: 0
      end

      def test_show_with_the_bucket_never_shows_the_private_key
        with_s3(stub_client) do
          get :show

          assert_response :success
          assert_select 'table.list.values.environment tr', text: /redmine-files/
          assert_select 'table.list.values.environment tr', text: /#{Regexp.escape(DOMAIN)}/
          assert_select 'table.list.values.environment tr', text: /Set\s*REDMINE_CLOUDFRONT_PRIVATE_KEY/
          assert_not_includes response.body, 'PRIVATE KEY'
          assert_select 'table.list.values.environment tr', text: /GuardDuty malware scan\s*Disabled/
        end
      end

      # Test and run actions are text links: Redmine has no icon for them.
      # Showing the tab calls nothing in AWS.
      def test_show_with_the_bucket_has_text_links_and_calls_nothing
        with_s3(stub_client) do |client|
          get :show

          assert_select 'p a[data-method=post][href=?]:not(.icon)', '/admin/aws/s3/read_write',
                        text: 'Read/write test'
          assert_select 'p a[data-method=post][href=?]:not(.icon)', '/admin/aws/s3/reconcile',
                        text: 'Run consistency check'
          assert_empty client.api_requests
        end
      end

      def test_non_administrators_are_refused
        @request.session[:user_id] = 2
        get :show

        assert_response :forbidden
      end

      def test_update_logs_the_names_of_the_settings
        log = capture_log do
          patch :update, params: { settings: { download_url_expiry: '120', cache_size_mb: '64', other: '1' } }
        end

        assert_redirected_to '/admin/aws/s3'
        assert_includes log, 'admin changed the settings download_url_expiry, cache_size_mb'
        assert_not_includes log, '120', 'the log names the settings, not their values'
      end

      def test_update_merges_the_settings
        RedmineAws::S3.update_settings('reconciliation' => { 'finished_at' => 'x' })
        patch :update, params: { settings: { download_url_expiry: '120', cache_size_mb: '64', other: '1' } }

        assert_equal 120, RedmineAws::S3.download_url_expiry
        assert_equal 64.megabytes, RedmineAws::S3.cache_size
        assert_equal({ 'finished_at' => 'x' }, RedmineAws::S3::Reconciliation.result)
        assert_not Setting.plugin_redmine_aws_s3.key?('other')
      end

      # The form is shown again with the values entered and the error in
      # Redmine's error box, and nothing is saved.
      def test_update_refuses_values_that_are_not_positive_numbers
        ['0', '-5', '1.5', 'x', '', '12345678'].each do |value|
          patch :update, params: { settings: { download_url_expiry: value, upload_url_expiry: '600' } }

          assert_response :unprocessable_content, value
          assert_select '#errorExplanation li', text: 'Enter a positive whole number: Download URL expiry'
          assert_select 'input[name=?][value=?]', 'settings[download_url_expiry]', value
          assert_select 'input[name=?][value=?]', 'settings[upload_url_expiry]', '600'
          assert_nil flash[:error]
          assert_default_expiries
        end
      end

      # Values above the limits that the plugin applies are refused, with
      # Redmine's own message, not saved and clamped silently.
      def test_update_refuses_values_over_the_maximum
        patch :update, params: { settings: { download_url_expiry: '604801', cache_size_mb: '10241' } }

        assert_response :unprocessable_content
        assert_select '#errorExplanation li', text: 'Download URL expiry must be less than or equal to 604800'
        assert_select '#errorExplanation li', text: 'Local cache size limit must be less than or equal to 10240'
        assert_default_expiries
      end

      def test_update_ignores_settings_that_are_not_strings
        patch :update, params: { settings: { download_url_expiry: ['120'], upload_url_expiry: { a: '1' } } }

        assert_redirected_to '/admin/aws/s3'
        assert_default_expiries
      end

      def test_blocked_files_use_the_aws_terms_and_redmine_users
        save_finding('time' => '2026-11-06T22:44:01Z', 'status' => 'THREATS_FOUND', 'filename' => 'bad.exe',
                     'key' => 'k', 'user' => 'jsmith')
        with_s3(stub_client) do
          get :show

          assert_select 'h3', text: 'Files blocked by malware scan'
          assert_select '#aws-s3-malware tbody tr', text: /Threats found\s*bad\.exe\s*John Smith/
          assert_select '#aws-s3-malware a[href=?]', '/users/2'
          assert_not_includes response.body, 'THREATS_FOUND'
          assert_not_includes response.body, '2026-11-06T22:44:01Z'
        end
      end

      private

      def save_finding(finding)
        RedmineAws::S3.update_settings('malware_findings' => [finding])
      end

      def assert_default_expiries
        assert_equal 300, RedmineAws::S3.download_url_expiry
        assert_equal 900, RedmineAws::S3.upload_url_expiry
      end
    end
  end
end
