# frozen_string_literal: true

require_relative 's3_objects'

module RedmineAws
  module S3
    # The setup of the integration tests of the avatars of Redmine 7.1
    # (docs/attachments.md#avatars) with S3 reproduced by LocalStack or moto.
    # Skipped on Redmine 7.0, which has no avatars.
    module AvatarsInS3Setup
      extend ActiveSupport::Concern
      include S3Objects

      IMAGE = '2010/11/101123161450_testfile_1.png'
      OTHER_IMAGE = '2010/12/101223161450_testfile_2.png'

      included do
        fixtures :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :projects,
                 :enabled_modules
      end

      def setup
        skip 'Redmine has no avatars before 7.1' unless RedmineAws::S3.avatars?
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        set_tmp_attachments_directory
        Attachment.clear_thumbnails
      end

      def fixture(name)
        Rails.root.join('test/fixtures/files', name).to_s
      end

      # The browser's side (s3_avatar_upload.js): presign, the PUT that
      # CloudFront sends to S3 through OAC, and the check. Returns the key of
      # the upload and the ticket.
      def upload(path, filename: File.basename(path))
        key, ticket = presign_and_put(File.binread(path), filename)
        post '/s3_uploads/avatar/check', params: { ticket: ticket }
        assert_response :success
        [key, ticket]
      end

      # Presign and the PUT; returns the key of the upload and the ticket.
      def presign_and_put(data, filename)
        post '/s3_uploads/avatar/presign',
             params: { filename: filename, size: data.bytesize, content_type: 'image/png' }
        assert_response :success
        presigned = response.parsed_body
        key = URI(presigned['url']).path.delete_prefix('/')
        put_object(key, data)
        [key, presigned['ticket']]
      end

      # As jsmith, the image uploaded through CloudFront and registered by
      # Redmine's form.
      def jsmith_with_avatar(path = fixture(IMAGE))
        log_user('jsmith', 'jsmith')
        put '/my/avatar', params: { s3_ticket: upload(path).last }
      end

      def thumbnail_key(attachment, size)
        "tmp/thumbnails/#{attachment.digest}_#{attachment.filesize}_#{size}_crop.thumb"
      end

      def assert_avatar_from(path, user, author: user)
        avatar = user.reload.avatar

        assert avatar, 'the user has no avatar'
        assert_equal author, avatar.author
        assert_equal user, avatar.container
        assert_avatar_in_s3(path, avatar)
        avatar
      end

      def assert_avatar_in_s3(path, avatar)
        assert_equal File.binread(path), object(avatar.s3_key).b
        assert object(thumbnail_key(avatar, 100)), 'the thumbnail Redmine tests the image with is in S3'
        assert_empty keys('tmp/incoming/')
      end
    end
  end
end
