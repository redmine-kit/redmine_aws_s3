# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module S3
      # The "S3" tab in Redmine Kit's new UI (redmine_kit_ui, installed by
      # bin/test's first run): the manifest it takes, and the tab's JSON and
      # actions of the browser's session (kit requests: the session and the
      # CSRF token), with S3 stubbed as the functional tests of the tab stub it.
      class KitTest < Redmine::IntegrationTest
        include S3::TestHelper
        include RedmineKit::Ui::TestHelper if Redmine::Plugin.installed?(:redmine_kit_ui)

        fixtures :users, :email_addresses

        def setup
          skip 'redmine_kit_ui is not installed (bin/test runs these with it)' unless kit_ui?
          User.current = nil
        end

        def teardown
          ActionController::Base.allow_forgery_protection = false
          Setting.plugin_redmine_kit_aws_s3 = {}
        end

        def kit_ui?
          Redmine::Plugin.installed?(:redmine_kit_ui)
        end

        test 'redmine_kit_ui takes the manifest: the tab S3 of the page AWS' do
          screen = assert_kit_manifest(:redmine_kit_aws_s3).screens.sole
          assert_equal({ path: '/admin/aws/s3', component: 'AwsS3Admin', layout: 'admin', menu_item: 'aws',
                         tab: 'label_aws_s3_admin', position: 50 },
                       screen.slice(:path, :component, :layout, :menu_item, :tab, :position))
        end

        test "the tab's JSON: the environment without the private key, the settings" do
          headers = kit_session('admin', 'admin')
          with_s3(stub_client) do
            get '/admin/aws/s3.json', headers: headers
          end
          assert_response :success
          json = response.parsed_body
          assert json['enabled']
          assert_includes json['environment'], { 'name' => 'CloudFront private key', 'value' => 'Set',
                                                 'note' => 'REDMINE_S3_CLOUDFRONT_PRIVATE_KEY' }
          assert_not_includes response.body, 'PRIVATE KEY'
          assert_equal '300', json['settings']['download_url_expiry']
          assert_nil json['findings']
          get '/admin/aws/s3.json', headers: headers
          assert_not response.parsed_body['enabled']
        end

        test "the settings: saved, or Redmine's errors as 422" do
          headers = kit_session('admin', 'admin')
          patch '/admin/aws/s3.json', params: { settings: { download_url_expiry: '0' } }, headers: headers, as: :json
          assert_response 422
          assert_equal 1, response.parsed_body['errors'].size
          patch '/admin/aws/s3.json', params: { settings: { download_url_expiry: '600' } }, headers: headers, as: :json
          assert_response :success
          assert_equal 600, RedmineKit::Aws::S3.setting('download_url_expiry').to_i
        end

        test "the read/write check's rows, and the reconciliation's notice" do
          headers = kit_session('admin', 'admin')
          with_s3(stub_client(get_object: { body: 'x' })) do
            post '/admin/aws/s3/read_write.json', headers: headers, as: :json
            assert_response :success
            assert_equal %w[PutObject GetObject DeleteObject], response.parsed_body['results'].pluck('name')
            assert(response.parsed_body['results'].all? { |row| row.key?('ok') })
            post '/admin/aws/s3/reconcile.json', headers: headers, as: :json
            assert_response :success
            assert_equal 'Consistency check started.', response.parsed_body['notice']
          end
        end

        test 'for system administrators only, with the CSRF token; the actions need the bucket' do
          headers = kit_session('admin', 'admin')
          post '/admin/aws/s3/reconcile.json', headers: headers, as: :json
          assert_response :not_found
          patch '/admin/aws/s3.json', params: { settings: { download_url_expiry: '600' } },
                                      headers: headers.except('X-CSRF-Token'), as: :json
          assert_response 422
          reset!
          # Redmine's login form, as the other sign-ins: kit_session turned the protection on
          ActionController::Base.allow_forgery_protection = false
          get '/admin/aws/s3.json', headers: kit_session('jsmith')
          assert_response :forbidden
        end
      end
    end
  end
end
