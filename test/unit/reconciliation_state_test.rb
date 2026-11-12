# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # A consistency check that failed or never finished is not shown as
    # running forever.
    class ReconciliationStateTest < ActiveSupport::TestCase
      include S3::TestHelper

      fixtures :users, :attachments

      def teardown
        Setting.plugin_redmine_aws_s3 = {}
      end

      def test_the_states_of_a_run
        recent = 10.minutes.ago.utc.iso8601
        assert_equal :running, Reconciliation.state('started_at' => recent)
        assert_equal :failed, Reconciliation.state('started_at' => 2.hours.ago.utc.iso8601)
        assert_equal :failed, Reconciliation.state('started_at' => recent, 'error' => 'Aws::S3::Errors::AccessDenied')
        assert_equal :finished, Reconciliation.state('started_at' => recent, 'finished_at' => recent)
      end

      # The job keeps the class of the error for the tab, logs the message,
      # and still fails.
      def test_a_failed_job_is_recorded
        Reconciliation.started
        log = capture_log do
          with_s3(stub_client(list_objects_v2: 'AccessDenied')) do
            assert_raises(::Aws::S3::Errors::AccessDenied) { AwsS3ReconcileJob.perform_now }
          end
        end

        assert_equal 'Aws::S3::Errors::AccessDenied', Reconciliation.result['error']
        assert Reconciliation.result['started_at'].present?
        assert_includes log, 'consistency check failed: Aws::S3::Errors::AccessDenied: stubbed-response-error-message'
      end
    end
  end
end
