# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_in_s3_setup'

module RedmineAws
  module S3
    # Rails logs every redirect. A CloudFront signed URL opens a private file
    # for anyone until it expires, so the log has [FILTERED] instead.
    class SignedUrlLogTest < Redmine::IntegrationTest
      include S3::TestHelper
      include AttachmentsInS3Setup

      def test_the_signed_url_of_a_download_is_not_logged
        with_test_s3 do
          attachment = create_attachment(mock_file(filename: 'secret.txt', content: 'secret'))
          log_user('admin', 'admin')
          log = rails_log { get "/attachments/download/#{attachment.id}/secret.txt" }

          assert_response :redirect
          assert_includes response.location, 'Key-Pair-Id='
          assert_includes log, 'Redirected to [FILTERED]'
          assert_not_includes log, 'Key-Pair-Id'
        end
      end

      # setup runs again on every code reload.
      def test_the_filter_is_added_once
        2.times { RedmineAws::S3::LogFilter.install }

        assert_equal 1, Rails.application.config.filter_redirect.count(RedmineAws::S3::LogFilter::SIGNED_URL)
      end

      private

      # Everything that the block writes to Rails' log.
      def rails_log
        io = StringIO.new
        logger = ActiveSupport::Logger.new(io)
        Rails.logger.broadcast_to(logger)
        yield
        io.string
      ensure
        Rails.logger.stop_broadcasting_to(logger)
      end
    end
  end
end
