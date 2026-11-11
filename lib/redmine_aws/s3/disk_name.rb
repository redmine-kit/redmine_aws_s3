# frozen_string_literal: true

module RedmineAws
  module S3
    # File names of attachments registered from S3, made as Redmine's
    # Attachment.create_diskfile makes them (yymmddHHMMSS_ and the name, or its
    # hash for names that are not short ASCII).
    module DiskName
      MAX_LENGTH = 50
      # How many names claim tries before it gives up.
      ATTEMPTS = 5

      module_function

      # A name not used in S3, by another attachment in the directory, or by a
      # file in the directory on the local disk, which Redmine's
      # create_diskfile also checks (the /tmp cache keeps S3 objects there).
      def free(filename, directory)
        timestamp = Time.zone.now.strftime('%y%m%d%H%M%S')
        loop do
          name = "#{timestamp}_#{ascii(filename)}"
          return name unless taken?(directory, name)

          timestamp = timestamp.succ
        end
      end

      # Yields a name (first, or a free one) to the block, which stores the
      # file under it with a conditional write, and returns the name. When
      # another Redmine server stored a file under that name first (S3's
      # Storage::KeyTaken: same second, same name, a different /tmp), it
      # yields the next free name.
      def claim(filename, directory, first: nil)
        name = first || free(filename, directory)
        ATTEMPTS.times do
          yield name
          return name
        rescue Storage::KeyTaken
          name = free(filename, directory)
        end
        raise Storage::KeyTaken, name
      end

      def ascii(filename)
        return filename if /\A[a-zA-Z0-9_.-]*\z/.match?(filename) && filename.length <= MAX_LENGTH

        hashed = ActiveSupport::Digest.hexdigest(filename)
        ext = filename[/(\.[a-zA-Z0-9]+)\z/, 1]
        ext && (hashed.length + ext.length) <= MAX_LENGTH ? hashed + ext : hashed
      end

      def taken?(directory, name)
        File.exist?(File.join(::Attachment.storage_path, directory.to_s, name)) ||
          Attachment.exists?(disk_directory: directory, disk_filename: name) ||
          RedmineAws::S3.storage.exists?(RedmineAws::S3.file_key(directory, name))
      end
    end
  end
end
