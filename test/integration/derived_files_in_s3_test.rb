# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_in_s3_setup'

module RedmineAws
  module S3
    # Files that Redmine makes from attachments: thumbnails and the zips of
    # "download all".
    class DerivedFilesInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AttachmentsInS3Setup

      def test_thumbnails_are_stored_in_s3
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        with_test_s3 do
          attachment = image_without_local_file
          key = "tmp/thumbnails/#{attachment.digest}_#{attachment.filesize}_100.thumb"

          assert_equal "/#{key}", thumbnail_path(attachment)
          assert object(key).b.start_with?("\x89PNG".b)
        end
      end

      def test_thumbnails_are_deleted_with_the_image
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        with_test_s3 do
          attachment = image_without_local_file
          thumbnail_path(attachment)
          attachment.destroy

          assert_empty keys('tmp/thumbnails/')
        end
      end

      def test_download_all_stores_a_zip
        with_test_s3 do
          key = download_all_key(two_files_of_the_same_name)

          assert key.start_with?('tmp/bulk/')
          names = zip_entries(object(key))
          assert_equal 'A', names['a.txt']
          assert_equal 'B', names['a(1).txt']
        end
      end

      def test_download_all_reuses_the_zip
        with_test_s3 do
          issue = two_files_of_the_same_name
          download_all_key(issue)
          get "/attachments/issues/#{issue.id}/download"

          assert_equal 1, keys('tmp/bulk/').size, 'the same zip is reused'
        end
      end

      private

      def image_without_local_file
        attachment = create_attachment(uploaded_test_file('2010/11/101123161450_testfile_1.png', 'image/png'))
        FileUtils.rm_f(attachment.local_diskfile)
        attachment
      end

      # GET the thumbnail as admin; returns the path of the signed URL.
      def thumbnail_path(attachment)
        log_user('admin', 'admin')
        get "/attachments/thumbnail/#{attachment.id}/100"
        assert_response :redirect
        URI(verify_signed_url(response.location).first).path
      end

      # Issue 1 with two files named a.txt, the first one not on the local
      # disk.
      def two_files_of_the_same_name
        first = create_attachment(mock_file(filename: 'a.txt', content: 'A'))
        create_attachment(mock_file(filename: 'a.txt', content: 'B'))
        FileUtils.rm_f(first.local_diskfile)
        Issue.find(1)
      end

      # GET "download all" as admin; returns the key of the signed URL.
      def download_all_key(issue)
        log_user('admin', 'admin')
        get "/attachments/issues/#{issue.id}/download"
        assert_response :redirect
        URI(verify_signed_url(response.location).first).path.delete_prefix('/')
      end

      # The entries of a zip by name.
      def zip_entries(data)
        names = {}
        Zip::InputStream.open(StringIO.new(data)) do |zip|
          while (entry = zip.get_next_entry)
            names[entry.name] = zip.read
          end
        end
        names
      end
    end
  end
end
