# frozen_string_literal: true

module RedmineAws
  module S3
    # The setup of the tests of Redmine's AttachmentsController with the
    # plugin, which are split by subject (downloads, PDF, thumbnails, download
    # all).
    module AttachmentsControllerSetup
      extend ActiveSupport::Concern

      included do
        tests AttachmentsController

        fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues, :trackers,
                 :issue_statuses, :enumerations, :attachments, :versions, :wiki_pages, :wikis, :documents
      end

      def setup
        set_fixtures_attachments_directory
        User.current = nil
      end

      def teardown
        set_tmp_attachments_directory
      end

      def signed_query(url)
        unsigned, expires = verify_signed_url(url)
        [URI(unsigned).path, URI.decode_www_form(URI(unsigned).query.to_s).to_h, expires]
      end

      # GET the action, which redirects, and the signed URL as
      # [path, query, expires].
      def signed_redirect(action, **params)
        get action, params: params

        assert_response :redirect
        signed_query(response.location)
      end

      def put_request(client)
        client.api_requests.find { |request| request[:operation_name] == :put_object }
      end
    end
  end
end
