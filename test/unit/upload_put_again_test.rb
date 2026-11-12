# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # S3 refuses to copy or read an upload (AccessDenied): the upload fails
    # with a message instead of a server error, and the log has the error.
    class UploadPutAgainTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      NOT_FOUND = 'The uploaded file was not found. Add the file again.'
      FAILED = 'The file could not be registered. Contact your Redmine administrator.'

      # With the malware scan, the bucket policy refuses an object PUT again
      # after the scan: the upload is as missing.
      def test_an_upload_that_s3_refuses_to_copy_after_the_scan
        client = stub_client(head_object: 'NotFound', copy_object: 'AccessDenied',
                             get_object_tagging: scan_tag('NO_THREATS_FOUND'))
        log, message = refusal_of(client) { with_malware_scan { upload.complete(presign[:ticket]) } }

        assert_equal NOT_FOUND, message
        assert_includes log, 'S3 refused the upload: Aws::S3::Errors::AccessDenied: stubbed-response-error-message'
      end

      # Without the scan, AccessDenied is a permission problem (IAM, KMS).
      def test_an_upload_that_s3_refuses_to_copy_without_the_scan
        client = stub_client(head_object: 'NotFound', copy_object: 'AccessDenied')
        log, message = refusal_of(client) { upload.complete(presign[:ticket]) }

        assert_equal FAILED, message
        assert_includes log, 'S3 refused the upload: Aws::S3::Errors::AccessDenied'
      end

      def test_an_avatar_that_s3_refuses_to_read
        _, without_scan = refusal_of(stub_client(get_object: 'AccessDenied')) { open_avatar }
        client = stub_client(get_object: 'AccessDenied', get_object_tagging: scan_tag('NO_THREATS_FOUND'))
        _, with_scan = refusal_of(client) { with_malware_scan { open_avatar } }

        assert_equal [FAILED, NOT_FOUND], [without_scan, with_scan]
      end

      private

      def open_avatar
        ticket = avatar_upload.presign(filename: 'a.png', size: CONTENT.bytesize)[:ticket]
        avatar_upload.open(ticket) { flunk }
      end

      # The log and the message of the Upload::Error that the block raises.
      def refusal_of(client, &)
        message = nil
        log = capture_log { with_s3(client) { message = assert_raises(Upload::Error, &).message } }
        [log, message]
      end
    end
  end
end
