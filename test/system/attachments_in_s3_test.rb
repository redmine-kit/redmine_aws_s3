# frozen_string_literal: true

require File.expand_path('../../../../test/application_system_test_case', __dir__)
require_relative '../test_helper'
require_relative '../support/system_s3_setup'
require_relative '../support/attachments_system_helpers'
require_relative 'fake_cloudfront'

module RedmineAws
  module S3
    # The browser side (assets/javascripts/s3_upload.js) in headless Chrome:
    # uploads through the fake CloudFront to the S3 of the tests (LocalStack or
    # moto), the 202 of the malware scan, downloads and thumbnails through signed
    # URLs. bin/test system runs them with Selenium in its own container.
    class AttachmentsSystemTest < ApplicationSystemTestCase
      include S3::TestHelper
      include SystemS3Setup
      include AttachmentsSystemHelpers

      fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :trackers, :projects_trackers,
               :enabled_modules, :issue_statuses, :issues, :enumerations, :custom_fields, :custom_values,
               :custom_fields_trackers, :watchers, :journals, :journal_details, :workflows

      TESTFILE = Rails.root.join('test/fixtures/files/testfile.txt')

      # The browser reaches the fake CloudFront on the test server over http;
      # the URL is signed as Redmine signs it, with https.
      module HttpUrls
        def url_for(...)
          super.sub(%r{\Ahttps://}, 'http://')
        end
      end
      RedmineAws::S3::UrlSigner.prepend(HttpUrls)
      Capybara.app = RedmineAws::S3::FakeCloudFront.new(
        Rails.application, public_key: RedmineAws::S3::TestHelper.private_key.public_key
      )

      def setup
        set_tmp_attachments_directory
        use_test_bucket
        page.driver.browser.manage.timeouts.script_timeout = 60
      end

      # On moto, HeadObject is given the checksum S3 would return (test_helper.rb).
      def run(...)
        emulate_s3_checksums { super }
      end

      def teardown
        restore_s3_env
        ENV.delete(RedmineAws::S3::ENV_MALWARE_SCAN)
      end

      def test_upload_through_cloudfront_with_progress
        attachment = create_issue_with(TESTFILE).attachments.first

        assert_equal 'testfile.txt', attachment.filename
        assert_stored(attachment, TESTFILE)
        assert_empty incoming_objects
        assert_predicate @progress, :present?, 'the progress bar got no value'
        assert_in_delta 100, @progress.last.to_f, 0.01
      end

      def test_download_redirects_to_the_file_with_the_headers_of_the_distribution
        attachment = create_issue_with(TESTFILE).attachments.first
        result = fetch_in_browser("/attachments/download/#{attachment.id}/testfile.txt")

        assert_redirected_to_the_file(result, attachment)
        assert_equal RedmineAws::S3::ATTACHMENT_CSP, result['csp']
        assert_equal 'nosniff', result['nosniff']
        assert_match(/\Aattachment; filename="testfile.txt"/, result['disposition'])
      end

      def test_thumbnails_are_shown_from_s3
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        Setting.thumbnails_enabled = '1'
        issue = create_issue_with(Rails.root.join('test/fixtures/files/2010/11/101123161450_testfile_1.png'))
        visit "/issues/#{issue.id}"
        assert_image_loaded(find('.thumbnails img'), 'the thumbnail did not load')

        assert_not_empty thumbnails_in_s3(issue.attachments.first), 'the thumbnail is not in S3'
      end

      def test_the_upload_waits_for_the_malware_scan
        turn_on_the_malware_scan
        answers = []
        subscriber = subscribe_to_complete(answers)
        issue = while_tagging_the_upload { create_issue_with(TESTFILE) }

        assert_equal 'testfile.txt', issue.attachments.first.filename
        assert_includes answers, 202
        assert_equal 200, answers.last
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end

      private

      # Runs the block while another thread tags the upload as GuardDuty would.
      def while_tagging_the_upload
        scanner = Thread.new { tag_the_upload_when_it_arrives }
        result = yield
        scanner.join
        result
      end

      def assert_stored(attachment, path)
        assert_equal File.binread(path), object(attachment.s3_key)
        assert_equal Digest::SHA256.file(path).hexdigest, attachment.digest
      end

      def assert_redirected_to_the_file(result, attachment)
        assert result['redirected']
        assert_includes result['url'], "/#{attachment.s3_key}?"
        assert_equal 200, result['status']
        assert_equal File.read(TESTFILE), result['text']
      end
    end
  end
end
