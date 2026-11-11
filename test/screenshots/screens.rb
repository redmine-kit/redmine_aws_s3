# frozen_string_literal: true

require_relative '../test_helper'
require File.join(Redmine::Plugin.find(:redmine_aws).directory, 'test/support/redmine_aws/screenshot_case')

# The "S3" tab of docs/admin.md, after "Read/write
# test" against the S3 of the tests (moto). The bucket, the CloudFront
# domain and key pair, the finding and the reconciliation are examples.
class RedmineAwsS3Screens < RedmineAws::ScreenshotCase
  include RedmineAwsS3::TestHelper

  self.docs = File.expand_path('../../docs', __dir__)

  BUCKET = 'redmine-files-111122223333'
  ENVIRONMENT = {
    RedmineAwsS3::ENV_BUCKET => BUCKET,
    RedmineAwsS3::ENV_REGION => 'ap-northeast-1',
    RedmineAwsS3::ENV_DOMAIN => 'redmine.example.com',
    RedmineAwsS3::ENV_KEY_PAIR_ID => 'K2EXAMPLE7QW5F',
    RedmineAwsS3::ENV_MALWARE_SCAN => 'true'
  }.freeze

  def setup
    super
    environment = ENVIRONMENT.merge(RedmineAwsS3::ENV_PRIVATE_KEY => RedmineAwsS3::TestHelper.private_key.to_pem)
    @saved = environment.keys.index_with { |name| ENV.fetch(name, nil) }
    ENV.update(environment)
    client = s3_test_client
    client.create_bucket(bucket: BUCKET) unless client.list_buckets.buckets.any? { |b| b.name == BUCKET }
    RedmineAwsS3.client = client
    RedmineAwsS3.update_settings(
      'malware_findings' => [{ 'time' => 3.days.ago.utc.iso8601, 'status' => 'THREATS_FOUND',
                               'filename' => 'invoice.pdf.exe', 'key' => 'incoming/example', 'user' => 'jsmith' }],
      'reconciliation' => { 'started_at' => 1.day.ago.utc.iso8601, 'finished_at' => 1.day.ago.utc.iso8601,
                            'attachments' => 1284, 'objects' => 1285, 'missing_count' => 0, 'unused_count' => 1,
                            'missing' => [], 'unused' => ['2026/10/261014093112_draft.docx'] }
    )
  end

  def teardown
    @saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    RedmineAwsS3.client = nil
  end

  def test_screens
    each_language do |language|
      visit '/admin/aws/s3'
      click_link I18n.t(:button_aws_s3_read_write, locale: language)
      assert_selector '#aws-s3-checks'
      shoot 's3-admin', language
    end
  end
end
