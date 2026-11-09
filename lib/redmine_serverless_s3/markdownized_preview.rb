# frozen_string_literal: true

module RedmineServerlessS3
  # Redmine's Markdown preview of an attachment (Pandoc), kept in S3 at the
  # same path as on Redmine's disk (docs/attachments.md#bucket-layout), so
  # that every environment reuses it instead of converting the file again.
  # Redmine writes it under attachments_storage_path, in /tmp on Lambda.
  module MarkdownizedPreview
    module_function

    def key(attachment)
      "#{PREVIEWS_PREFIX}#{File.basename(attachment.markdownized_preview_cache_path)}"
    end

    # Runs Redmine's own code (the block) with the preview fetched from S3
    # when this environment does not have it, and stores the one it made.
    def around(attachment)
      target = attachment.markdownized_preview_cache_path
      fetch(key(attachment), target) unless File.exist?(target)
      made_here = !File.exist?(target)
      content = yield
      RedmineServerlessS3.storage.put_file(key(attachment), target) if content && made_here && File.exist?(target)
      content
    end

    def fetch(key, target)
      storage = RedmineServerlessS3.storage
      return unless storage.exists?(key)

      FileUtils.mkdir_p(File.dirname(target))
      storage.download(key, target)
    end
  end
end
