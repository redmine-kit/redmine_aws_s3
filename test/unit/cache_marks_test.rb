# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The marks of the cache (<file>.s3cache): set on every file known to be
    # in S3, so that /tmp does not fill.
    class CacheMarksTest < ActiveSupport::TestCase
      include S3::AttachmentTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      Cache = RedmineAws::S3::Cache

      # Uploads through Lambda: the local file, put to S3, is a cached copy.
      def test_a_file_put_to_s3_is_cached
        a = with_s3(stub_client) { create_issue_attachment('cached.txt', 'cached') }

        assert Cache.cached?(a.local_diskfile)
      end
    end
  end
end
