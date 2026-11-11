# frozen_string_literal: true

require_relative 's3_objects'

module RedmineAws
  module S3
    # The setup of the integration tests of attachments in S3 reproduced by
    # LocalStack or moto (S3_TEST_ENDPOINT, chosen by bin/test). moto 5.2.5
    # does not return ChecksumSHA256 from HeadObject, so on moto the upload
    # tests compute that HeadObject result from the stored bytes, as S3 does;
    # S3 computing the SHA256 of a copy is tested on LocalStack only.
    module AttachmentsInS3Setup
      extend ActiveSupport::Concern
      include S3Objects

      included do
        fixtures :users, :email_addresses, :projects, :roles, :members, :member_roles, :enabled_modules, :issues,
                 :trackers, :projects_trackers, :issue_statuses, :enumerations, :workflows, :attachments,
                 :custom_fields, :custom_values, :custom_fields_projects, :custom_fields_trackers
      end

      def setup
        set_tmp_attachments_directory
        Attachment.clear_thumbnails
      end

      # The browser's PUT, sent to S3 as CloudFront does through OAC.
      def put_upload(url, data)
        key = URI(url).path.delete_prefix('/')
        put_object(key, data)
        key
      end

      def upload_through_cloudfront(data, filename)
        post '/s3_uploads/presign', params: { filename: filename, size: data.bytesize, content_type: 'text/plain' }
        assert_response :success
        presigned = response.parsed_body
        key = put_upload(presigned['url'], data)
        post '/s3_uploads/complete.js', params: { ticket: presigned['ticket'], attachment_id: 1 }, xhr: true
        assert_response :success
        [key, response.body[/val\('([^']+)'\)/, 1]]
      end

      # As jsmith, a presign and the browser's PUT; returns the key in
      # tmp/incoming/ and the ticket.
      def presign_and_put(data, filename)
        log_user('jsmith', 'jsmith')
        post '/s3_uploads/presign', params: { filename: filename, size: data.bytesize }
        presigned = response.parsed_body
        [put_upload(presigned['url'], data), presigned['ticket']]
      end

      def complete_upload(ticket)
        post '/s3_uploads/complete.js', params: { ticket: ticket, attachment_id: 1 }, xhr: true
      end

      # An attachment of issue 1 by admin, created through Redmine.
      def create_attachment(file)
        Attachment.create!(container: Issue.find(1), author: User.find(1), file: file)
      end
    end
  end
end
