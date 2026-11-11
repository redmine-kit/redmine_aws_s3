# frozen_string_literal: true

require_relative '../test_helper'
require File.join(Redmine::Plugin.find(:redmine_aws).directory, 'test/support/redmine_aws/screenshot_case')

module RedmineAws
  module S3
    # The "S3" tab of docs/admin.md, after "Read/write
    # test" against the S3 of the tests (moto). The bucket, the CloudFront
    # domain and key pair, the finding and the reconciliation are examples.
    class ScreenshotsTest < ScreenshotCase
      include S3::TestHelper

      self.docs = File.expand_path('../../docs', __dir__)

      BUCKET = 'redmine-files-111122223333'
      ENVIRONMENT = {
        RedmineAws::S3::ENV_BUCKET => BUCKET,
        RedmineAws::S3::ENV_REGION => 'ap-northeast-1',
        RedmineAws::S3::ENV_DOMAIN => 'redmine.example.com',
        RedmineAws::S3::ENV_KEY_PAIR_ID => 'K2EXAMPLE7QW5F',
        RedmineAws::S3::ENV_MALWARE_SCAN => 'true'
      }.freeze

      def setup
        super
        environment = ENVIRONMENT.merge(S3::ENV_PRIVATE_KEY => S3::TestHelper.private_key.to_pem)
        @saved = environment.keys.index_with { |name| ENV.fetch(name, nil) }
        ENV.update(environment)
        RedmineAws::S3.client = bucket_client
        RedmineAws::S3.update_settings('malware_findings' => [finding], 'reconciliation' => reconciliation)
      end

      def teardown
        @saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
        RedmineAws::S3.client = nil
      end

      # The S3 of the tests, with the example bucket.
      def bucket_client
        client = s3_test_client
        client.create_bucket(bucket: BUCKET) unless client.list_buckets.buckets.any? { |b| b.name == BUCKET }
        client
      end

      def finding
        { 'time' => 3.days.ago.utc.iso8601, 'status' => 'THREATS_FOUND', 'filename' => 'invoice.pdf.exe',
          'key' => 'incoming/example', 'user' => 'jsmith' }
      end

      def reconciliation
        { 'started_at' => 1.day.ago.utc.iso8601, 'finished_at' => 1.day.ago.utc.iso8601,
          'attachments' => 1284, 'objects' => 1285, 'missing_count' => 0, 'unused_count' => 1,
          'missing' => [], 'unused' => ['2026/10/261014093112_draft.docx'] }
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
  end
end
