# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessS3UrlSignerTest < ActiveSupport::TestCase
  include RedmineServerlessS3::TestHelper

  def signer
    RedmineServerlessS3::UrlSigner.new(domain: DOMAIN, key_pair_id: KEY_PAIR_ID,
                                       private_key: RedmineServerlessS3::TestHelper.private_key.to_pem)
  end

  def test_signed_url_verifies_with_the_public_key
    url = signer.url_for('files/2026/11/261109120000_a.txt', expires_in: 300)
    unsigned, expires = verify_signed_url(url)

    assert_equal "https://#{DOMAIN}/files/2026/11/261109120000_a.txt", unsigned
    assert_in_delta Time.now.to_i + 300, expires, 5
  end

  def test_query_strings_are_signed
    disposition = ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: '報告書 1.pdf')
    url = signer.url_for('files/2026/11/x.pdf',
                         { 'response-content-disposition' => disposition,
                           'response-content-type' => 'application/pdf' },
                         expires_in: 60)
    unsigned, = verify_signed_url(url)
    query = URI.decode_www_form(URI(unsigned).query).to_h

    assert_equal disposition, query['response-content-disposition']
    assert_equal 'application/pdf', query['response-content-type']
    assert_includes disposition, "filename*=UTF-8''%E5%A0%B1%E5%91%8A%E6%9B%B8%201.pdf"
  end

  def test_a_changed_query_does_not_verify
    url = signer.url_for('files/a.txt', { 'response-content-type' => 'text/plain' }, expires_in: 60)
    tampered = url.sub('text%2Fplain', 'text%2Fhtml')

    assert_raises(Minitest::Assertion) { verify_signed_url(tampered) }
  end

  def test_keys_are_escaped_per_segment
    url = signer.url_for('files/2026/11/a b#c.txt', expires_in: 60)

    assert url.start_with?("https://#{DOMAIN}/files/2026/11/a%20b%23c.txt?Expires=")
  end

  def test_not_configured
    signer = RedmineServerlessS3::UrlSigner.new(domain: DOMAIN, key_pair_id: nil, private_key: nil)

    assert_raises(RedmineServerlessS3::UrlSigner::NotConfigured) { signer.url_for('files/a', expires_in: 1) }
  end
end
