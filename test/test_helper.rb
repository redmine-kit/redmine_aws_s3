# frozen_string_literal: true

require File.expand_path('../../../test/test_helper', __dir__)

# Coverage of the plugin's own files. Redmine's test helper starts SimpleCov
# before Rails boots when COVERAGE is set (bin/test sets it); the report goes
# to coverage/ in the plugin, in Cobertura for Codecov and in HTML.
if ENV['COVERAGE'] && defined?(SimpleCov)
  require 'simplecov-cobertura'
  plugin_root = File.expand_path('..', __dir__)
  SimpleCov.root plugin_root
  SimpleCov.coverage_dir 'coverage'
  SimpleCov.track_files '{app,lib}/**/*.rb'
  SimpleCov.add_filter { |file| !file.filename.start_with?("#{plugin_root}/") }
  SimpleCov.add_filter { |file| file.filename.start_with?("#{plugin_root}/test/") }
  SimpleCov.formatters = [SimpleCov::Formatter::CoberturaFormatter, SimpleCov::Formatter::HTMLFormatter]
end

module RedmineServerlessS3
  # Turns the plugin on for a test, with S3 stubbed by the SDK (stub_responses)
  # or reproduced by LocalStack or moto (S3_TEST_ENDPOINT, set by bin/test), and a
  # CloudFront key pair made for the test.
  module TestHelper
    DOMAIN = 'redmine.example.test'
    KEY_PAIR_ID = 'KTESTKEYPAIR'

    def self.private_key
      @private_key ||= OpenSSL::PKey::RSA.new(2048)
    end

    def s3_env(bucket: 'redmine-files')
      { ENV_BUCKET => bucket, ENV_REGION => 'us-east-1', ENV_DOMAIN => DOMAIN, ENV_KEY_PAIR_ID => KEY_PAIR_ID,
        ENV_PRIVATE_KEY => TestHelper.private_key.to_pem }
    end

    # Runs the block with the plugin on and the given S3 client.
    def with_s3(client, bucket: 'redmine-files')
      saved_env = s3_env.keys.index_with { |name| ENV.fetch(name, nil) }
      saved_client = RedmineServerlessS3.instance_variable_get(:@client)
      s3_env(bucket: bucket).each { |name, value| ENV[name] = value }
      RedmineServerlessS3.client = client
      yield client
    ensure
      saved_env.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
      RedmineServerlessS3.client = saved_client
    end

    # Runs the block with REDMINE_S3_MALWARE_SCAN=true, without waiting
    # between the requests for the scan tag.
    def with_malware_scan
      saved = ENV.fetch(ENV_MALWARE_SCAN, nil)
      ENV[ENV_MALWARE_SCAN] = 'true'
      MalwareScan.stubs(:wait_seconds).returns(0)
      yield
    ensure
      saved.nil? ? ENV.delete(ENV_MALWARE_SCAN) : ENV[ENV_MALWARE_SCAN] = saved
    end

    def scan_tag(status)
      { tag_set: status ? [{ key: MalwareScan::TAG, value: status }] : [] }
    end

    def stub_client(**stubs)
      Aws::S3::Client.new(stub_responses: stubs.presence || true, region: 'us-east-1',
                          credentials: Aws::Credentials.new('test', 'test'))
    end

    # LocalStack or moto (S3_TEST_BACKEND, chosen by bin/test).
    def s3_test_backend
      ENV.fetch('S3_TEST_BACKEND', 'moto')
    end

    # LocalStack 2026.10.6 sometimes answers 400 with no body to a request on
    # a reused connection when several test processes send at once (about 1
    # in 1,000 PutObject with 4 processes, none with new connections;
    # reproduced on 2026-11-11). S3 does not, so the tests' client does not
    # keep idle connections. Also used by test/core/additional_environment.rb.
    LOCALSTACK_CONNECTIONS = { http_idle_timeout: 0 }.freeze

    # A client of the S3 of the tests; skips the test without it.
    def s3_test_client
      skip 'S3_TEST_ENDPOINT is not set (bin/test sets it)' unless ENV['S3_TEST_ENDPOINT']
      Aws::S3::Client.new(endpoint: ENV.fetch('S3_TEST_ENDPOINT'), force_path_style: true, region: 'us-east-1',
                          credentials: Aws::Credentials.new('test', 'test'), **LOCALSTACK_CONNECTIONS)
    end

    def with_test_s3(&)
      client = s3_test_client
      bucket = "redmine-test-#{SecureRandom.hex(6)}"
      client.create_bucket(bucket: bucket)
      with_s3(client, bucket: bucket, &)
    ensure
      if client && bucket
        keys = client.list_objects_v2(bucket: bucket).contents.map { |object| { key: object.key } }
        client.delete_objects(bucket: bucket, delete: { objects: keys }) if keys.any?
        client.delete_bucket(bucket: bucket)
      end
    end

    # HeadObject as S3 answers it for an object uploaded with a SHA256
    # checksum, where the backend does not return the checksum or its type
    # (moto 5.2.5 returns the SHA256 of a copy without ChecksumType with
    # aws-sdk-s3 1.240, checked on 2026-11-10). On only inside
    # emulate_s3_checksums, from any thread (the system tests' server runs in
    # its own).
    module EmulatedChecksums
      class << self
        attr_accessor :enabled
      end

      def head(key, checksum: false)
        result = super
        return result unless EmulatedChecksums.enabled && result && checksum
        return result unless result.checksum_sha256.nil? || result.checksum_type.nil?

        data = client.get_object(bucket: bucket, key: key).body.read
        Struct.new(:content_length, :checksum_sha256, :checksum_type)
              .new(result.content_length, Digest::SHA256.base64digest(data), 'FULL_OBJECT')
      end
    end

    def emulate_s3_checksums
      Storage.prepend(EmulatedChecksums) unless Storage < EmulatedChecksums
      EmulatedChecksums.enabled = true
      yield
    ensure
      EmulatedChecksums.enabled = false
    end

    def sha256_base64(data)
      Digest::SHA256.base64digest(data)
    end

    # Checks a CloudFront signed URL (canned policy) with the public key and
    # returns the URL without the signature parameters and the expiry.
    def verify_signed_url(url)
      uri = URI(url)
      params = URI.decode_www_form(uri.query).to_h
      signature = params['Signature']
      expires = params['Expires']
      assert_equal KEY_PAIR_ID, params['Key-Pair-Id']
      assert signature && expires, 'the URL has no canned policy signature'
      rest = params.except('Signature', 'Expires', 'Key-Pair-Id')
      unsigned = "#{uri.scheme}://#{uri.host}#{uri.path}#{"?#{URI.encode_www_form(rest)}" if rest.any?}"
      # The SDK signs the URL as it was given, before its own parameters.
      resource = url.split(/[?&]Expires=/).first
      policy = %({"Statement":[{"Resource":"#{resource}","Condition":{"DateLessThan":{"AWS:EpochTime":#{expires}}}}]})
      raw = Base64.decode64(signature.tr('-_~', '+=/'))
      assert TestHelper.private_key.public_key.verify(OpenSSL::Digest.new('SHA1'), raw, policy),
             'the signature does not verify with the public key'
      [unsigned, expires.to_i]
    end
  end
end
