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

      def test_delivery_with_the_headers_of_the_distribution
        signed = response(Net::HTTPOK, '200', 'Content-Security-Policy' => RedmineAws::S3::ATTACHMENT_CSP,
                                              'X-Content-Type-Options' => 'nosniff')
        unsigned = response(Net::HTTPForbidden, '403')
        with_s3(stub_client) do |client|
          urls = []
          RedmineAws::S3::Checks.stubs(:get).with { |url| urls << url }.returns(signed, unsigned)
          results = RedmineAws::S3::Checks.delivery
          put = client.api_requests.find { |request| request[:operation_name] == :put_object }
          deleted = client.api_requests.find { |request| request[:operation_name] == :delete_objects }

          assert(results.all? { |_, ok, _| ok }, results.inspect)
          assert_match %r{\Atmp/bulk/healthcheck-}, put[:params][:key]
          assert_equal put[:params][:key], deleted[:params][:delete][:objects].first[:key]
          verify_signed_url(urls.first)
          assert_equal "https://#{DOMAIN}/#{put[:params][:key]}", urls.second
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
