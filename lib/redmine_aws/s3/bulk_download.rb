# frozen_string_literal: true

require 'zip'

module RedmineAws
  module S3
    # "Download all attachments" (docs/attachments.md#downloading-all-attachments):
    # the zip is written to /tmp one file at a time, stored at tmp/bulk/ in S3,
    # and reused while it is there for the same set of attachments.
    class BulkDownload
      def initialize(attachments)
        @attachments = attachments.select(&:readable?)
      end

      # The S3 key of the zip, or nil when there is nothing to archive.
      def store
        return nil if @attachments.empty?

        key = "#{RedmineAws::S3::BULK_PREFIX}#{signature}.zip"
        storage = RedmineAws::S3.storage
        return key if storage.exists?(key)

        Dir.mktmpdir('redmine-bulk') do |dir|
          zip = File.join(dir, 'attachments.zip')
          write_zip(zip)
          storage.put_file(key, zip)
        end
        key
      end

      private

      # The same set of attachments (ids and digests) gives the same key.
      def signature
        Digest::SHA256.hexdigest(@attachments.sort_by(&:id).map { |a| "#{a.id}:#{a.digest}" }.join(','))
      end

      # Redmine's Attachment.archive_attachments, written to a file instead of
      # memory.
      def write_zip(path)
        Zip.unicode_names = true
        names = []
        Zip::OutputStream.open(path) do |zos|
          @attachments.each do |attachment|
            name = unique_name(attachment.filename, names)
            zos.put_next_entry(name)
            File.open(attachment.diskfile, 'rb') { |io| IO.copy_stream(io, zos) }
            names << name
          end
        end
      end

      def unique_name(filename, names)
        name = filename
        count = 0
        while names.include?(name)
          count += 1
          extname = File.extname(filename)
          name = "#{File.basename(filename, extname)}(#{count})#{extname}"
        end
        name
      end
    end
  end
end
