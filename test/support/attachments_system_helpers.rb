# frozen_string_literal: true

module RedmineAws
  module S3
    # The browser's side of the system tests of attachments
    # (system/attachments_in_s3_test.rb): an issue created with a file
    # attached through s3_upload.js, requests sent from the browser, and the
    # malware scan.
    module AttachmentsSystemHelpers
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

      FETCH_SCRIPT = <<~JS
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

      # GET url with fetch in the browser, following the redirect; returns
      # what the browser got.
      def fetch_in_browser(url)
        page.evaluate_async_script(FETCH_SCRIPT, url)
      end

      # Collects the statuses of S3UploadsController#complete.
      def subscribe_to_complete(answers)
        ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
          answers << payload[:status] if payload[:controller] == 'S3UploadsController' && payload[:action] == 'complete'
        end
      end

      # Puts the tag GuardDuty would on the upload, 2 seconds after it
      # arrives in tmp/incoming/.
      def tag_the_upload_when_it_arrives
        key = wait_for_the_upload
        sleep 2
        tag = { key: RedmineAws::S3::MalwareScan::TAG, value: 'NO_THREATS_FOUND' }
        @client.put_object_tagging(bucket: @bucket, key: key, tagging: { tag_set: [tag] })
      end

      # The key of the first upload in tmp/incoming/, waiting up to 2 minutes.
      def wait_for_the_upload
        240.times do
          key = incoming_objects.first&.key
          return key if key

          sleep 0.5
        end
        nil
      end

      # REDMINE_S3_MALWARE_SCAN=true, without waiting between the requests
      # for the scan tag (teardown deletes the variable).
      def turn_on_the_malware_scan
        ENV[RedmineAws::S3::ENV_MALWARE_SCAN] = 'true'
        RedmineAws::S3::MalwareScan.stubs(:wait_seconds).returns(0)
      end

      def thumbnails_in_s3(attachment)
        prefix = "tmp/thumbnails/#{attachment.digest}_#{attachment.filesize}_"
        @client.list_objects_v2(bucket: @bucket, prefix: prefix).contents
      end
    end
  end
end
