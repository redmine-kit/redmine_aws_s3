# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The files of attachments are written to S3 only when their key is free
    # (If-None-Match: *). Another Redmine server can pick the same name in the
    # same second; the one that loses takes the next free name.
    class ConditionalWritesTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      NOW = Time.utc(2026, 11, 9, 12, 0, 0)

      def test_an_upload_takes_the_next_name_when_its_key_is_taken
        # HeadObject: the name is free, then taken by the other server, the
        # next one is free, and the copy.
        client = stub_client(copy_object: [precondition_failed, copied],
                             head_object: ['NotFound', {}, 'NotFound', head_of(CONTENT)])
        attachment = complete_upload(client)
        copies = params_of(client, :copy_object)

        assert_equal ['files/2026/11/261109120000_report.txt', 'files/2026/11/261109120001_report.txt'],
                     copies.pluck(:key)
        assert_equal %w[* *], copies.pluck(:if_none_match)
        assert_equal '261109120001_report.txt', attachment.reload.disk_filename
      end

      def test_a_file_saved_through_redmine_takes_the_next_name_when_its_key_is_taken
        client = stub_client(put_object: [precondition_failed, {}], head_object: 'NotFound')
        attachment = travel_to(NOW) { with_s3(client) { create_attachment('saved.txt') } }
        puts = params_of(client, :put_object)

        assert_equal ['files/2026/11/261109120000_saved.txt', 'files/2026/11/261109120001_saved.txt'],
                     puts.pluck(:key)
        assert_equal %w[* *], puts.pluck(:if_none_match)
        assert_equal '261109120001_saved.txt', attachment.reload.disk_filename
        assert File.exist?(attachment.local_diskfile), 'the local file has the new name'
      end

      def test_writes_that_never_succeed_stop
        client = stub_client(put_object: precondition_failed, head_object: 'NotFound')

        assert_raises(Storage::KeyTaken) { travel_to(NOW) { with_s3(client) { create_attachment('lost.txt') } } }
        assert_equal DiskName::ATTEMPTS, operations(client).count(:put_object)
      end

      private

      def complete_upload(client)
        travel_to(NOW) { with_s3(client) { upload.complete(presign[:ticket]) } }
      end

      # CopyObject's answer as S3 sends it: S3 checks a 200 answer of CopyObject
      # for an error in its body, which stubbed data does not have.
      def copied
        { status_code: 200, headers: {},
          body: '<?xml version="1.0" encoding="UTF-8"?><CopyObjectResult><ETag>"e"</ETag></CopyObjectResult>' }
      end

      # S3's answer to a conditional write when the key has an object (412).
      def precondition_failed
        ::Aws::S3::Errors::PreconditionFailed.new(nil, 'At least one of the pre-conditions you specified did not hold')
      end

      # The params of every request of the operation, in order.
      def params_of(client, operation)
        client.api_requests.select { |request| request[:operation_name] == operation }.pluck(:params)
      end

      def create_attachment(filename)
        Attachment.create!(container: Issue.find(1), author: User.find(1),
                           file: mock_file(filename: filename, content: 'saved'))
      end
    end
  end
end
