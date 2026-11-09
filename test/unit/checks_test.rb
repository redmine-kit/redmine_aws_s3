# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessS3ChecksTest < ActiveSupport::TestCase
  include RedmineServerlessS3::TestHelper

  def response(klass, code, headers = {})
    res = klass.new('1.1', code, '')
    headers.each { |name, value| res[name] = value }
    res
  end

  def test_delivery_with_the_headers_of_the_distribution
    signed = response(Net::HTTPOK, '200', 'Content-Security-Policy' => RedmineServerlessS3::ATTACHMENT_CSP,
                                          'X-Content-Type-Options' => 'nosniff')
    unsigned = response(Net::HTTPForbidden, '403')
    with_s3(stub_client) do |client|
      urls = []
      RedmineServerlessS3::Checks.stubs(:get).with { |url| urls << url }.returns(signed, unsigned)
      results = RedmineServerlessS3::Checks.delivery
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
      RedmineServerlessS3::Checks.stubs(:get).returns(response(Net::HTTPOK, '200'), response(Net::HTTPOK, '200'))
      results = RedmineServerlessS3::Checks.delivery.to_h { |name, ok, _| [name, ok] }

      assert results['Signed URL']
      assert_not results['Sandbox CSP']
      assert_not results['nosniff']
      assert_not results['Unsigned URL refused']
    end
  end

  def test_delivery_reports_errors
    with_s3(stub_client(put_object: 'AccessDenied')) do
      results = RedmineServerlessS3::Checks.delivery

      assert_equal 'Delivery', results.first.first
      assert_not results.first.second
    end
  end
end
