# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_controller_setup'

module RedmineAws
  module S3
    # Downloads of attachments through CloudFront.
    class AttachmentsControllerTest < Redmine::ControllerTest
      include S3::TestHelper
      include AttachmentsControllerSetup

      def test_download_redirects_to_a_signed_url
        with_s3(stub_client) do |client|
          path, _, expires = signed_redirect(:download, id: 4)
          a = Attachment.find(4)

          assert_equal "/files/#{a.disk_directory}/#{a.disk_filename}".squeeze('/'), path
          assert_in_delta Time.now.to_i + 300, expires, 5
          assert_empty client.api_requests, 'the local file is used for the existence check'
        end
      end

      def test_download_names_the_file_and_its_type
        with_s3(stub_client) do
          _, query, = signed_redirect(:download, id: 4)
          filename = Attachment.find(4).filename

          assert_equal "attachment; filename=\"#{filename}\"; filename*=UTF-8''#{filename}",
                       query['response-content-disposition']
          assert_equal 'application/x-ruby', query['response-content-type']
        end
      end

      def test_download_checks_s3_when_the_file_is_not_local
        a = Attachment.find(4)
        a.update_columns(disk_filename: 'only_in_s3.rb')
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          get :download, params: { id: 4 }

          assert_response :redirect
          assert_equal 'files/2006/07/only_in_s3.rb', client.api_requests.first[:params][:key]
        end
      end

      def test_download_of_a_file_missing_everywhere
        Attachment.find(4).update_columns(disk_filename: 'nowhere.rb')
        with_s3(stub_client(head_object: 'NotFound', get_object: 'NoSuchKey')) do
          get :download, params: { id: 4 }

          assert_response :not_found
        end
      end

      def test_download_keeps_redmines_permissions
        with_s3(stub_client) do
          get :download, params: { id: 7 } # an attachment of a private project

          assert_response :redirect
          assert_match %r{/login}, response.location
        end
      end

      def test_download_counts_project_files
        with_s3(stub_client) do
          assert_difference -> { Attachment.find(9).downloads } do
            get :download, params: { id: 9 }
          end
        end
      end

      def test_download_through_the_api_redirects_too
        with_s3(stub_client) do
          with_settings rest_api_enabled: '1' do
            get :download, params: { id: 4, key: User.find(2).api_key }

            assert_response :redirect
            assert response.location.start_with?("https://#{DOMAIN}/files/")
          end
        end
      end

      def test_without_the_bucket_redmine_sends_the_file
        get :download, params: { id: 4 }

        assert_response :success
        assert_equal RedmineAws::S3::ATTACHMENT_CSP, response.headers['Content-Security-Policy']
      end
    end
  end
end
