# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The marks of the cache (<file>.s3cache): set on every file known to be
    # in S3, so that /tmp does not fill, and removed with the file.
    class CacheMarksTest < ActiveSupport::TestCase
      include S3::AttachmentTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      Cache = RedmineAws::S3::Cache

      # Uploads through Lambda: the local file, put to S3, is a cached copy.
      def test_a_file_put_to_s3_is_cached
        a = with_s3(stub_client) { create_issue_attachment('cached.txt', 'cached') }

        assert Cache.cached?(a.local_diskfile)
      end

      def test_deleting_an_attachment_deletes_the_mark
        with_s3(stub_client) do
          a = create_issue_attachment('deleted.txt', 'deleted')
          a.destroy

          assert_not File.exist?("#{a.local_diskfile}#{Cache::MARK}")
        end
      end

      # The newer copy of a shared file goes, and its mark with it.
      def test_sharing_deletes_the_mark_of_the_newer_copy
        with_s3(stub_client) do |client|
          create_issue_attachment('first.txt', 'same')
          create_issue_attachment('second.txt', 'same')
          copy = File.join(Attachment.storage_path, deleted_keys(client).last.delete_prefix('files/'))

          assert_match(/_second\.txt\z/, copy)
          assert_not File.exist?("#{copy}#{Cache::MARK}")
        end
      end

      # A mark whose file is gone, and a download stopped before its rename.
      def test_prune_deletes_leftovers
        dir = Dir.mktmpdir
        mark = File.join(dir, "gone.txt#{Cache::MARK}")
        part = File.join(dir, 'a.txt.0123.part')
        FileUtils.touch([mark, part])
        File.utime(2.hours.ago.to_time, 2.hours.ago.to_time, part)
        Cache.prune(root: dir, limit: 1.megabyte)

        assert_not File.exist?(mark)
        assert_not File.exist?(part)
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
