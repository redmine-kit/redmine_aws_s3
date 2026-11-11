# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_controller_setup'

module RedmineAws
  module S3
    # "Download all": the zip kept in S3 under tmp/bulk/.
    class AttachmentsControllerDownloadAllTest < Redmine::ControllerTest
      include S3::TestHelper
      include AttachmentsControllerSetup

      def setup
        super
        @request.session[:user_id] = 2
      end

      def test_download_all_stores_the_zip_and_redirects
        with_s3(stub_client(head_object: 'NotFound')) do |client|
          path, = signed_redirect(:download_all, object_type: 'issues', object_id: 3)

          assert_match %r{\A/tmp/bulk/[0-9a-f]{64}\.zip\z}, path
          assert_equal path.delete_prefix('/'), put_request(client)[:params][:key]
        end
      end

      def test_download_all_names_the_zip
        with_s3(stub_client(head_object: 'NotFound')) do
          _, query, = signed_redirect(:download_all, object_type: 'issues', object_id: 3)

          assert_equal 'attachment; filename="issue-3-attachments.zip"; ' \
                       "filename*=UTF-8''issue-3-attachments.zip", query['response-content-disposition']
          assert_equal 'application/zip', query['response-content-type']
        end
      end

      # Redmine lets the files of an issue be renamed (Edit attachments); the
      # zip then has the new names.
      def test_download_all_after_a_rename_makes_a_new_zip
        with_s3(stub_client(head_object: 'NotFound')) do
          before, = signed_redirect(:download_all, object_type: 'issues', object_id: 3)
          Issue.find(3).attachments.find(&:readable?).update!(filename: 'renamed.txt')
          after, = signed_redirect(:download_all, object_type: 'issues', object_id: 3)

          assert_not_equal before, after
        end
      end

      def test_download_all_reuses_a_stored_zip
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          get :download_all, params: { object_type: 'issues', object_id: 3 }

          assert_response :redirect
          assert_not_includes client.api_requests.pluck(:operation_name), :put_object
        end
      end
    end
  end
end
