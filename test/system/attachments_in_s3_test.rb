# frozen_string_literal: true

require File.expand_path('../../../../test/application_system_test_case', __dir__)
require_relative '../test_helper'
require_relative 'fake_cloudfront'

module RedmineAws
  module S3
    # The browser side (assets/javascripts/s3_upload.js) in headless Chrome:
    # uploads through the fake CloudFront to the S3 of the tests (LocalStack or
    # moto), the 202 of the malware scan, downloads and thumbnails through signed
    # URLs. bin/test system runs them with Selenium in its own container.
    class AttachmentsSystemTest < ApplicationSystemTestCase
      include S3::TestHelper

      fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :trackers, :projects_trackers,
               :enabled_modules, :issue_statuses, :issues, :enumerations, :custom_fields, :custom_values,
               :custom_fields_trackers, :watchers, :journals, :journal_details, :workflows

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
        @client = s3_test_client
        @bucket = "redmine-system-#{SecureRandom.hex(6)}"
        @client.create_bucket(bucket: @bucket)
        @saved_env = s3_env.keys.index_with { |name| ENV.fetch(name, nil) }
        app = URI(Capybara.app_host)
        s3_env(bucket: @bucket).merge(RedmineAws::S3::ENV_DOMAIN => "#{app.host}:#{app.port}")
                               .each { |name, value| ENV[name] = value }
        RedmineAws::S3.client = @client
        page.driver.browser.file_detector = ->(args) { args.first.to_s if File.exist?(args.first.to_s) }
        page.driver.browser.manage.timeouts.script_timeout = 60
      end

      # On moto, HeadObject is given the checksum S3 would return (test_helper.rb).
      def run(...)
        emulate_s3_checksums { super }
      end

      def teardown
        @saved_env&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
        ENV.delete(RedmineAws::S3::ENV_MALWARE_SCAN)
        RedmineAws::S3.client = nil
      end

      def object(key)
        @client.get_object(bucket: @bucket, key: key).body.read
      rescue ::Aws::S3::Errors::NoSuchKey
        nil
      end

      # Records the values Redmine's progress bar is given.
      def record_progress
        page.execute_script(<<~JS)
          window.s3Progress = [];
          var original = $.fn.progressbar;
          $.fn.progressbar = function(name, key, value) {
            if (name === 'value') { window.s3Progress.push(key); }
            return original.apply(this, arguments);
          };
        JS
      end

      # Waits for the token that the completed upload puts into the form; the
      # message shows what Redmine displayed when the upload failed.
      def attach_and_wait(path)
        attach_file 'attachments[dummy][file]', path
        uploaded = 240.times.any? do
          token = page.evaluate_script("$('.attachments_fields input.token').val()")
          break true if token.present?

          sleep 0.5
          false
        end
        assert uploaded, "no token; the form shows: #{find('.attachments_fields', visible: :all).text(:all)}"
      end

      def create_issue_with(path)
        log_user('jsmith', 'jsmith')
        visit '/projects/ecookbook/issues/new'
        fill_in 'Subject', with: "With #{File.basename(path)}"
        record_progress
        attach_and_wait(path)
        @progress = page.evaluate_script('window.s3Progress')
        click_on 'Create'
        assert_text(/Issue #\d+ created/)
        Issue.last
      end

      def test_upload_through_cloudfront_with_progress
        path = Rails.root.join('test/fixtures/files/testfile.txt')
        issue = create_issue_with(path)
        attachment = issue.attachments.first

        assert_equal 'testfile.txt', attachment.filename
        assert_equal File.binread(path), object(attachment.s3_key)
        assert_equal Digest::SHA256.file(path).hexdigest, attachment.digest
        assert_empty @client.list_objects_v2(bucket: @bucket, prefix: 'tmp/incoming/').contents
        assert_predicate @progress, :present?, 'the progress bar got no value'
        assert_in_delta 100, @progress.last.to_f, 0.01
      end

      def test_download_redirects_to_the_file_with_the_headers_of_the_distribution
        issue = create_issue_with(Rails.root.join('test/fixtures/files/testfile.txt'))
        attachment = issue.attachments.first
        result = page.evaluate_async_script(<<~JS, "/attachments/download/#{attachment.id}/testfile.txt")
          var done = arguments[arguments.length - 1];
          fetch(arguments[0]).then(function(response) {
            return response.text().then(function(text) {
              done({ redirected: response.redirected, url: response.url, status: response.status, text: text,
                     csp: response.headers.get('content-security-policy'),
                     nosniff: response.headers.get('x-content-type-options'),
                     disposition: response.headers.get('content-disposition') });
            });
          });
        JS

        assert result['redirected']
        assert_includes result['url'], "/#{attachment.s3_key}?"
        assert_equal 200, result['status']
        assert_equal File.read(Rails.root.join('test/fixtures/files/testfile.txt')), result['text']
        assert_equal RedmineAws::S3::ATTACHMENT_CSP, result['csp']
        assert_equal 'nosniff', result['nosniff']
        assert_match(/\Aattachment; filename="testfile.txt"/, result['disposition'])
      end

      def test_thumbnails_are_shown_from_s3
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        Setting.thumbnails_enabled = '1'
        issue = create_issue_with(Rails.root.join('test/fixtures/files/2010/11/101123161450_testfile_1.png'))
        visit "/issues/#{issue.id}"
        image = find('.thumbnails img')
        assert page.evaluate_script('arguments[0].complete && arguments[0].naturalWidth > 0', image),
               'the thumbnail did not load'
        attachment = issue.attachments.first

        prefix = "tmp/thumbnails/#{attachment.digest}_#{attachment.filesize}_"
        thumbnails = @client.list_objects_v2(bucket: @bucket, prefix: prefix)

        assert_not_empty thumbnails.contents, 'the thumbnail is not in S3'
      end

      def test_the_upload_waits_for_the_malware_scan
        ENV[RedmineAws::S3::ENV_MALWARE_SCAN] = 'true'
        RedmineAws::S3::MalwareScan.stubs(:wait_seconds).returns(0)
        answers = []
        subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
          answers << payload[:status] if payload[:controller] == 'S3UploadsController' && payload[:action] == 'complete'
        end
        scanner = Thread.new do
          key = nil
          240.times do
            key = @client.list_objects_v2(bucket: @bucket, prefix: 'tmp/incoming/').contents.first&.key
            break if key

            sleep 0.5
          end
          sleep 2
          tag = { key: RedmineAws::S3::MalwareScan::TAG, value: 'NO_THREATS_FOUND' }
          @client.put_object_tagging(bucket: @bucket, key: key, tagging: { tag_set: [tag] })
        end
        issue = create_issue_with(Rails.root.join('test/fixtures/files/testfile.txt'))
        scanner.join

        assert_equal 'testfile.txt', issue.attachments.first.filename
        assert_includes answers, 202
        assert_equal 200, answers.last
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end
    end
  end
end
