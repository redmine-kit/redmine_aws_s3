# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # Upload#presign and the ticket it returns.
    class UploadPresignTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users, :attachments

      def test_presign_returns_a_signed_put_url_for_incoming
        with_s3(stub_client) do
          unsigned, expires = verify_signed_url(presign[:url])

          assert_match %r{\Ahttps://#{DOMAIN}/tmp/incoming/[0-9a-f-]{36}\z}, unsigned
          assert_in_delta Time.now.to_i + 900, expires, 5
        end
      end

      def test_presign_returns_the_url_and_a_ticket_without_calling_s3
        with_s3(stub_client) do |client|
          result = presign

          assert_equal %i[url ticket], result.keys
          assert result[:ticket].present?
          assert_empty client.api_requests
        end
      end

      def test_presign_checks_the_extension
        with_s3(stub_client) do
          with_settings attachment_extensions_denied: 'exe' do
            error = assert_raises(RedmineAws::S3::Upload::Error) { presign(filename: 'tool.exe') }
            assert_includes error.message, '.exe'
          end
        end
      end

      def test_presign_checks_the_size
        with_s3(stub_client) do
          with_settings attachment_max_size: '1' do
            assert_raises(RedmineAws::S3::Upload::Error) { presign(size: 1025) }
            assert presign(size: 1024)
          end
        end
      end

      def test_presign_checks_the_name_and_size
        with_s3(stub_client) do
          assert_raises(RedmineAws::S3::Upload::Error) { presign(size: '-1') }
          assert_raises(RedmineAws::S3::Upload::Error) { presign(filename: '') }
        end
      end

      def test_the_ticket_belongs_to_its_user
        with_s3(stub_client(head_object: head_of(CONTENT))) do |client|
          ticket = presign[:ticket]

          assert_raises(RedmineAws::S3::Upload::Error) { RedmineAws::S3::Upload.new(User.find(3)).complete(ticket) }
          assert_raises(RedmineAws::S3::Upload::Error) { upload.complete("#{ticket}x") }
          assert_empty client.api_requests
        end
      end

      def test_the_ticket_expires
        with_s3(stub_client(head_object: head_of(CONTENT))) do
          ticket = presign[:ticket]
          travel 901.seconds do
            assert_raises(RedmineAws::S3::Upload::Error) { upload.complete(ticket) }
          end
        end
      end
    end
  end
end
