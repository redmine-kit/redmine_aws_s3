# frozen_string_literal: true

module RedmineAws
  module S3
    # The local cache of S3 under Redmine's attachments_storage_path
    # (docs/attachments.md#the-tmp-cache): files are fetched when Redmine reads
    # them, kept while the environment lives, and the least recently used ones
    # are deleted beyond the size limit.
    module Cache
      module_function

      # Makes the object at key available at path. Returns the path, or nil
      # if the object is not in S3.
      def fetch(key, path)
        if File.exist?(path)
          touch(path)
          return path
        end
        return nil unless RedmineAws::S3.storage.download(key, path)

        prune(keep: path)
        path
      end

      def touch(path)
        now = Time.now
        File.utime(now, now, path)
      rescue SystemCallError
        nil
      end

      # Deletes the least recently used files under the storage path until the
      # total is under the limit. Office preview caches (derived_cache) count too.
      def prune(keep: nil, root: Attachment.storage_path, limit: RedmineAws::S3.cache_size)
        files = files_under(root)
        total = files.sum { |_, size, _| size }
        files.sort_by { |_, _, mtime| mtime }.each do |file, size, _|
          break if total <= limit
          next if file == keep

          FileUtils.rm_f(file)
          total -= size
        end
      end

      # [path, size, mtime] of each file under root.
      def files_under(root)
        Dir.glob(File.join(root, '**', '*')).filter_map do |file|
          stat = File.stat(file)
          [file, stat.size, stat.mtime] if stat.file?
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
