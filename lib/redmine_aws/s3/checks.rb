# frozen_string_literal: true

require 'net/http'
require 'securerandom'

module RedmineAws
  module S3
    # The connection tests of the "S3" tab (docs/admin.md). Each returns
    # a list of [name, ok, detail].
    module Checks
      module_function

      # The S3 row of the connection test on the Status tab of redmine_aws:
      # HeadBucket.
      def head_bucket
        RedmineAws::S3.client.head_bucket(bucket: RedmineAws::S3.bucket)
        RedmineAws::S3.bucket
      end

      # PutObject, GetObject and DeleteObject on tmp/healthcheck/<UUID>.
      def read_write
        storage = RedmineAws::S3.storage
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
      # signature is denied.
      def delivery
        storage = RedmineAws::S3.storage
        key = "#{RedmineAws::S3::BULK_PREFIX}healthcheck-#{SecureRandom.uuid}.txt"
        storage.client.put_object(bucket: storage.bucket, key: key, body: 'ok', content_type: 'text/plain')
        url = RedmineAws::S3.url_signer.url_for(key, expires_in: 60)
        delivery_results(get(url), get(url.split('?').first))
      rescue StandardError => e
        [[::I18n.t(:label_aws_s3_delivery), false, e.message]]
      ensure
        storage&.delete(key) if key
      end

      def delivery_results(signed, unsigned)
        csp = signed['content-security-policy'].to_s
        nosniff = signed['x-content-type-options'].to_s
        [
          [::I18n.t(:label_aws_s3_signed_url), signed.is_a?(Net::HTTPOK), signed.code],
          ['CSP sandbox', csp.include?('sandbox'), csp],
          ['nosniff', nosniff.casecmp?('nosniff'), nosniff],
          [::I18n.t(:label_aws_s3_unsigned_url_denied), %w[401 403].include?(unsigned.code), unsigned.code]
        ]
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
end
