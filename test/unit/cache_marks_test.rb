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

      def test_prune_deletes_a_mark_whose_file_is_gone
        in_tmpdir do |dir|
          mark = File.join(dir, "gone.txt#{Cache::MARK}")
          FileUtils.touch(mark)
          Cache.prune(root: dir, limit: 1.megabyte)

          assert_not File.exist?(mark)
        end
      end

      # A download stopped before its rename, after an hour.
      def test_prune_deletes_an_old_partial_download
        in_tmpdir do |dir|
          old, recent = %w[old recent].map { |name| File.join(dir, "#{name}.txt.0123.part") }
          FileUtils.touch([old, recent])
          File.utime(2.hours.ago.to_time, 2.hours.ago.to_time, old)
          Cache.prune(root: dir, limit: 1.megabyte)

          assert_equal [false, true], [File.exist?(old), File.exist?(recent)]
        end
      end

      private

      def in_tmpdir
        dir = Dir.mktmpdir
        yield dir
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
