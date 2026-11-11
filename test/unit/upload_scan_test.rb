# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Upload#complete with the malware scan on (docs/attachments.md#malware-scan).
    class UploadScanTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      def teardown
        Setting.plugin_redmine_aws_s3 = {}
      end

      def test_complete_waits_for_a_clean_scan
        tags = scan_tag('NO_THREATS_FOUND')
        with_s3(stub_client(get_object_tagging: tags, head_object: ['NotFound', head_of(CONTENT)])) do |client|
          with_malware_scan do
            attachment = upload.complete(presign[:ticket])

            assert attachment.persisted?
            assert_equal %i[get_object_tagging head_object], client.api_requests.pluck(:operation_name).first(2)
          end
        end
      end

      def test_complete_while_the_scan_runs_is_pending
        with_s3(stub_client(get_object_tagging: scan_tag(nil))) do |client|
          with_malware_scan do
            ticket = presign[:ticket]

            assert_raises(RedmineAws::S3::Upload::Pending) { upload.complete(ticket) }
            assert_equal [:get_object_tagging], client.api_requests.pluck(:operation_name)
          end
        end
      end

      def test_complete_refuses_a_threat
        with_s3(stub_client(get_object_tagging: scan_tag('THREATS_FOUND'))) do |client|
          with_malware_scan { assert_complete_refused('threat') }
          operations = client.api_requests.pluck(:operation_name)

          assert_includes operations, :delete_objects
          assert_not_includes operations, :head_object
        end
      end
    end
  end
end
