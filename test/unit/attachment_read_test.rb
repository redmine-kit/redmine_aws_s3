# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Reading the file of an attachment from S3 when it is not on the local
    # disk, and Redmine's own code when the plugin is off.
    class AttachmentReadTest < ActiveSupport::TestCase
      include S3::AttachmentTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      # Runs the block with the client but without the bucket (the plugin off).
      def with_client_only(client)
        RedmineAws::S3.client = client
        yield client
      ensure
        RedmineAws::S3.client = nil
      end

      def test_off_without_the_bucket
        with_client_only(stub_client) do |client|
          a = create_issue_attachment('off.txt', 'off')

          assert_not RedmineAws::S3.enabled?
          assert File.exist?(a.diskfile)
          assert a.readable?
          a.destroy
          assert_empty client.api_requests
        end
      end

      def test_readable_asks_s3_when_the_file_is_not_local
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          a = Attachment.new(disk_directory: '2026/11', disk_filename: 'missing.txt')

          assert a.readable?
          assert a.readable?
          assert_equal [:head_object], operations(client)
          assert_equal 'files/2026/11/missing.txt', client.api_requests.last[:params][:key]
        end
      end

      def test_readable_is_false_when_s3_does_not_have_it
        with_s3(stub_client(head_object: 'NotFound')) do
          assert_not Attachment.new(disk_directory: '2026/11', disk_filename: 'missing.txt').readable?
        end
      end

      def test_diskfile_fetches_a_saved_attachment
        with_s3(stub_client(get_object: { body: 'from s3' })) do
          a = Attachment.find(1)
          FileUtils.rm_f(a.local_diskfile)

          assert_equal 'from s3', File.read(a.diskfile)
        end
      end

      def test_diskfile_of_a_new_record_fetches_nothing
        with_s3(stub_client) do |client|
          Attachment.new(disk_directory: '2026/11', disk_filename: 'new.txt').diskfile

          assert_empty client.api_requests
        end
      end
    end
  end
end
