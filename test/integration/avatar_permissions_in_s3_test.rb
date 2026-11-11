# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/avatars_in_s3_setup'

module RedmineAws
  module S3
    # Avatars of Redmine 7.1: who may upload which avatar, and the files
    # Redmine refuses.
    class AvatarPermissionsInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AvatarsInS3Setup

      def test_an_administrator_uploads_for_another_user
        with_test_s3 do
          log_user('admin', 'admin')
          put '/users/2/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }

          assert_redirected_to '/users/2/avatar'
          assert_avatar_from(fixture(IMAGE), User.find(2), author: User.find(1))
          assert_nil User.find(1).avatar_id
        end
      end

      def test_only_an_administrator_changes_another_users_avatar
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          put '/users/3/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }

          assert_response :forbidden
          assert_nil User.find(3).avatar_id
        end
      end

      def test_the_ticket_of_another_user_is_refused
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          _, ticket = upload(fixture(IMAGE))
          reset!
          log_user('admin', 'admin')
          put '/my/avatar', params: { s3_ticket: ticket }

          assert_response :unprocessable_content
          assert_select '#errorExplanation', text: /the upload ticket is invalid or expired/
          assert_nil User.find(1).avatar_id
        end
      end

      def test_a_file_that_is_not_an_image_is_refused_as_redmine_refuses_it
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          key, ticket = upload(fixture('testfile.txt'), filename: 'not-an-image.png')
          put '/my/avatar', params: { s3_ticket: ticket }

          assert_response :unprocessable_content
          assert_select '#errorExplanation', text: /Avatar is invalid/
          assert_nil User.find(2).avatar_id
          assert_nil object(key)
          assert_empty keys('files/')
        end
      end

      def test_presign_checks_the_size
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          with_settings attachment_max_size: '1' do
            post '/s3_uploads/avatar/presign', params: { filename: 'big.png', size: 2.kilobytes }
          end

          assert_response :unprocessable_content
          assert_match(/exceeds the maximum allowed file size/, response.parsed_body['errors'].first)
        end
      end

      def test_presign_needs_a_login
        with_test_s3 do
          post '/s3_uploads/avatar/presign', params: { filename: 'a.png', size: 1 }

          assert_response :redirect
          assert_match %r{/login}, response.location
        end
      end
    end
  end
end
