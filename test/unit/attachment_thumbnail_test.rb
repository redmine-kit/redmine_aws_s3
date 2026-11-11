# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Thumbnails kept in S3 under tmp/thumbnails/.
    class AttachmentThumbnailTest < ActiveSupport::TestCase
      include S3::AttachmentTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      def setup
        super
        Attachment.clear_thumbnails
      end

      def teardown
        set_tmp_attachments_directory
        Attachment.clear_thumbnails
      end

      def test_no_thumbnail_beyond_the_cache_size
        with_s3(stub_client) do
          with_plugin_settings('cache_size_mb' => '1') do
            assert Attachment.new(filename: 'a.png', filesize: 1.megabyte).thumbnailable?
            assert_not Attachment.new(filename: 'a.png', filesize: 1.megabyte + 1).thumbnailable?
          end
        end
      end

      def test_thumbnail_size_is_redmines
        a = Attachment.new
        with_settings thumbnails_size: '120' do
          assert_equal 120, a.thumbnail_size({})
        end
        assert_equal 200, a.thumbnail_size(size: 151)
        assert_equal 800, a.thumbnail_size(size: 2000)
      end

      def test_thumbnail_comes_from_s3_when_it_is_there
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        a = Attachment.find(16)
        with_s3(stub_client(head_object: { content_length: 1 }, get_object: { body: 'from S3' })) do |client|
          assert_equal 'from S3', File.read(a.thumbnail(size: 100))
          assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_100.thumb",
                       api_request(client, :get_object)[:params][:key]
          assert_not_includes operations(client), :put_object
        end
      end

      # Cropped thumbnails (avatars of Redmine 7.1) have their own key, as their
      # own file name in Redmine; Redmine 7.0 does not crop.
      def test_cropped_thumbnail_key
        with_s3(stub_client(head_object: { content_length: 1 })) do
          a = Attachment.find(16)
          suffix = RedmineAws::S3.thumbnail_crop? ? '100_crop' : '100'

          assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_#{suffix}.thumb", a.s3_thumbnail(size: 100, crop: true)
          assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_100.thumb", a.s3_thumbnail(size: 100)
        end
      end

      def test_cropped_thumbnail_is_stored_under_its_own_key
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?
        skip 'Redmine crops from 7.1' unless RedmineAws::S3.thumbnail_crop?

        set_fixtures_attachments_directory
        a = Attachment.find(16)
        with_s3(stub_client(head_object: { content_length: 1 }, get_object: 'NoSuchKey')) do |client|
          assert a.thumbnail(size: 100, crop: true)
          assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_100_crop.thumb",
                       api_request(client, :put_object)[:params][:key]
        end
      end

      private

      def with_plugin_settings(values)
        saved = Setting.plugin_redmine_aws_s3
        Setting.plugin_redmine_aws_s3 = (saved.is_a?(Hash) ? saved : {}).merge(values)
        yield
      ensure
        Setting.plugin_redmine_aws_s3 = saved
      end
    end
  end
end
