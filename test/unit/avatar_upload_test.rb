# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # AvatarUpload#open: the upload of an avatar read from S3 (docs/attachments.md#avatars).
    class AvatarUploadTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      def avatar_ticket(size: CONTENT.bytesize, **)
        avatar_upload.presign(filename: 'a.png', size: size, **)[:ticket]
      end

      # Opens an avatar upload one byte larger than declared; returns the error.
      def open_a_larger_avatar
        ticket = avatar_ticket
        assert_raises(RedmineAws::S3::Upload::Error) { avatar_upload.open(ticket) { flunk } }
      end

      # A signed URL does not limit what is PUT to it: an avatar upload larger
      # than declared is read only up to one byte over its size.
      def test_an_avatar_upload_is_read_up_to_one_byte_over_its_size
        with_s3(stub_client(get_object: { body: "#{CONTENT}x" })) do |client|
          error = open_a_larger_avatar

          assert_equal 'the uploaded file does not match its size', error.message
          assert_equal "bytes=0-#{CONTENT.bytesize}", api_request(client, :get_object)[:params][:range]
          assert_includes client.api_requests.pluck(:operation_name), :delete_objects
        end
      end

      def test_an_avatar_upload_of_the_declared_size
        with_s3(stub_client(get_object: { body: CONTENT })) do |client|
          ticket = avatar_ticket(content_type: 'image/png')
          read = avatar_upload.open(ticket) { |file| [file.original_filename, file.content_type, file.read] }

          assert_equal ['a.png', 'image/png', CONTENT], read
          assert_equal "bytes=0-#{CONTENT.bytesize}", api_request(client, :get_object)[:params][:range]
        end
      end

      def test_an_empty_avatar_upload_is_not_read
        with_s3(stub_client) do |client|
          ticket = avatar_ticket(size: 0)

          assert_equal 0, avatar_upload.open(ticket, &:size)
          assert_not_includes client.api_requests.pluck(:operation_name), :get_object
        end
      end
    end
  end
end
