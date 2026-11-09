# frozen_string_literal: true

require_relative 'screenshot_case'
require_relative '../test_helper'

# The "Attachments in S3" tab of docs/admin.md, after "Check reading and
# writing" against the S3 of the tests (moto). The bucket, the CloudFront
# domain and key pair, the finding and the reconciliation are examples.
class RedmineServerlessS3Screens < ScreenshotCase
  include RedmineServerlessS3::TestHelper

  BUCKET = 'redmine-files-111122223333'
  ENVIRONMENT = {
    RedmineServerlessS3::ENV_BUCKET => BUCKET,
    RedmineServerlessS3::ENV_REGION => 'ap-northeast-1',
    RedmineServerlessS3::ENV_DOMAIN => 'redmine.example.com',
    RedmineServerlessS3::ENV_KEY_PAIR_ID => 'K2EXAMPLE7QW5F',
    RedmineServerlessS3::ENV_MALWARE_SCAN => 'true'
  }.freeze

  def setup
    super
    environment = ENVIRONMENT.merge(RedmineServerlessS3::ENV_PRIVATE_KEY => RedmineServerlessS3::TestHelper.private_key.to_pem)
    @saved = environment.keys.index_with { |name| ENV.fetch(name, nil) }
    ENV.update(environment)
    client = s3_test_client
    client.create_bucket(bucket: BUCKET) unless client.list_buckets.buckets.any? { |b| b.name == BUCKET }
    RedmineServerlessS3.client = client
    RedmineServerlessS3.update_settings(
      'malware_findings' => [{ 'time' => 3.days.ago.utc.iso8601, 'status' => 'THREATS_FOUND',
                               'filename' => 'invoice.pdf.exe', 'key' => 'incoming/example', 'user' => 'jsmith' }],
      'reconciliation' => { 'started_at' => 1.day.ago.utc.iso8601, 'finished_at' => 1.day.ago.utc.iso8601,
                            'attachments' => 1284, 'objects' => 1285, 'missing_count' => 0, 'unused_count' => 1,
                            'missing' => [], 'unused' => ['2026/10/261014093112_draft.docx'] }
    )
  end

  def teardown
    @saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    RedmineServerlessS3.client = nil
  end

  def test_screens
    each_language do |language|
      visit '/admin/serverless/s3'
      click_link I18n.t(:button_redmine_serverless_s3_read_write, locale: language)
      assert_selector '#serverless-s3-checks'
      shoot 's3-admin', language
    end
  end
end
