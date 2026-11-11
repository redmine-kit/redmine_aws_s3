# frozen_string_literal: true

module RedmineAws
  module S3
    # The setup of the tests of POST /s3_uploads/presign and complete, which
    # are split by action.
    module UploadsControllerSetup
      extend ActiveSupport::Concern

      CONTENT = 'from the browser'

      included do
        tests S3UploadsController

        fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules
      end

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

      # The ticket of a presign with the given parameters.
      def presigned_ticket(**params)
        post :presign, params: presign_params.merge(params)
        response.parsed_body['ticket']
      end

      # Runs the block through the REST API, without a session; yields the
      # API key of jsmith.
      def with_api
        @request.session[:user_id] = nil
        with_settings(rest_api_enabled: '1') { yield User.find(2).api_key }
      end

      # The anonymous role and non-members may not upload; returns a user
      # who is a member of no project.
      def user_without_upload
        [Role.anonymous, Role.non_member].each { |role| role.update!(permissions: [:view_issues]) }
        User.generate!
      end
    end
  end
end
