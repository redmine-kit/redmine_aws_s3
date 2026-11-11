# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_controller_setup'

module RedmineAws
  module S3
    # The disposition and type of PDF files in the signed URL.
    class AttachmentsControllerPdfTest < Redmine::ControllerTest
      include S3::TestHelper
      include AttachmentsControllerSetup

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
      # inline.
      def test_download_of_a_pdf_compatible_file_is_an_attachment_with_its_type
        skip 'Redmine 7.0 has no PDF compatible files' unless RedmineAws::S3.pdf_previewable?

        Attachment.find(4).update_columns(filename: 'logo.ai', content_type: 'application/illustrator')
        with_s3(stub_client) do
          get :download, params: { id: 4 }
          _, query, = signed_query(response.location)

          assert_match(/\Aattachment;/, query['response-content-disposition'])
          assert_equal 'application/illustrator', query['response-content-type']
        end
      end

      def test_download_of_a_pdf_compatible_file_inline_is_pdf
        skip 'Redmine 7.0 has no PDF compatible files' unless RedmineAws::S3.pdf_previewable?

        Attachment.find(4).update_columns(filename: 'logo.ai', content_type: 'application/illustrator')
        with_s3(stub_client) do
          get :download, params: { id: 4, disposition: 'inline' }
          _, query, = signed_query(response.location)

          assert_match(/\Ainline;/, query['response-content-disposition'])
          assert_equal 'application/pdf', query['response-content-type']
        end
      end

      # A file that is not a PDF is never inline.
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
    end
  end
end
