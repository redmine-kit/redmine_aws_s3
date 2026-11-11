# frozen_string_literal: true

module RedmineAws
  module S3
    # The S3 of the system tests: a bucket of its own in the S3 of the tests
    # (LocalStack or moto), reached through the fake CloudFront of the test
    # server.
    module SystemS3Setup
      # Creates the bucket and turns the plugin on with it.
      def use_test_bucket
        @client = s3_test_client
        @bucket = "redmine-system-#{SecureRandom.hex(6)}"
        @client.create_bucket(bucket: @bucket)
        @saved_env = s3_env.keys.index_with { |name| ENV.fetch(name, nil) }
        system_s3_env.each { |name, value| ENV[name] = value }
        RedmineAws::S3.client = @client
        send_local_files
      end

      # The plugin's variables, with the domain of the fake CloudFront on the
      # test server.
      def system_s3_env
        app = URI(Capybara.app_host)
        s3_env(bucket: @bucket).merge(RedmineAws::S3::ENV_DOMAIN => "#{app.host}:#{app.port}")
      end

      # Files given to attach_file are sent from this container to the browser.
      def send_local_files
        page.driver.browser.file_detector = ->(args) { args.first.to_s if File.exist?(args.first.to_s) }
      end

      def restore_s3_env
        @saved_env&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
        RedmineAws::S3.client = nil
      end

      def incoming_objects
        @client.list_objects_v2(bucket: @bucket, prefix: 'tmp/incoming/').contents
      end

      def assert_image_loaded(image, message)
        assert page.evaluate_script('arguments[0].complete && arguments[0].naturalWidth > 0', image), message
      end
    end
  end
end
