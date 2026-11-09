# frozen_string_literal: true

module RedmineServerlessS3
  # File names of attachments registered from S3, made as Redmine's
  # Attachment.create_diskfile makes them (yymmddHHMMSS_ and the name, or its
  # hash for names that are not short ASCII).
  module DiskName
    MAX_LENGTH = 50

    module_function

    # A name not used in S3 or by another attachment in the directory.
    def free(filename, directory)
      timestamp = Time.zone.now.strftime('%y%m%d%H%M%S')
      loop do
        name = "#{timestamp}_#{ascii(filename)}"
        return name unless taken?(directory, name)

        timestamp = timestamp.succ
      end
    end

    def ascii(filename)
      return filename if /\A[a-zA-Z0-9_.-]*\z/.match?(filename) && filename.length <= MAX_LENGTH

      hashed = ActiveSupport::Digest.hexdigest(filename)
      ext = filename[/(\.[a-zA-Z0-9]+)\z/, 1]
      ext && (hashed.length + ext.length) <= MAX_LENGTH ? hashed + ext : hashed
    end

    def taken?(directory, name)
      Attachment.exists?(disk_directory: directory, disk_filename: name) ||
        RedmineServerlessS3.storage.exists?(RedmineServerlessS3.file_key(directory, name))
    end
  end
end
