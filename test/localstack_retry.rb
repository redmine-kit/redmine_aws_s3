# frozen_string_literal: true

module RedmineServerlessS3
  # For the tests only (test_helper.rb and test/core/additional_environment.rb).
  # LocalStack 2026.10.6 sometimes answers a PutObject that carries a checksum
  # with 400 and no body when several processes send at once: about 1 in 1,000
  # with 4 processes, never without the checksum header (reproduced on
  # 2026-11-11). S3 does not do this, so the tests send such a PutObject once
  # more instead of failing.
  module LocalStackRetry
    def put_file(key, path)
      super
    rescue Aws::S3::Errors::BadRequest => e
      raise unless e.context.http_response.body.respond_to?(:string) && e.context.http_response.body.string.empty?

      super
    end

    def self.install
      Storage.prepend(self) unless Storage.ancestors.include?(self)
    end
  end
end
