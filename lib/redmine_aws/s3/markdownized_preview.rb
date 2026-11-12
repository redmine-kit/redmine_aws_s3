# frozen_string_literal: true

module RedmineAws
  module S3
    # Redmine's Markdown preview of an attachment (Pandoc), kept in S3 at the
    # same path as on Redmine's disk (docs/attachments.md#bucket-layout), so
    # that every environment reuses it instead of converting the file again.
    # Redmine writes it under attachments_storage_path, in /tmp on Lambda.
    module MarkdownizedPreview
      module_function

      def key(attachment)
        "#{PREVIEWS_PREFIX}#{File.basename(attachment.markdownized_preview_cache_path)}"
      end

      # The preview of this environment or of S3, without running Redmine's
      # own code (the block), which would fetch the whole original first. The
      # block makes it only when there is none; the one it made is stored.
      def around(attachment)
        target = attachment.markdownized_preview_cache_path
        return File.read(target, mode: 'rb') if File.exist?(target) || fetched?(key(attachment), target)

        content = yield
        if content && File.exist?(target)
          RedmineAws::S3.storage.put_file(key(attachment), target)
          Cache.add(target)
        end
        content
      end

      # Whether the preview was fetched from S3.
      def fetched?(key, target)
        storage = RedmineAws::S3.storage
        return false unless storage.exists?(key)

        FileUtils.mkdir_p(File.dirname(target))
        return false unless storage.download(key, target)

        Cache.add(target)
        true
      end
    end
  end
end
