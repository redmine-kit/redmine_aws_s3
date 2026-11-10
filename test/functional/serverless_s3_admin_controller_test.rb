# frozen_string_literal: true

require_relative '../test_helper'

class ServerlessS3AdminControllerTest < Redmine::ControllerTest
  include RedmineServerlessS3::TestHelper

  fixtures :users

  def setup
    @request.session[:user_id] = 1
  end

  def teardown
    Setting.plugin_redmine_serverless_s3 = {}
  end

  def test_show_without_the_bucket
    get :show

    assert_response :success
    assert_select '.tabs a', text: 'S3'
    assert_select 'p.warning', text: /REDMINE_S3_BUCKET/
    assert_select 'input[name=?][value=?]', 'settings[download_url_expiry]', '300'
    assert_select 'a[href=?]', '/admin/serverless/s3/read_write', count: 0
  end

  def test_show_with_the_bucket_never_shows_the_private_key
    with_s3(stub_client) do |client|
      get :show

      assert_response :success
      assert_select 'div.box.tabular p', text: /redmine-files/
      assert_select 'div.box.tabular p', text: /#{Regexp.escape(DOMAIN)}/
      assert_select 'div.box.tabular p', text: /Set\s*REDMINE_CLOUDFRONT_PRIVATE_KEY/
      assert_not_includes response.body, 'PRIVATE KEY'
      assert_select 'div.box.tabular p', text: /GuardDuty malware scan\s*Disabled/
      # Test and run actions are text links: Redmine has no icon for them.
      assert_select 'p a[data-method=post][href=?]:not(.icon)', '/admin/serverless/s3/read_write',
                    text: 'Read/write test'
      assert_select 'p a[data-method=post][href=?]:not(.icon)', '/admin/serverless/s3/reconcile',
                    text: 'Run consistency check'
      assert_empty client.api_requests
    end
  end

  def test_non_administrators_are_refused
    @request.session[:user_id] = 2
    get :show

    assert_response :forbidden
  end

  def test_update_merges_the_settings
    RedmineServerlessS3.update_settings('reconciliation' => { 'finished_at' => 'x' })
    patch :update, params: { settings: { download_url_expiry: '120', cache_size_mb: '64', other: '1' } }

    assert_redirected_to '/admin/serverless/s3'
    assert_equal 120, RedmineServerlessS3.download_url_expiry
    assert_equal 64.megabytes, RedmineServerlessS3.cache_size
    assert_equal({ 'finished_at' => 'x' }, RedmineServerlessS3::Reconciliation.result)
    assert_not Setting.plugin_redmine_serverless_s3.key?('other')
  end

  def test_update_refuses_values_that_are_not_positive_numbers
    patch :update, params: { settings: { download_url_expiry: '0' } }

    assert_redirected_to '/admin/serverless/s3'
    assert_equal 300, RedmineServerlessS3.download_url_expiry
    assert_equal 'Enter a positive whole number: Download URL expiry', flash[:error]
  end

  def test_read_write_check
    put_body = lambda do |context|
      { body: context.client.api_requests.find { |request| request[:operation_name] == :put_object }[:params][:body] }
    end
    with_s3(stub_client(get_object: put_body)) do
      post :read_write

      assert_redirected_to '/admin/serverless/s3'
      assert_equal [['PutObject', true, ''], ['GetObject', true, ''], ['DeleteObject', true, '']],
                   flash[:serverless_s3_checks]
    end
  end

  def test_read_write_check_reports_a_failure
    with_s3(stub_client(put_object: 'AccessDenied', get_object: 'NoSuchKey')) do
      post :read_write

      assert_equal [false, false, true], flash[:serverless_s3_checks].map(&:second)
    end
  end

  def test_actions_need_the_bucket
    post :read_write

    assert_response :not_found
  end

  def test_reconcile_enqueues_the_job
    with_s3(stub_client) do
      ServerlessS3ReconcileJob.expects(:perform_later).once
      post :reconcile

      assert_redirected_to '/admin/serverless/s3'
      assert RedmineServerlessS3::Reconciliation.result['started_at'].present?
    end
  end

  def test_shows_the_reconciliation_result
    RedmineServerlessS3.update_settings(
      'reconciliation' => { 'started_at' => '2026-11-06T22:40:00Z', 'finished_at' => '2026-11-06T22:44:01Z',
                            'attachments' => 1200, 'objects' => 1201, 'missing_count' => 1,
                            'missing' => ['files/2026/11/a'], 'unused_count' => 2, 'unused' => [] }
    )
    with_s3(stub_client) do
      with_settings(date_format: '%Y-%m-%d', time_format: '%H:%M') { get :show }

      assert_select '#serverless-s3-reconciliation p', text: /Last run\s*2026-11-06 \d\d:44/
      assert_select '#serverless-s3-reconciliation p', text: /Attachments\s*1,200/
      assert_select '#serverless-s3-reconciliation p', text: %r{S3 objects\s*1,201\s*files/}
      assert_select '#serverless-s3-reconciliation p', text: /Files missing in S3\s*1/
      assert_select '#serverless-s3-reconciliation p', text: /Unused objects\s*2/
      assert_not_includes response.body, '2026-11-06T22:44:01Z'
      assert_select 'li code', text: 'files/2026/11/a'
    end
  end

  def test_a_running_reconciliation
    RedmineServerlessS3.update_settings('reconciliation' => { 'started_at' => '2026-11-06T22:40:00Z' })
    with_s3(stub_client) do
      with_settings(date_format: '%Y-%m-%d', time_format: '%H:%M') { get :show }

      assert_select '#serverless-s3-reconciliation p', text: /Status\s*Running/
      assert_select '#serverless-s3-reconciliation p', text: /Started at\s*2026-11-06 \d\d:40/
    end
  end

  def test_blocked_files_use_the_aws_terms_and_redmine_users
    RedmineServerlessS3.update_settings(
      'malware_findings' => [{ 'time' => '2026-11-06T22:44:01Z', 'status' => 'THREATS_FOUND',
                               'filename' => 'bad.exe', 'key' => 'k', 'user' => 'jsmith' }]
    )
    with_s3(stub_client) do
      get :show

      assert_select 'h3', text: 'Files blocked by malware scan'
      assert_select '#serverless-s3-malware tbody tr', text: /Threats found\s*bad\.exe\s*John Smith/
      assert_select '#serverless-s3-malware a[href=?]', '/users/2'
      assert_not_includes response.body, 'THREATS_FOUND'
      assert_not_includes response.body, '2026-11-06T22:44:01Z'
    end
  end
end

class RedmineServerlessS3SettingsControllerTest < Redmine::ControllerTest
  tests SettingsController

  fixtures :users

  def setup
    @request.session[:user_id] = 1
  end

  def test_configure_opens_the_tab
    get :plugin, params: { id: 'redmine_serverless_s3' }

    assert_redirected_to '/admin/serverless/s3'
  end

  def test_other_plugins_are_not_changed
    get :plugin, params: { id: 'no_such_plugin' }

    assert_response :not_found
  end

  def test_the_settings_page_explains_the_upload_limit
    ENV[RedmineServerlessS3::ENV_BUCKET] = 'redmine-files'
    get :edit, params: { tab: 'attachments' }

    assert_response :success
    assert_include 'settings_attachment_max_size', response.body
    assert_include 'keep the CloudFront Function (/tmp/*) limit the same', response.body
    assert_select 'meta[name=?]', 'redmine-s3-presign-url'
  ensure
    ENV.delete(RedmineServerlessS3::ENV_BUCKET)
  end

  def test_nothing_is_added_without_the_bucket
    get :edit, params: { tab: 'attachments' }

    assert_select 'meta[name=?]', 'redmine-s3-presign-url', count: 0
    assert_not_includes response.body, 's3_upload'
  end
end
