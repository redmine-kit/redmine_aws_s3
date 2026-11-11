# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Upload#complete: the copy, the digest and the attachment.
    class UploadTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      # Completes an upload of CONTENT; returns the attachment and the client.
      def complete_upload
        client = stub_client(head_object: ['NotFound', head_of(CONTENT)])
        attachment = with_s3(client) { upload.complete(presign[:ticket]) }
        [attachment, client]
      end

      # Completes the upload of a PDF declared as text/plain; returns the
      # attachment and the GetObject request that read its start, if any.
      def complete_pdf_declared_as_text
        pdf = "%PDF-1.4\n#{'x' * 32}"
        client = stub_client(head_object: ['NotFound', head_of(pdf)], get_object: { body: pdf })
        attachment = with_s3(client) do
          ticket = upload.presign(filename: 'report.txt', size: pdf.bytesize, content_type: 'text/plain')[:ticket]
          upload.complete(ticket)
        end
        [attachment, api_request(client, :get_object)]
      end

      # Completes an upload with the same content as attachment 1; returns the
      # attachment and the client.
      def complete_shared_upload
        content = 'shared'
        Attachment.find(1).update_columns(digest: Digest::SHA256.hexdigest(content), filesize: content.bytesize)
        client = stub_client(head_object: ['NotFound', head_of(content), head_of(content)])
        attachment = with_s3(client) do
          upload.complete(upload.presign(filename: 'copy.gif', size: content.bytesize)[:ticket])
        end
        [attachment, client]
      end

      def test_complete_registers_the_attachment
        attachment, = complete_upload

        assert attachment.persisted?
        assert_equal Digest::SHA256.hexdigest(CONTENT), attachment.digest
        assert_equal CONTENT.bytesize, attachment.filesize
        assert_equal 'report.txt', attachment.filename
        assert_equal 'text/plain', attachment.content_type
        assert_equal @user, attachment.author
      end

      def test_complete_names_the_file_as_redmine_does
        attachment, = complete_upload

        assert_match %r{\A\d{4}/\d{2}\z}, attachment.disk_directory
        assert_match(/\A\d{12}_report\.txt\z/, attachment.disk_filename)
      end

      def test_complete_copies_the_upload_with_its_sha256
        attachment, client = complete_upload
        copy = last_params(client)[:copy_object]

        assert_equal attachment.s3_key, copy[:key]
        assert_equal 'SHA256', copy[:checksum_algorithm]
        assert_match %r{\Aredmine-files/tmp/incoming/}, copy[:copy_source]
      end

      def test_complete_reads_the_sha256_and_deletes_the_upload
        _, client = complete_upload
        params = last_params(client)

        assert_equal 'ENABLED', params[:head_object][:checksum_mode]
        assert_match %r{\Atmp/incoming/}, params[:delete_objects][:delete][:objects].first[:key]
      end

      # Redmine 7.1 detects the type from the contents and the name, and ignores
      # the declared one; 7.0 takes the declared one.
      def test_the_content_type_of_the_upload
        attachment, read = complete_pdf_declared_as_text

        if RedmineAws::S3.detects_content_type?
          assert_equal 'application/pdf', attachment.content_type
          assert_equal attachment.s3_key, read[:params][:key]
          assert_equal 'bytes=0-65535', read[:params][:range]
        else
          assert_equal 'text/plain', attachment.content_type
          assert_nil read
        end
      end

      def test_complete_shares_a_file_with_the_same_content
        attachment, = complete_shared_upload
        existing = Attachment.find(1)

        assert attachment.persisted?
        assert_equal existing.disk_filename, attachment.disk_filename
        assert_equal existing.disk_directory, attachment.disk_directory
        assert_equal Digest::SHA256.hexdigest('shared'), attachment.digest
      end

      def test_complete_deletes_the_copy_of_a_shared_file
        _, client = complete_shared_upload
        deleted = deleted_keys(client)

        assert_includes deleted, api_request(client, :copy_object)[:params][:key], 'the extra copy is deleted'
        assert(deleted.any? { |key| key.start_with?('tmp/incoming/') }, 'the upload is deleted')
      end
    end
  end
end
