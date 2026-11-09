# frozen_string_literal: true

require 'net/http'
require 'securerandom'

module RedmineServerlessS3
  # The checks of the "Attachments in S3" tab (docs/admin.md). Each returns
  # a list of [name, ok, detail].
  module Checks
    module_function

    # The connection check of the shared Serverless page: HeadBucket.
    def head_bucket
      RedmineServerlessS3.client.head_bucket(bucket: RedmineServerlessS3.bucket)
      RedmineServerlessS3.bucket
    end

    # PutObject, GetObject and DeleteObject on tmp/healthcheck/<UUID>.
    def read_write
      storage = RedmineServerlessS3.storage
      key = "tmp/healthcheck/#{SecureRandom.uuid}"
      body = SecureRandom.hex(16)
      results = []
      results << step('PutObject') { storage.client.put_object(bucket: storage.bucket, key: key, body: body) }
      results << step('GetObject') do
        storage.client.get_object(bucket: storage.bucket, key: key).body.read == body || raise('different contents')
      end
      results << step('DeleteObject') { storage.delete(key) }
      results
    end

    # A check object under tmp/bulk/ through CloudFront: the signed URL
    # returns it with the sandbox CSP and nosniff, and the URL without the
    # signature is refused.
    def delivery
      storage = RedmineServerlessS3.storage
      key = "tmp/bulk/healthcheck-#{SecureRandom.uuid}.txt"
      storage.client.put_object(bucket: storage.bucket, key: key, body: 'ok', content_type: 'text/plain')
      url = RedmineServerlessS3.url_signer.url_for(key, expires_in: 60)
      signed = get(url)
      unsigned = get(url.split('?').first)
      [
        ['Signed URL', signed.is_a?(Net::HTTPOK), signed.code],
        ['Sandbox CSP', signed['content-security-policy'].to_s.include?('sandbox'),
         signed['content-security-policy'].to_s],
        ['nosniff', signed['x-content-type-options'].to_s.casecmp?('nosniff'), signed['x-content-type-options'].to_s],
        ['Unsigned URL refused', %w[401 403].include?(unsigned.code), unsigned.code]
      ]
    rescue StandardError => e
      [['Delivery', false, e.message]]
    ensure
      storage&.delete(key) if key
    end

    def step(name)
      yield
      [name, true, '']
    rescue StandardError => e
      [name, false, e.message]
    end

    def get(url)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
    end
  end
end
