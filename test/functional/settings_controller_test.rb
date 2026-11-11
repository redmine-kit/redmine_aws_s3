# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    class SettingsControllerTest < Redmine::ControllerTest
      include RedmineAws::TestHelper

      tests SettingsController

      fixtures :users

      def setup
        @request.session[:user_id] = 1
      end

      def test_configure_opens_the_tab
        get :plugin, params: { id: 'redmine_aws_s3' }

        assert_redirected_to '/admin/aws/s3'
      end

      def test_other_plugins_are_not_changed
        get :plugin, params: { id: 'no_such_plugin' }

        assert_response :not_found
      end

      def test_the_settings_page_explains_the_upload_limit
        with_env(RedmineAws::S3::ENV_BUCKET => 'redmine-files') { get :edit, params: { tab: 'attachments' } }

        assert_response :success
        assert_include 'settings_attachment_max_size', response.body
        assert_select 'meta[name=?][content^=?]', 'redmine-s3-max-size-note',
                      'With S3, keep the CloudFront Function (/tmp/*) limit the same.'
        assert_select 'script[src*=?]', 'plugin_assets/redmine_aws_s3/s3_settings'
      end

      # The note comes from the script file, not from an inline script.
      def test_the_settings_page_has_no_inline_script
        with_env(RedmineAws::S3::ENV_BUCKET => 'redmine-files') { get :edit, params: { tab: 'attachments' } }

        assert_select 'script:not([src])', text: /redmine-s3|settings_attachment_max_size/, count: 0
        assert_select 'meta[name=?]', 'redmine-s3-presign-url'
      end

      def test_nothing_is_added_without_the_bucket
        get :edit, params: { tab: 'attachments' }

        assert_select 'meta[name=?]', 'redmine-s3-presign-url', count: 0
        assert_not_includes response.body, 's3_upload'
      end
    end
  end
end
