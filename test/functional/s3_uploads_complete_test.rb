# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/uploads_controller_setup'

module RedmineAws
  module S3
    # POST /s3_uploads/complete.
    class S3UploadsCompleteTest < Redmine::ControllerTest
      include S3::TestHelper
      include UploadsControllerSetup

      # As in S3UploadsControllerTest, for complete.
      def test_complete_needs_the_upload_permission_of_a_role
        user = user_without_upload
        with_s3(stub_client) do |client|
          [user.id, nil].each do |user_id|
            @request.session[:user_id] = user_id
            post :complete, params: { ticket: 'bad', format: 'json' }

            assert_response :forbidden, "complete as #{user_id.inspect}"
          end
          assert_empty client.api_requests
        end
      end

      def test_complete_registers_the_attachment
        with_s3(stub_client(head_object: ['NotFound', head])) do
          ticket = presigned_ticket

          assert_difference 'Attachment.count' do
            post :complete, params: { ticket: ticket, attachment_id: 7, format: 'js' }, xhr: true
          end
          assert_response :success
          assert_equal 'note.txt', Attachment.last.filename
        end
      end

      def test_complete_returns_the_script_of_redmines_upload
        with_s3(stub_client(head_object: ['NotFound', head])) do
          post :complete, params: { ticket: presigned_ticket, attachment_id: 7, format: 'js' }, xhr: true

          assert_include "$('#attachments_7')", response.body
          assert_include Attachment.last.token, response.body
        end
      end

      def test_complete_errors_are_json
        with_s3(stub_client(head_object: 'NotFound')) do
          post :complete, params: { ticket: 'bad', attachment_id: 1, format: 'js' }, xhr: true

          assert_response :unprocessable_content
          assert_equal ['The upload has expired. Add the file again.'], response.parsed_body['errors']
        end
      end

      def test_complete_through_the_api
        with_api do |key|
          with_s3(stub_client(head_object: ['NotFound', head])) do
            ticket = presigned_ticket(format: 'json', key: key)

            assert_response :success
            post :complete, params: { ticket: ticket, format: 'json', key: key }

            assert_response :created
            assert_equal Attachment.last.token, response.parsed_body['upload']['token']
          end
        end
      end

      def test_complete_api_errors
        with_api do |key|
          with_s3(stub_client) do
            post :complete, params: { ticket: 'bad', format: 'json', key: key }

            assert_response :unprocessable_content
            assert_equal ['The upload has expired. Add the file again.'], response.parsed_body['errors']
          end
        end
      end

      def test_complete_answers_202_while_the_scan_runs
        with_s3(stub_client(get_object_tagging: { tag_set: [] })) do
          with_malware_scan do
            assert_no_difference 'Attachment.count' do
              post :complete, params: { ticket: presigned_ticket, attachment_id: 1, format: 'js' }, xhr: true
            end
            assert_response :accepted
            assert_equal 'scanning', response.parsed_body['status']
            assert_equal '2', response.headers['Retry-After']
          end
        end
      end

      def test_complete_through_the_api_answers_202_while_the_scan_runs
        with_api do |key|
          with_s3(stub_client(get_object_tagging: { tag_set: [] })) do
            with_malware_scan do
              post :complete, params: { ticket: presigned_ticket(format: 'json', key: key), format: 'json', key: key }

              assert_response :accepted
            end
          end
        end
      end
    end
  end
end
