# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_in_s3_setup'

module RedmineAws
  module S3
    # Files that Redmine writes itself (REST API uploads, CSV imports) and
    # their deletion.
    class UploadsThroughRedmineInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AttachmentsInS3Setup

      def test_uploads_through_lambda_are_put_to_s3
        with_test_s3 do
          attachment = upload_through_the_api('through the REST API')

          assert_equal 'through the REST API', object(attachment.s3_key)
          FileUtils.rm_f(attachment.local_diskfile)
          assert attachment.readable?
          assert_equal 'through the REST API', File.read(attachment.reload.diskfile)
        end
      end

      def test_deleting_an_attachment_deletes_its_object
        with_test_s3 do
          attachment = upload_through_the_api('through the REST API')
          attachment.destroy

          assert_empty keys('files/')
          assert_not File.exist?(attachment.local_diskfile)
        end
      end

      def test_a_csv_import_is_kept_in_s3
        with_test_s3 do
          import = upload_import

          assert_equal ["imports/#{import.filename}"], keys('imports/')
        end
      end

      def test_csv_import_continues_in_another_environment
        with_test_s3 do
          import = upload_import
          FileUtils.rm_f(import.filepath)
          post "/imports/#{import.to_param}/settings",
               params: { import_settings: { separator: ';', wrapper: '"', encoding: 'UTF-8' } }

          assert_redirected_to "/imports/#{import.to_param}/mapping"
          assert File.exist?(import.filepath)
          assert import.reload.total_items.positive?
        end
      end

      private

      # POST /uploads.json as jsmith; returns the attachment.
      def upload_through_the_api(content)
        with_settings rest_api_enabled: '1' do
          post '/uploads.json?filename=api.txt', params: content,
                                                 headers: { 'CONTENT_TYPE' => 'application/octet-stream' }
                                                   .merge(credentials('jsmith'))
          assert_response :created
        end
        Attachment.last
      end

      def upload_import
        log_user('jsmith', 'jsmith')
        post '/imports', params: { type: 'IssueImport', file: uploaded_test_file('import_issues.csv', 'text/csv') }
        Import.last
      end
    end
  end
end
