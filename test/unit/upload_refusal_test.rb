# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Upload#complete refuses an upload that is missing or does not match,
    # and deletes what it copied.
    class UploadRefusalTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      def test_a_size_that_does_not_match_deletes_the_upload_and_the_copy
        head = head_of(CONTENT).merge(content_length: CONTENT.bytesize + 1)
        with_s3(stub_client(head_object: ['NotFound', head])) do |client|
          assert_complete_refused('size')

          assert_deleted_under(client, 'tmp/incoming/', 'files/')
        end
      end

      def test_a_copy_without_a_full_object_sha256_is_refused
        with_s3(stub_client(head_object: ['NotFound', head_of(CONTENT, type: 'COMPOSITE')])) do |client|
          assert_raises(RedmineAws::S3::Upload::Error) { upload.complete(presign[:ticket]) }
          assert_deleted_under(client, 'files/')
        end
      end

      def test_a_copy_without_a_sha256_is_refused
        with_s3(stub_client(head_object: ['NotFound', head_of(CONTENT).merge(checksum_sha256: nil)])) do
          error = assert_raises(RedmineAws::S3::Upload::Error) { upload.complete(presign[:ticket]) }
          assert_equal 'The file could not be registered. Contact your Redmine administrator.', error.message
        end
      end

      def test_a_missing_upload_is_refused
        with_s3(stub_client(head_object: 'NotFound', copy_object: 'NoSuchKey')) do
          error = assert_raises(RedmineAws::S3::Upload::Error) { upload.complete(presign[:ticket]) }
          assert_equal 'The uploaded file was not found. Add the file again.', error.message
        end
      end
    end
  end
end
