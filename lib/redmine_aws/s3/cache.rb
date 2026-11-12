# frozen_string_literal: true

module RedmineAws
  module S3
    # The local cache of S3 under Redmine's attachments_storage_path
    # (docs/attachments.md#the-tmp-cache): files are fetched when Redmine reads
    # them, kept while the environment lives, and the least recently used ones
    # are deleted beyond the size limit. Only files known to be in S3 (fetched
    # from it or put to it) are cached, each marked by an empty file next to
    # it: files that were there before (the originals of a Redmine that starts
    # using S3) are never deleted.
    module Cache
      MARK = '.s3cache'
      PART_LIMIT = 1.hour

      module_function

      # Makes the object at key available at path. Returns the path, or nil
      # if the object is not in S3.
      def fetch(key, path)
        if File.exist?(path)
          touch(path)
          return path
        end
        return nil unless RedmineAws::S3.storage.download(key, path)

        add(path)
        path
      end

      # Marks the file at path, which is in S3, as cached, and prunes.
      def add(path)
        FileUtils.touch("#{path}#{MARK}")
        prune(keep: path)
      rescue SystemCallError
        nil
      end

      def cached?(path)
        File.exist?("#{path}#{MARK}")
      end

      def touch(path)
        now = Time.now
        File.utime(now, now, path)
      rescue SystemCallError
        nil
      end

      # Deletes the least recently used cached files under the storage path
      # until their total is under the limit. Markdown previews
      # (derived_cache) count too.
      def prune(keep: nil, root: Attachment.storage_path, limit: RedmineAws::S3.cache_size)
        files = cached_files(root)
        total = files.sum { |_, size, _| size }
        files.sort_by { |_, _, mtime| mtime }.each do |file, size, _|
          break if total <= limit
          next if file == keep

          delete(file)
          total -= size
        end
        delete_partial_downloads(root)
      end

      # Deletes a cached file and its mark.
      def delete(path)
        FileUtils.rm_f([path, "#{path}#{MARK}"])
      end

      # [path, size, mtime] of each cached file under root, found by its mark
      # (only the marked files are read, not every file of the directory). A
      # mark whose file is gone is deleted.
      def cached_files(root)
        Dir.glob(File.join(root, '**', "*#{MARK}")).filter_map do |mark|
          file = mark.delete_suffix(MARK)
          stat = File.stat(file)
          [file, stat.size, stat.mtime]
        rescue Errno::ENOENT
          FileUtils.rm_f(mark)
          nil
        rescue SystemCallError
          nil
        end
      end

      # Storage#download writes to <path>.<random>.part and renames it; a
      # process stopped in between leaves the part, deleted after an hour.
      def delete_partial_downloads(root)
        Dir.glob(File.join(root, '**', '*.part')).each do |part|
          FileUtils.rm_f(part) if File.mtime(part) < PART_LIMIT.ago
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
