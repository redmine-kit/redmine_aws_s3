# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/admin_controller_setup'

module RedmineAws
  module S3
    # The values that the "S3" tab shows but does not edit, as Administration ›
    # Information shows them: redmine_aws's partial aws_admin/values, a
    # table.list without a header row.
    class AwsS3AdminValuesTest < Redmine::ControllerTest
      include S3::TestHelper
      include AdminControllerSetup

      def test_the_environment_variables
        with_s3(stub_client) { get :show }

        assert_select 'table.list.values.environment th', 0
        assert_select 'table.list.values.environment tr', 7
        assert_select 'table.list.values.environment tr td.value em.info', text: 'REDMINE_S3_BUCKET'
        assert_select 'div.box.tabular', 1, 'only the settings form'
      end

      def test_the_results_of_a_connection_test
        results = [['PutObject', true, ''], ['GetObject', false, 'Aws::S3::Errors::NoSuchKey']]
        with_s3(stub_client) { get :show, flash: { aws_s3_checks: results } }

        assert_select 'table.list.values.checks th', 0
        assert_select 'table.list.values.checks tr.ok td.tick span.icon-ok'
        assert_select 'table.list.values.checks tr.failed td.value', text: 'Aws::S3::Errors::NoSuchKey'
      end
    end
  end
end
