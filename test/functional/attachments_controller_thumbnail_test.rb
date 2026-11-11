# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_controller_setup'

module RedmineAws
  module S3
    # Thumbnails kept in S3 under tmp/thumbnails/.
    class AttachmentsControllerThumbnailTest < Redmine::ControllerTest
      include S3::TestHelper
      include AttachmentsControllerSetup

      def test_thumbnail_redirects_to_the_stored_thumbnail
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          @request.session[:user_id] = 1
          path, = signed_redirect(:thumbnail, id: 16, size: 100)
          a = Attachment.find(16)

          assert_equal 'max-age=300, private', response.headers['Cache-Control']
          assert_equal "/tmp/thumbnails/#{a.digest}_#{a.filesize}_100.thumb", path
          assert_not_includes client.api_requests.pluck(:operation_name), :put_object
        end
      end

      def test_thumbnail_is_sent_as_an_image_attachment
        with_s3(stub_client(head_object: { content_length: 1 })) do
          @request.session[:user_id] = 1
          _, query, = signed_redirect(:thumbnail, id: 16, size: 100)

          assert_equal 'image/png', query['response-content-type']
          assert query['response-content-disposition'].start_with?('attachment;')
        end
      end

      def test_thumbnail_is_made_and_stored_when_s3_does_not_have_it
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        Attachment.clear_thumbnails
        with_s3(stub_client(head_object: 'NotFound', get_object: 'NoSuchKey')) do |client|
          @request.session[:user_id] = 1
          get :thumbnail, params: { id: 16, size: 100 }
          a = Attachment.find(16)

          assert_response :redirect
          assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_100.thumb", put_request(client)[:params][:key]
        end
      end

      def test_no_thumbnail_for_a_file_larger_than_the_cache
        Attachment.find(16).update_columns(filesize: 300.megabytes)
        with_s3(stub_client(head_object: 'NotFound')) do
          @request.session[:user_id] = 1
          get :thumbnail, params: { id: 16, size: 100 }

          assert_response :not_found
        end
      end
    end
  end
end
