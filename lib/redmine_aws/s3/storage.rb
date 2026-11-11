# frozen_string_literal: true

require 'securerandom'

module RedmineAws
  module S3
    # The S3 operations the plugin uses, on one bucket.
    class Storage
      attr_reader :client, :bucket

      def initialize(client, bucket)
        @client = client
        @bucket = bucket
      end

      def put_file(key, path)
        File.open(path, 'rb') do |io|
          client.put_object(bucket: bucket, key: key, body: io, checksum_algorithm: 'SHA256')
        end
      end

      # Writes the object to path through a temporary file in the same
      # directory and a rename, so a partial file is never seen at path.
      # Returns false if the object does not exist.
      def download(key, path)
        FileUtils.mkdir_p(File.dirname(path))
        temp = "#{path}.#{SecureRandom.hex(8)}.part"
        client.get_object(bucket: bucket, key: key, response_target: temp)
        File.rename(temp, path)
        true
      rescue ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::NotFound
        false
      ensure
        FileUtils.rm_f(temp) if temp
      end

      # Writes the object into io. Returns false if the object does not exist.
      def read(key, io)
        client.get_object(bucket: bucket, key: key, response_target: io)
        true
      rescue ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::NotFound
        false
      end

      # The first bytes of the object, or nil if it does not exist.
      def read_start(key, bytes)
        client.get_object(bucket: bucket, key: key, range: "bytes=0-#{bytes - 1}").body.read
      rescue ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::NotFound
        nil
      end

      # HeadObject, or nil if the object does not exist.
      def head(key, checksum: false)
        params = { bucket: bucket, key: key }
        params[:checksum_mode] = 'ENABLED' if checksum
        client.head_object(params)
      rescue ::Aws::S3::Errors::NotFound, ::Aws::S3::Errors::NoSuchKey
        nil
      end

      def exists?(key)
        !head(key).nil?
      end

      def copy(source_key, key)
        client.copy_object(bucket: bucket, key: key, copy_source: "#{bucket}/#{escape_key(source_key)}",
                           checksum_algorithm: 'SHA256')
      end

      def delete(*keys)
        keys = keys.flatten.compact
        return if keys.empty?

        keys.each_slice(1000) do |slice|
          client.delete_objects(bucket: bucket, delete: { objects: slice.map { |key| { key: key } }, quiet: true })
        end
      end

      def keys(prefix)
        result = []
        client.list_objects_v2(bucket: bucket, prefix: prefix).each_page do |page|
          result.concat(page.contents.map(&:key))
        end
        result
      end

      def delete_prefix(prefix)
        delete(keys(prefix))
      end

      private

      def escape_key(key)
        key.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')
      end
    end
  end
end
