# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Redmine 7.0 has no avatar form: nothing of the avatar upload is there.
    class AvatarsBefore71Test < Redmine::IntegrationTest
      include S3::TestHelper

      fixtures :users, :email_addresses, :user_preferences

      def setup
        skip 'Redmine has avatars (7.1)' if RedmineAws::S3.avatars?
      end

      def test_no_avatar_upload
        with_s3(stub_client) do
          log_user('jsmith', 'jsmith')
          post '/s3_uploads/avatar/presign', params: { filename: 'a.png', size: 1 }

          assert_response :not_found
          get '/my/account'

          assert_response :success
          assert_select 'meta[name=redmine-s3-avatar-presign-url]', 0
        end
      end
    end
  end
end
