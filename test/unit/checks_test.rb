# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    class ChecksTest < ActiveSupport::TestCase
      include S3::TestHelper

      def response(klass, code, headers = {})
        res = klass.new('1.1', code, '')
        headers.each { |name, value| res[name] = value }
        res
      end

      # The answers of a distribution with the headers: the object for the
      # signed URL, 403 for the unsigned one. Returns the URLs requested.
      def stub_distribution
        signed = response(Net::HTTPOK, '200', 'Content-Security-Policy' => RedmineAws::S3::ATTACHMENT_CSP,
                                              'X-Content-Type-Options' => 'nosniff')
        urls = []
        RedmineAws::S3::Checks.stubs(:get).with { |url| urls << url }
                              .returns(signed, response(Net::HTTPForbidden, '403'))
        urls
      end

      def test_delivery_with_the_headers_of_the_distribution
        with_s3(stub_client) do
          stub_distribution
          results = RedmineAws::S3::Checks.delivery

          assert(results.all? { |_, ok, _| ok }, results.inspect)
        end
      end

      def test_delivery_requests_a_check_object_and_deletes_it
        with_s3(stub_client) do |client|
          urls = stub_distribution
          RedmineAws::S3::Checks.delivery
          key = api_request(client, :put_object)[:params][:key]

          assert_match %r{\Atmp/bulk/healthcheck-}, key
          assert_equal key, deleted_keys(client).first
          verify_signed_url(urls.first)
          assert_equal "https://#{DOMAIN}/#{key}", urls.second
        end
      end

      def test_delivery_without_the_csp
        with_s3(stub_client) do
          RedmineAws::S3::Checks.stubs(:get).returns(response(Net::HTTPOK, '200'), response(Net::HTTPOK, '200'))
          results = RedmineAws::S3::Checks.delivery.to_h { |name, ok, _| [name, ok] }

          assert results['Signed URL']
          assert_not results['CSP sandbox']
          assert_not results['nosniff']
          assert_not results['Unsigned URL denied']
        end
      end

      # The screen never shows an exception message; the log has its class.
      def test_delivery_reports_errors
        log = capture_log do
          with_s3(stub_client(put_object: 'AccessDenied')) do
            assert_equal [['Delivery', false, '']], RedmineAws::S3::Checks.delivery
          end
        end

        assert_includes log, 'connection test Delivery failed: Aws::S3::Errors::AccessDenied'
        assert_not_includes log, 'stubbed'
      end

      def test_read_write_reports_errors_without_their_messages
        with_s3(stub_client(put_object: 'AccessDenied', get_object: 'NoSuchKey')) do
          assert_equal [['PutObject', false, ''], ['GetObject', false, ''], ['DeleteObject', true, '']],
                       RedmineAws::S3::Checks.read_write
        end
      end
    end
  end
end
