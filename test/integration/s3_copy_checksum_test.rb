# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_in_s3_setup'

module RedmineAws
  module S3
    # S3 computes the SHA256 of the whole object on a copy, which becomes the
    # digest of an upload (LocalStack only: moto does not return it).
    class S3CopyChecksumTest < Redmine::IntegrationTest
      include S3::TestHelper
      include AttachmentsInS3Setup

      def setup
        super
        return if s3_test_backend == 'localstack'

        skip "#{s3_test_backend} does not return ChecksumSHA256 (LocalStack does)"
      end

      def test_a_copy_gets_the_sha256_of_the_whole_object
        with_test_s3 do
          put_object('tmp/incoming/ok', 'abc')
          RedmineAws::S3.storage.copy('tmp/incoming/ok', 'files/ok')
          head = RedmineAws::S3.storage.head('files/ok', checksum: true)

          assert_equal sha256_base64('abc'), head.checksum_sha256
          assert_equal 'FULL_OBJECT', head.checksum_type
        end
      end

      def test_a_copy_of_a_multipart_object_gets_the_sha256_of_the_whole_object
        with_test_s3 do
          parts = ['a' * 5.megabytes, 'b']
          put_multipart('tmp/incoming/parts', parts)
          RedmineAws::S3.storage.copy('tmp/incoming/parts', 'files/parts')
          head = RedmineAws::S3.storage.head('files/parts', checksum: true)

          assert_equal sha256_base64(parts.join), head.checksum_sha256
          assert_equal 'FULL_OBJECT', head.checksum_type
        end
      end

      private

      def put_multipart(key, parts)
        client = RedmineAws::S3.client
        target = { bucket: RedmineAws::S3.bucket, key: key }
        id = client.create_multipart_upload(**target).upload_id
        etags = parts.each_with_index.map do |part, i|
          client.upload_part(**target, upload_id: id, part_number: i + 1, body: part).etag
        end
        completed = etags.each_with_index.map { |etag, i| { etag: etag, part_number: i + 1 } }
        client.complete_multipart_upload(**target, upload_id: id, multipart_upload: { parts: completed })
      end
    end
  end
end
