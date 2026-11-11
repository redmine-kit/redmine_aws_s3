# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    class S3UploadsControllerTest < Redmine::ControllerTest
      include S3::TestHelper

      tests S3UploadsController

      fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

      CONTENT = 'from the browser'

      def setup
        set_tmp_attachments_directory
        @request.session[:user_id] = 2
      end

      def head
        { content_length: CONTENT.bytesize, checksum_sha256: sha256_base64(CONTENT), checksum_type: 'FULL_OBJECT' }
      end

      def presign_params
        { filename: 'note.txt', size: CONTENT.bytesize, content_type: 'text/plain' }
      end

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

      # Each action as a logged-in user who may upload nowhere, and as an
      # anonymous user when the anonymous role may not upload either (403
      # without the REST API, as Redmine answers).
      def test_presign_and_complete_need_the_upload_permission
        [Role.anonymous, Role.non_member].each { |role| role.update!(permissions: [:view_issues]) }
        user = User.generate!
        with_s3(stub_client) do |client|
          [[user.id, :forbidden], [nil, :forbidden]].each do |user_id, status|
            @request.session[:user_id] = user_id
            post :presign, params: presign_params.merge(format: 'json')

            assert_response status, "presign as #{user_id.inspect}"
            post :complete, params: { ticket: 'bad', format: 'json' }

            assert_response status, "complete as #{user_id.inspect}"
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
          post :presign, params: presign_params.merge(content_type: { type: 'text/html' })

          assert_response :success
          post :complete, params: { ticket: response.parsed_body['ticket'], attachment_id: 1, format: 'js' },
                          xhr: true

          assert_response :success
          assert_equal 'text/plain', Attachment.last.content_type
        end
      end

      def test_complete_returns_the_script_of_redmines_upload
        with_s3(stub_client(head_object: ['NotFound', head])) do
          post :presign, params: presign_params
          ticket = response.parsed_body['ticket']

          assert_difference 'Attachment.count' do
            post :complete, params: { ticket: ticket, attachment_id: 7, format: 'js' }, xhr: true
          end
          assert_response :success
          attachment = Attachment.last

          assert_include "$('#attachments_7')", response.body
          assert_include attachment.token, response.body
          assert_equal 'note.txt', attachment.filename
        end
      end

      def test_complete_errors_are_json
        with_s3(stub_client(head_object: 'NotFound')) do
          post :complete, params: { ticket: 'bad', attachment_id: 1, format: 'js' }, xhr: true

          assert_response :unprocessable_content
          assert_equal ['the upload ticket is invalid or expired'], response.parsed_body['errors']
        end
      end

      def test_complete_through_the_api
        @request.session[:user_id] = nil
        with_settings rest_api_enabled: '1' do
          with_s3(stub_client(head_object: ['NotFound', head])) do
            key = User.find(2).api_key
            post :presign, params: presign_params.merge(format: 'json', key: key)

            assert_response :success
            post :complete, params: { ticket: response.parsed_body['ticket'], format: 'json', key: key }

            assert_response :created
            assert_equal Attachment.last.token, response.parsed_body['upload']['token']
          end
        end
      end

      def test_complete_api_errors
        @request.session[:user_id] = nil
        with_settings rest_api_enabled: '1' do
          with_s3(stub_client) do
            post :complete, params: { ticket: 'bad', format: 'json', key: User.find(2).api_key }

            assert_response :unprocessable_content
            assert_equal ['the upload ticket is invalid or expired'], response.parsed_body['errors']
          end
        end
      end

      def test_complete_answers_202_while_the_scan_runs
        with_s3(stub_client(get_object_tagging: { tag_set: [] })) do
          with_malware_scan do
            post :presign, params: presign_params
            ticket = response.parsed_body['ticket']

            assert_no_difference 'Attachment.count' do
              post :complete, params: { ticket: ticket, attachment_id: 1, format: 'js' }, xhr: true
            end
            assert_response :accepted
            assert_equal 'scanning', response.parsed_body['status']
            assert_equal '2', response.headers['Retry-After']
          end
        end
      end

      def test_complete_through_the_api_answers_202_while_the_scan_runs
        @request.session[:user_id] = nil
        with_settings rest_api_enabled: '1' do
          with_s3(stub_client(get_object_tagging: { tag_set: [] })) do
            with_malware_scan do
              key = User.find(2).api_key
              post :presign, params: presign_params.merge(format: 'json', key: key)
              post :complete, params: { ticket: response.parsed_body['ticket'], format: 'json', key: key }

              assert_response :accepted
            end
          end
        end
      end
    end
  end
end
