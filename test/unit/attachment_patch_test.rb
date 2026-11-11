# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The file of an attachment put to S3 when it is saved, and deleted with it.
    class AttachmentPatchTest < ActiveSupport::TestCase
      include S3::AttachmentTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      # Destroys a new attachment while S3 lists one thumbnail of it; returns
      # the attachment and the client.
      def destroyed_attachment
        client = stub_client(list_objects_v2: { contents: [{ key: 'tmp/thumbnails/d_1_100.thumb' }] })
        a = with_s3(client) { create_issue_attachment('gone.txt', 'gone').tap(&:destroy) }
        [a, client]
      end

      def test_files_to_final_location_puts_the_file
        with_s3(stub_client) do |client|
          a = create_issue_attachment('put.txt', 'put')
          put = api_request(client, :put_object)[:params]

          assert_equal a.s3_key, put[:key]
          assert_match %r{\Afiles/\d{4}/\d{2}/\d{12}_put\.txt\z}, a.s3_key
          assert_equal 'redmine-files', put[:bucket]
        end
      end

      def test_a_failed_put_stops_the_save
        with_s3(stub_client(put_object: 'AccessDenied')) do
          a = new_issue_attachment('denied.txt', 'x')

          assert_raises(::Aws::S3::Errors::AccessDenied) { a.save }
          assert_not Attachment.exists?(filename: 'denied.txt')
        end
      end

      def test_saving_without_a_new_file_puts_nothing
        with_s3(stub_client) do |client|
          a = Attachment.find(1)
          a.description = 'changed'
          a.save!

          assert_not_includes operations(client), :put_object
        end
      end

      def test_delete_from_disk_deletes_the_object_and_its_thumbnails
        a, client = destroyed_attachment
        deleted = deleted_keys(client)

        assert_includes deleted, a.s3_key
        assert_includes deleted, 'tmp/thumbnails/d_1_100.thumb'
        assert_not File.exist?(a.local_diskfile)
      end

      def test_delete_from_disk_lists_the_thumbnails_and_deletes_the_preview
        a, client = destroyed_attachment

        assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_",
                     api_request(client, :list_objects_v2)[:params][:prefix]
        assert_includes deleted_keys(client), "files/derived_cache/markdownized_previews/#{a.digest}_#{a.filesize}.md"
      end

      def test_a_shared_file_is_not_deleted
        with_s3(stub_client) do |client|
          a1 = create_issue_attachment('one.txt', 'same')
          a2 = create_issue_attachment('two.txt', 'same')
          client.api_requests.clear
          a2.reload.destroy

          assert_equal a1.disk_filename, a2.disk_filename
          assert_not_includes operations(client), :delete_objects
        end
      end

      # Both attachments are locked while the file is shared, as Redmine's
      # reuse_existing_file_if_possible locks them, so that the existing one is
      # not deleted meanwhile.
      def test_sharing_locks_the_existing_attachment
        with_s3(stub_client) do
          create_issue_attachment('first.txt', 'abcd')
          Attachment.any_instance.expects(:lock!).twice
          create_issue_attachment('second.txt', 'abcd')
        end
      end

      def test_same_content_is_shared_by_digest_and_size
        with_s3(stub_client) do |client|
          a1 = create_issue_attachment('first.txt', 'abcd')
          a2 = create_issue_attachment('second.txt', 'abcd').reload
          deleted = deleted_keys(client)

          assert_equal a1.s3_key, a2.s3_key
          assert_equal 1, deleted.size
          assert_match(/_second\.txt\z/, deleted.first)
        end
      end
    end
  end
end
