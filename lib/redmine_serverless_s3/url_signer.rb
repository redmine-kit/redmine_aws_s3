# frozen_string_literal: true

module RedmineServerlessS3
  # CloudFront signed URLs on Redmine's own domain, for the cache behaviors
  # /files/*, /thumbnails/*, /tmp/bulk/* and /incoming/* (docs/attachments.md).
  # A canned policy covers exactly the URL, query string included.
  class UrlSigner
    class NotConfigured < StandardError; end

    def initialize(domain:, key_pair_id:, private_key:)
      @domain = domain
      @key_pair_id = key_pair_id
      @private_key = private_key
    end

    # url_for('files/2026/11/name', 'response-content-type' => 'text/plain')
    def url_for(key, query = {}, expires_in:)
      raise NotConfigured, 'the CloudFront domain, key pair ID and private key are needed' unless configured?

      url = "https://#{@domain}/#{escape_path(key)}"
      url += "?#{query.map { |name, value| "#{name}=#{ERB::Util.url_encode(value)}" }.join('&')}" if query.any?
      signer.signed_url(url, expires: Time.now.to_i + expires_in.to_i)
    end

    def configured?
      @domain.present? && @key_pair_id.present? && @private_key.present?
    end

    private

    def signer
      require 'aws-sdk-cloudfront'
      Aws::CloudFront::UrlSigner.new(key_pair_id: @key_pair_id, private_key: @private_key)
    end

    def escape_path(key)
      key.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')
    end
  end
end
