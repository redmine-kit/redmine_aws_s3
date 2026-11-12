# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/conditional_writes'

module RedmineAws
  module S3
    # S3 answers 409 (ConditionalRequestConflict) to conditional writes of the
    # same key at the same time: the write takes the next name, as for 412,
    # instead of failing the request.
    class ConditionalConflictTest < ActiveSupport::TestCase
      include S3::UploadTestHelper
      include ConditionalWrites

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      def test_an_upload_takes_the_next_name_after_a_conflict
        client = stub_client(copy_object: [conflict, copied],
                             head_object: ['NotFound', {}, 'NotFound', head_of(CONTENT)])
        attachment = complete_upload(client)

        assert_equal 2, params_of(client, :copy_object).size
        assert_equal '261109120001_report.txt', attachment.reload.disk_filename
      end

      def test_a_file_saved_through_redmine_takes_the_next_name_after_a_conflict
        client = stub_client(put_object: [conflict, {}], head_object: 'NotFound')
        attachment = travel_to(NOW) { with_s3(client) { create_attachment('conflict.txt') } }

        assert_equal 2, params_of(client, :put_object).size
        assert_equal '261109120001_conflict.txt', attachment.reload.disk_filename
      end
    end
  end
end
