# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/uploads_controller_setup'

module RedmineAws
  module S3
    # POST /s3_uploads/presign.
    class S3UploadsControllerTest < Redmine::ControllerTest
      include S3::TestHelper
      include UploadsControllerSetup

      def test_presign
        with_s3(stub_client) do
          post :presign, params: presign_params

          assert_response :success
          json = response.parsed_body

          assert json['url'].start_with?("https://#{DOMAIN}/tmp/incoming/")
          assert_nil json['headers']
          assert json['ticket'].present?
        end
      end

      def test_presign_errors_are_json
        with_s3(stub_client) do
          post :presign, params: presign_params.merge(size: 'x')

          assert_response :unprocessable_content
          assert_equal ['size is invalid'], response.parsed_body['errors']
        end
      end

      def test_presign_needs_the_upload_permission
        @request.session[:user_id] = nil
        with_s3(stub_client) do
          with_settings login_required: '1' do
            post :presign, params: presign_params

            assert_response :redirect
            assert_match %r{/login}, response.location
          end
        end
      end

      def test_not_found_without_the_bucket
        post :presign, params: presign_params

        assert_response :not_found
      end

      # As a logged-in user who may upload nowhere, and as an anonymous user
      # when the anonymous role may not upload either (403 without the REST
      # API, as Redmine answers).
      def test_presign_needs_the_upload_permission_of_a_role
        user = user_without_upload
        with_s3(stub_client) do |client|
          [user.id, nil].each do |user_id|
            @request.session[:user_id] = user_id
            post :presign, params: presign_params.merge(format: 'json')

            assert_response :forbidden, "presign as #{user_id.inspect}"
          end
          assert_empty client.api_requests
        end
      end

      # A hash or an array in place of a string is refused, or for the
      # content type ignored, instead of being turned into text.
      def test_presign_refuses_parameters_that_are_not_strings
        with_s3(stub_client) do
          [{ filename: { name: 'note.txt' } }, { filename: ['note.txt'] }, { size: [CONTENT.bytesize] },
           { size: { value: CONTENT.bytesize } }].each do |shape|
            post :presign, params: presign_params.merge(shape)

            assert_response :unprocessable_content, shape.inspect
            assert_nil response.parsed_body['ticket'], shape.inspect
          end
        end
      end

      def test_a_content_type_that_is_not_a_string_is_ignored
        with_s3(stub_client(head_object: ['NotFound', head])) do
          ticket = presigned_ticket(content_type: { type: 'text/html' })

          assert_response :success
          post :complete, params: { ticket: ticket, attachment_id: 1, format: 'js' }, xhr: true

          assert_response :success
          assert_equal 'text/plain', Attachment.last.content_type
        end
      end
    end
  end
end
