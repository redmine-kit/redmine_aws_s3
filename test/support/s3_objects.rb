# frozen_string_literal: true

module RedmineKit
  module Aws
    module S3
      # Objects in the bucket of the integration tests (with_test_s3).
      module S3Objects
        def object(key)
          RedmineKit::Aws::S3.client.get_object(bucket: RedmineKit::Aws::S3.bucket, key: key).body.read
        rescue ::Aws::S3::Errors::NoSuchKey
          nil
        end

        def keys(prefix = '')
          RedmineKit::Aws::S3.storage.keys(prefix)
        end

        def put_object(key, body)
          RedmineKit::Aws::S3.client.put_object(bucket: RedmineKit::Aws::S3.bucket, key: key, body: body)
        end

        # The tag GuardDuty puts after its scan (GuardDuty is not reproduced
        # locally).
        def tag_scan(key, value)
          RedmineKit::Aws::S3.client.put_object_tagging(
            bucket: RedmineKit::Aws::S3.bucket, key: key,
            tagging: { tag_set: [{ key: RedmineKit::Aws::S3::MalwareScan::TAG, value: value }] }
          )
        end
      end
    end
  end
end
