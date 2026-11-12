# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # An object PUT again after the malware scan, to a signed URL still valid:
    # the bucket policy refuses to copy or read an object not scanned yet
    # (AccessDenied). The upload fails as a missing one, not with a server
    # error.
    class UploadPutAgainTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      NOT_FOUND = 'The uploaded file was not found. Add the file again.'

      def test_an_upload_that_s3_refuses_to_copy
        with_s3(stub_client(head_object: 'NotFound', copy_object: 'AccessDenied')) do
          error = assert_raises(Upload::Error) { upload.complete(presign[:ticket]) }

          assert_equal NOT_FOUND, error.message
        end
      end

      def test_an_avatar_that_s3_refuses_to_read
        with_s3(stub_client(get_object: 'AccessDenied')) do
          ticket = avatar_upload.presign(filename: 'a.png', size: CONTENT.bytesize)[:ticket]
          error = assert_raises(Upload::Error) { avatar_upload.open(ticket) { flunk } }

          assert_equal NOT_FOUND, error.message
        end
      end
    end
  end
end
