# frozen_string_literal: true

# Copied to Redmine's config/additional_environment.rb in the test image
# (test/Dockerfile). Only `bin/test core-s3` sets REDMINE_S3_TEST_CORE: it
# turns the plugin on for Redmine's own attachment tests, with S3 from
# LocalStack or moto and a CloudFront key pair made for the run.
if ENV['REDMINE_S3_TEST_CORE'] == '1'
  require 'openssl'
  ENV['REDMINE_CLOUDFRONT_DOMAIN'] ||= 'redmine.example.test'
  ENV['REDMINE_CLOUDFRONT_KEY_PAIR_ID'] ||= 'KTESTKEYPAIR'
  ENV['REDMINE_CLOUDFRONT_PRIVATE_KEY'] ||= OpenSSL::PKey::RSA.new(2048).to_pem

  create_bucket = lambda do |client|
    client.create_bucket(bucket: ENV.fetch('REDMINE_S3_BUCKET'))
  rescue Aws::S3::Errors::BucketAlreadyOwnedByYou, Aws::S3::Errors::BucketAlreadyExists
    nil
  end

  config.after_initialize do
    # No idle connections kept: LocalStack sometimes refuses a request on a
    # reused connection from parallel workers (test_helper.rb,
    # LOCALSTACK_CONNECTIONS).
    client = Aws::S3::Client.new(endpoint: ENV.fetch('S3_TEST_ENDPOINT'), force_path_style: true,
                                 region: 'us-east-1', credentials: Aws::Credentials.new('test', 'test'),
                                 http_idle_timeout: 0)
    create_bucket.call(client)
    RedmineAwsS3.client = client
  end

  # Each parallel worker has its own database and attachments directory; it
  # gets its own bucket too, so that two workers saving files of the same
  # name in the same second do not write the same key.
  ActiveSupport.on_load(:active_support_test_case) do
    parallelize_setup do |worker|
      ENV['REDMINE_S3_BUCKET'] = "#{ENV.fetch('REDMINE_S3_BUCKET')}-#{worker}"
      create_bucket.call(RedmineAwsS3.client)
    end
  end
end
