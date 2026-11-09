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

  config.after_initialize do
    client = Aws::S3::Client.new(endpoint: ENV.fetch('S3_TEST_ENDPOINT'), force_path_style: true,
                                 region: 'us-east-1', credentials: Aws::Credentials.new('test', 'test'))
    begin
      client.create_bucket(bucket: ENV.fetch('REDMINE_S3_BUCKET'))
    rescue Aws::S3::Errors::BucketAlreadyOwnedByYou, Aws::S3::Errors::BucketAlreadyExists
      nil
    end
    RedmineServerlessS3.client = client
  end
end
