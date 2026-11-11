# frozen_string_literal: true

module RedmineAws
  module S3
    # The setup of the tests of the "S3" tab, which are split by subject
    # (settings, connection tests, consistency check).
    module AdminControllerSetup
      extend ActiveSupport::Concern

      included do
        tests AwsS3AdminController

        fixtures :users
      end

      def setup
        @request.session[:user_id] = 1
      end

      def teardown
        Setting.plugin_redmine_aws_s3 = {}
      end
    end
  end
end
