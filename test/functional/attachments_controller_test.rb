# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    class AttachmentsControllerTest < Redmine::ControllerTest
      include S3::TestHelper

      tests AttachmentsController

      fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues, :trackers,
               :issue_statuses, :enumerations, :attachments, :versions, :wiki_pages, :wikis, :documents

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

      def test_download_redirects_to_a_signed_url
        with_s3(stub_client) do |client|
          get :download, params: { id: 4 }

          assert_response :redirect
          path, query, expires = signed_query(response.location)
          a = Attachment.find(4)

          assert_equal "/files/#{a.disk_directory}/#{a.disk_filename}".squeeze('/'), path
          assert_equal "attachment; filename=\"#{a.filename}\"; filename*=UTF-8''#{a.filename}",
                       query['response-content-disposition']
          assert_equal 'application/x-ruby', query['response-content-type']
          assert_in_delta Time.now.to_i + 300, expires, 5
          assert_empty client.api_requests, 'the local file is used for the existence check'
        end
      end

      # Redmine 7.0 sends every PDF inline; 7.1 only when the PDF preview asks
      # for it with ?disposition=inline.
      def test_download_of_a_pdf_is_inline
        a = Attachment.find(4)
        a.update_columns(filename: '報告.pdf', content_type: 'application/pdf')
        params = RedmineAws::S3.pdf_previewable? ? { id: 4, disposition: 'inline' } : { id: 4 }
        with_s3(stub_client) do
          get :download, params: params
          _, query, = signed_query(response.location)

          assert_equal "inline; filename=\"%3F%3F.pdf\"; filename*=UTF-8''%E5%A0%B1%E5%91%8A.pdf",
                       query['response-content-disposition']
          assert_equal 'application/pdf', query['response-content-type']
        end
      end

      def test_download_of_a_pdf_without_disposition_inline_is_an_attachment
        skip 'Redmine 7.0 sends every PDF inline' unless RedmineAws::S3.pdf_previewable?

        Attachment.find(4).update_columns(filename: 'report.pdf', content_type: 'application/pdf')
        with_s3(stub_client) do
          get :download, params: { id: 4 }
          _, query, = signed_query(response.location)

          assert_match(/\Aattachment;/, query['response-content-disposition'])
        end
      end

      # Redmine 7.1: a PDF compatible file (Illustrator) is sent as PDF only
      # inline; a file that is not a PDF is never inline.
      def test_download_of_a_pdf_compatible_file_is_pdf_only_inline
        skip 'Redmine 7.0 has no PDF compatible files' unless RedmineAws::S3.pdf_previewable?

        Attachment.find(4).update_columns(filename: 'logo.ai', content_type: 'application/illustrator')
        with_s3(stub_client) do
          get :download, params: { id: 4 }
          _, query, = signed_query(response.location)

          assert_match(/\Aattachment;/, query['response-content-disposition'])
          assert_equal 'application/illustrator', query['response-content-type']

          get :download, params: { id: 4, disposition: 'inline' }
          _, query, = signed_query(response.location)

          assert_match(/\Ainline;/, query['response-content-disposition'])
          assert_equal 'application/pdf', query['response-content-type']
        end
      end

      def test_download_of_a_file_that_is_not_a_pdf_is_never_inline
        skip 'Redmine 7.0 decides by the name' unless RedmineAws::S3.pdf_previewable?

        Attachment.find(4).update_columns(filename: 'fake.pdf', content_type: 'text/html')
        with_s3(stub_client) do
          get :download, params: { id: 4, disposition: 'inline' }
          _, query, = signed_query(response.location)

          assert_match(/\Aattachment;/, query['response-content-disposition'])
          assert_equal 'text/html', query['response-content-type']
        end
      end

      def test_download_checks_s3_when_the_file_is_not_local
        a = Attachment.find(4)
        a.update_columns(disk_filename: 'only_in_s3.rb')
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          get :download, params: { id: 4 }

          assert_response :redirect
          assert_equal 'files/2006/07/only_in_s3.rb', client.api_requests.first[:params][:key]
        end
      end

      def test_download_of_a_file_missing_everywhere
        Attachment.find(4).update_columns(disk_filename: 'nowhere.rb')
        with_s3(stub_client(head_object: 'NotFound', get_object: 'NoSuchKey')) do
          get :download, params: { id: 4 }

          assert_response :not_found
        end
      end

      def test_download_keeps_redmines_permissions
        with_s3(stub_client) do
          get :download, params: { id: 7 } # an attachment of a private project

          assert_response :redirect
          assert_match %r{/login}, response.location
        end
      end

      def test_download_counts_project_files
        with_s3(stub_client) do
          assert_difference -> { Attachment.find(9).downloads } do
            get :download, params: { id: 9 }
          end
        end
      end

      def test_download_through_the_api_redirects_too
        with_s3(stub_client) do
          with_settings rest_api_enabled: '1' do
            get :download, params: { id: 4, key: User.find(2).api_key }

            assert_response :redirect
            assert response.location.start_with?("https://#{DOMAIN}/files/")
          end
        end
      end

      def test_without_the_bucket_redmine_sends_the_file
        get :download, params: { id: 4 }

        assert_response :success
        assert_equal RedmineAws::S3::ATTACHMENT_CSP, response.headers['Content-Security-Policy']
      end

      def test_thumbnail_redirects_to_the_stored_thumbnail
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          @request.session[:user_id] = 1
          get :thumbnail, params: { id: 16, size: 100 }

          assert_response :redirect
          assert_equal 'max-age=300, private', response.headers['Cache-Control']
          path, query, = signed_query(response.location)
          a = Attachment.find(16)

          assert_equal "/tmp/thumbnails/#{a.digest}_#{a.filesize}_100.thumb", path
          assert_equal 'image/png', query['response-content-type']
          assert query['response-content-disposition'].start_with?('attachment;')
          assert_not_includes client.api_requests.pluck(:operation_name), :put_object
        end
      end

      def test_thumbnail_is_made_and_stored_when_s3_does_not_have_it
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        Attachment.clear_thumbnails
        with_s3(stub_client(head_object: 'NotFound', get_object: 'NoSuchKey')) do |client|
          @request.session[:user_id] = 1
          get :thumbnail, params: { id: 16, size: 100 }

          assert_response :redirect
          put = client.api_requests.find { |request| request[:operation_name] == :put_object }
          a = Attachment.find(16)

          assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_100.thumb", put[:params][:key]
        end
      end

      def test_no_thumbnail_for_a_file_larger_than_the_cache
        Attachment.find(16).update_columns(filesize: 300.megabytes)
        with_s3(stub_client(head_object: 'NotFound')) do
          @request.session[:user_id] = 1
          get :thumbnail, params: { id: 16, size: 100 }

          assert_response :not_found
        end
      end

      def test_download_all_stores_the_zip_and_redirects
        @request.session[:user_id] = 2
        with_s3(stub_client(head_object: 'NotFound')) do |client|
          get :download_all, params: { object_type: 'issues', object_id: 3 }

          assert_response :redirect
          path, query, = signed_query(response.location)
          put = client.api_requests.find { |request| request[:operation_name] == :put_object }

          assert_match %r{\A/tmp/bulk/[0-9a-f]{64}\.zip\z}, path
          assert_equal path.delete_prefix('/'), put[:params][:key]
          assert_equal 'attachment; filename="issue-3-attachments.zip"; ' \
                       "filename*=UTF-8''issue-3-attachments.zip", query['response-content-disposition']
          assert_equal 'application/zip', query['response-content-type']
        end
      end

      # Redmine lets the files of an issue be renamed (Edit attachments); the
      # zip then has the new names.
      def test_download_all_after_a_rename_makes_a_new_zip
        @request.session[:user_id] = 2
        with_s3(stub_client(head_object: 'NotFound')) do
          get :download_all, params: { object_type: 'issues', object_id: 3 }
          before = signed_query(response.location).first
          Issue.find(3).attachments.find(&:readable?).update!(filename: 'renamed.txt')
          get :download_all, params: { object_type: 'issues', object_id: 3 }

          assert_not_equal before, signed_query(response.location).first
        end
      end

      def test_download_all_reuses_a_stored_zip
        @request.session[:user_id] = 2
        with_s3(stub_client(head_object: { content_length: 1 })) do |client|
          get :download_all, params: { object_type: 'issues', object_id: 3 }

          assert_response :redirect
          assert_not_includes client.api_requests.pluck(:operation_name), :put_object
        end
      end
    end
  end
end
