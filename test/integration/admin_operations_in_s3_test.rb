# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_in_s3_setup'

module RedmineAws
  module S3
    # The consistency check and the connection tests of the "S3" tab.
    class AdminOperationsInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AttachmentsInS3Setup

      def teardown
        Setting.plugin_redmine_aws_s3 = {}
      end

      def test_reconciliation_lists_unused_objects_without_the_derived_cache
        with_test_s3 do
          result = reconcile

          assert_includes result['unused'], 'files/2020/01/orphan'
          assert_not_includes result['unused'], 'files/derived_cache/markdownized_previews/d_1.md'
          assert result['finished_at'].present?
        end
      end

      def test_reconciliation_lists_missing_files
        with_test_s3 do
          kept = create_attachment(mock_file(filename: 'kept.txt', content: 'kept'))
          result = reconcile

          assert_not_includes result['missing'], kept.s3_key
          assert_includes result['missing'], Attachment.find(1).s3_key
        end
      end

      def test_read_write_check
        with_test_s3 do
          assert(RedmineAws::S3::Checks.read_write.all? { |_, ok, _| ok })
          assert_empty keys('tmp/')
          assert_equal RedmineAws::S3.bucket, RedmineAws::S3::Checks.head_bucket
        end
      end

      private

      # An unused object and an object of Redmine's derived cache, then the
      # consistency check; returns its result.
      def reconcile
        put_object('files/2020/01/orphan', 'x')
        put_object('files/derived_cache/markdownized_previews/d_1.md', 'x')
        AwsS3ReconcileJob.perform_now
        RedmineAws::S3::Reconciliation.result
      end
    end
  end
end
