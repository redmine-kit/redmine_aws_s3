# frozen_string_literal: true

module RedmineAws
  module S3
    # The file that Redmine wrote for an attachment (uploads through Lambda,
    # mail, forms), put to S3 under the name Redmine chose, or under the next
    # free one when another Redmine server stored a file under it first
    # (Redmine checks only this /tmp). The local file is renamed with it.
    module AttachmentFile
      module_function

      def put(attachment)
        path = attachment.local_diskfile
        directory = attachment.disk_directory
        attachment.disk_filename = DiskName.claim(attachment.filename, directory,
                                                  first: attachment.disk_filename) do |name|
          MalwareScan.put(path, RedmineAws::S3.file_key(directory, name),
                          filename: attachment.filename, user: attachment.author)
        end
        FileUtils.mv(path, attachment.local_diskfile) unless path == attachment.local_diskfile
        # In S3 now: the local file is a copy that the cache may delete.
        Cache.add(attachment.local_diskfile)
      end
    end
  end
end
