# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/avatars_in_s3_setup'

module RedmineAws
  module S3
    # Avatars of Redmine 7.1: the cropped thumbnails kept in S3, Redmine's own
    # rules for showing them, and the deletion of the files.
    class AvatarThumbnailsInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AvatarsInS3Setup

      def test_show_serves_the_cropped_thumbnail_from_s3
        with_test_s3 do
          avatar = avatar_in_another_environment
          get_avatar(100)

          assert_response :success
          assert_equal thumbnail(avatar, 100), response.body.b
          assert_not File.exist?(avatar.local_diskfile), 'the image was not read for a thumbnail in S3'
        end
      end

      def test_show_sends_the_thumbnail_as_an_inline_image
        with_test_s3 do
          avatar_in_another_environment
          get_avatar(100)

          assert_equal 'image/png', response.media_type
          assert_match(/\Ainline/, response.headers['Content-Disposition'])
          assert_equal "max-age=#{1.day.to_i}, public", response.headers['Cache-Control']
        end
      end

      def test_show_serves_the_thumbnail_of_redmines_size
        with_test_s3 do
          avatar = avatar_in_another_environment
          get_avatar(48)

          assert_response :success
          assert_equal thumbnail(avatar, 50), response.body.b
          assert_not_equal File.binread(fixture(IMAGE)).b, response.body.b
        end
      end

      def test_show_is_private_when_login_is_required
        with_test_s3 do
          jsmith_with_avatar
          with_settings(login_required: '1') { get_avatar(100) }

          assert_response :success
          assert_equal "max-age=#{1.day.to_i}, private", response.headers['Cache-Control']
        end
      end

      def test_show_needs_a_login_when_login_is_required
        with_test_s3 do
          jsmith_with_avatar
          reset!
          with_settings(login_required: '1') { get_avatar(100) }

          assert_response :redirect
          assert_match %r{/login}, response.location
        end
      end

      def test_show_checks_the_key
        with_test_s3 do
          jsmith_with_avatar
          get "/users/2/avatar/#{'0' * 16}/100"

          assert_response :not_found
        end
      end

      def test_replace_registers_the_new_avatar
        with_test_s3 do
          jsmith_with_avatar
          replace_avatar

          assert_redirected_to '/my/avatar'
          assert_avatar_from(fixture(OTHER_IMAGE), User.find(2))
        end
      end

      def test_replace_deletes_the_old_avatar_in_s3
        with_test_s3 do
          jsmith_with_avatar
          old = User.find(2).avatar
          replace_avatar

          assert_not Attachment.exists?(old.id)
          assert_nil object(old.s3_key)
          assert_empty keys("tmp/thumbnails/#{old.digest}_")
        end
      end

      def test_delete_deletes_the_avatar_in_s3
        with_test_s3 do
          jsmith_with_avatar
          avatar = User.find(2).avatar
          delete '/my/avatar'

          assert_redirected_to '/my/avatar'
          assert_nil User.find(2).avatar_id
          assert_nil object(avatar.s3_key)
          assert_empty keys('tmp/thumbnails/')
        end
      end

      private

      # jsmith's avatar seen from another environment: neither the image nor
      # its thumbnails on the disk, and a new session.
      def avatar_in_another_environment
        jsmith_with_avatar
        avatar = User.find(2).avatar
        FileUtils.rm_f(avatar.local_diskfile)
        Attachment.clear_thumbnails
        reset!
        avatar
      end

      def replace_avatar
        put '/my/avatar', params: { s3_ticket: upload(fixture(OTHER_IMAGE)).last }
      end

      # The thumbnail of the size in S3, as bytes.
      def thumbnail(avatar, size)
        object(thumbnail_key(avatar, size)).b
      end

      def get_avatar(size)
        get "/users/2/avatar/#{User.find(2).avatar_key}/#{size}"
      end
    end
  end
end
