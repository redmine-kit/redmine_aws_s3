# frozen_string_literal: true

require File.expand_path('../../../test/test_helper', __dir__)
require File.join(Redmine::Plugin.find(:redmine_aws).directory, 'test/support/redmine_aws/test_helper')

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

module RedmineAws
  module S3
    # Assertions on the CloudFront signed URLs that the plugin makes, with the
    # key pair of the tests (TestHelper).
    module SignedUrlAssertions
      # Checks a CloudFront signed URL (canned policy) with the public key and
      # returns the URL without the signature parameters and the expiry.
      def verify_signed_url(url)
        uri = URI(url)
        params = URI.decode_www_form(uri.query).to_h
        assert_equal TestHelper::KEY_PAIR_ID, params['Key-Pair-Id']
        assert params['Signature'] && params['Expires'], 'the URL has no canned policy signature'
        assert_canned_policy_signature(url, params['Signature'], params['Expires'])
        [url_without_signature(uri, params), params['Expires'].to_i]
      end

      def url_without_signature(uri, params)
        rest = params.except('Signature', 'Expires', 'Key-Pair-Id')
        "#{uri.scheme}://#{uri.host}#{uri.path}#{"?#{URI.encode_www_form(rest)}" if rest.any?}"
      end

      # The signature of the canned policy of the URL, checked with the public key.
      def assert_canned_policy_signature(url, signature, expires)
        # The SDK signs the URL as it was given, before its own parameters.
        resource = url.split(/[?&]Expires=/).first
        policy = %({"Statement":[{"Resource":"#{resource}","Condition":{"DateLessThan":{"AWS:EpochTime":#{expires}}}}]})
        raw = Base64.decode64(signature.tr('-_~', '+=/'))
        assert TestHelper.private_key.public_key.verify(OpenSSL::Digest.new('SHA1'), raw, policy),
               'the signature does not verify with the public key'
      end
    end

    # Turns the plugin on for a test, with S3 stubbed by the SDK (stub_responses)
    # or reproduced by LocalStack or moto (S3_TEST_ENDPOINT, set by bin/test), and a
    # CloudFront key pair made for the test.
    module TestHelper
      include RedmineAws::TestHelper
      include SignedUrlAssertions

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
        saved_client = RedmineAws::S3.instance_variable_get(:@client)
        with_env(s3_env(bucket: bucket)) do
          RedmineAws::S3.client = client
          yield client
        end
      ensure
        RedmineAws::S3.client = saved_client
      end

      # Runs the block with REDMINE_S3_MALWARE_SCAN=true, without waiting
      # between the requests for the scan tag.
      def with_malware_scan(&)
        MalwareScan.stubs(:wait_seconds).returns(0)
        with_env(ENV_MALWARE_SCAN => 'true', &)
      end

      # The plugin's own lines ([redmine_aws_s3]) that the block writes to
      # Rails' log, where controllers write too.
      def capture_log
        io = StringIO.new
        logger = ActiveSupport::Logger.new(io)
        Rails.logger.broadcast_to(logger)
        yield
        io.string.lines.grep(/\[redmine_aws_s3\]/).join
      ensure
        Rails.logger.stop_broadcasting_to(logger)
      end

      def scan_tag(status)
        { tag_set: status ? [{ key: MalwareScan::TAG, value: status }] : [] }
      end

      def stub_client(**)
        stub_aws_client(::Aws::S3::Client, **)
      end

      # The operations of the requests of a stubbed client, in order.
      def operations(client)
        client.api_requests.pluck(:operation_name)
      end

      # The params of the last request of a stubbed client for each operation.
      def last_params(client)
        client.api_requests.to_h { |request| [request[:operation_name], request[:params]] }
      end

      # The first request of a stubbed client for the operation.
      def api_request(client, operation)
        client.api_requests.find { |request| request[:operation_name] == operation }
      end

      # The keys of the DeleteObjects requests of a stubbed client, in order.
      def deleted_keys(client)
        client.api_requests.select { |request| request[:operation_name] == :delete_objects }
              .flat_map { |request| request[:params][:delete][:objects].pluck(:key) }
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
        ::Aws::S3::Client.new(endpoint: ENV.fetch('S3_TEST_ENDPOINT'), force_path_style: true,
                              region: TEST_REGION, credentials: RedmineAws::TestHelper.credentials,
                              **LOCALSTACK_CONNECTIONS)
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

    # Uploads through CloudFront (Upload, AvatarUpload) by jsmith, with S3
    # stubbed: shared by the tests of the uploads.
    module UploadTestHelper
      include S3::TestHelper

      CONTENT = 'uploaded contents'

      def setup
        set_tmp_attachments_directory
        @user = User.find(2)
      end

      def upload
        RedmineAws::S3::Upload.new(@user)
      end

      def avatar_upload
        RedmineAws::S3::AvatarUpload.new(@user)
      end

      def presign(**)
        upload.presign(filename: 'report.txt', size: CONTENT.bytesize, content_type: 'text/plain', **)
      end

      def head_of(content, checksum: sha256_base64(content), type: 'FULL_OBJECT')
        { content_length: content.bytesize, checksum_sha256: checksum, checksum_type: type }
      end

      # Asserts that completing an upload fails with an error that includes
      # the text, and saves no attachment.
      def assert_complete_refused(text)
        assert_no_difference 'Attachment.count' do
          error = assert_raises(RedmineAws::S3::Upload::Error) { upload.complete(presign[:ticket]) }
          assert_includes error.message, text
        end
      end

      # Asserts that an object under each prefix was deleted.
      def assert_deleted_under(client, *prefixes)
        deleted = deleted_keys(client)
        prefixes.each do |prefix|
          assert(deleted.any? { |key| key.start_with?(prefix) }, "nothing under #{prefix} was deleted")
        end
      end
    end

    # Attachments of issue 1 by the administrator, saved through Redmine:
    # shared by the tests of AttachmentPatch.
    module AttachmentTestHelper
      include S3::TestHelper

      def setup
        set_tmp_attachments_directory
        User.current = nil
      end

      def new_issue_attachment(filename, content)
        Attachment.new(container: Issue.find(1), author: User.find(1),
                       file: mock_file(filename: filename, content: content))
      end

      def create_issue_attachment(filename, content)
        new_issue_attachment(filename, content).tap(&:save!)
      end
    end
  end
end
