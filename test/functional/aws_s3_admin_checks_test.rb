# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/admin_controller_setup'

module RedmineAws
  module S3
    # The connection tests and the consistency check of the "S3" tab.
    class AwsS3AdminChecksTest < Redmine::ControllerTest
      include S3::TestHelper
      include AdminControllerSetup

      def test_read_write_check
        with_s3(stub_client(get_object: put_body)) do
          post :read_write

          assert_redirected_to '/admin/aws/s3'
          assert_equal [['PutObject', true, ''], ['GetObject', true, ''], ['DeleteObject', true, '']],
                       flash[:aws_s3_checks]
        end
      end

      def test_read_write_check_reports_a_failure
        with_s3(stub_client(put_object: 'AccessDenied', get_object: 'NoSuchKey')) do
          post :read_write

          assert_equal [false, false, true], flash[:aws_s3_checks].map(&:second)
        end
      end

      def test_actions_need_the_bucket
        post :read_write

        assert_response :not_found
      end

      def test_reconcile_enqueues_the_job
        with_s3(stub_client) do
          AwsS3ReconcileJob.expects(:perform_later).once
          post :reconcile

          assert_redirected_to '/admin/aws/s3'
          assert RedmineAws::S3::Reconciliation.result['started_at'].present?
        end
      end

      def test_shows_the_counts_of_the_reconciliation
        show_reconciliation

        assert_select 'table.list.values.reconciliation tr', text: /Attachments\s*1,200/
        assert_select 'table.list.values.reconciliation tr', text: %r{S3 objects\s*1,201\s*files/}
        assert_select 'table.list.values.reconciliation tr', text: /Files missing in S3\s*1/
        assert_select 'table.list.values.reconciliation tr', text: /Unused objects\s*2/
      end

      def test_shows_the_time_and_the_keys_of_the_reconciliation
        show_reconciliation

        assert_select 'table.list.values.reconciliation tr', text: /Last run\s*2026-11-06 \d\d:44/
        assert_not_includes response.body, '2026-11-06T22:44:01Z'
        assert_select 'li code', text: 'files/2026/11/a'
      end

      def test_a_running_reconciliation
        RedmineAws::S3.update_settings('reconciliation' => { 'started_at' => '2026-11-06T22:40:00Z' })
        with_s3(stub_client) do
          travel_to(Time.utc(2026, 11, 6, 22, 50)) do
            with_settings(date_format: '%Y-%m-%d', time_format: '%H:%M') { get :show }
          end

          assert_select 'table.list.values.reconciliation tr', text: /Status\s*Running/
          assert_select 'table.list.values.reconciliation tr', text: /Started at\s*2026-11-06 \d\d:40/
        end
      end

      private

      # GetObject returns the body of the PutObject before it.
      def put_body
        lambda do |context|
          put = context.client.api_requests.find { |request| request[:operation_name] == :put_object }
          { body: put[:params][:body] }
        end
      end

      def show_reconciliation
        RedmineAws::S3.update_settings(
          'reconciliation' => { 'started_at' => '2026-11-06T22:40:00Z', 'finished_at' => '2026-11-06T22:44:01Z',
                                'attachments' => 1200, 'objects' => 1201, 'missing_count' => 1,
                                'missing' => ['files/2026/11/a'], 'unused_count' => 2, 'unused' => [] }
        )
        with_s3(stub_client) do
          with_settings(date_format: '%Y-%m-%d', time_format: '%H:%M') { get :show }
        end
      end
    end
  end
end
