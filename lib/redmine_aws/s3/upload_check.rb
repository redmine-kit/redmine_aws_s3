# frozen_string_literal: true

module RedmineAws
  module S3
    # The checks of an upload's name and size before its URL is signed
    # (Upload#presign), with Redmine's own messages; Upload::Error otherwise.
    module UploadCheck
      module_function

      def check!(filename, size)
        check_request!(filename, size)
        extension = File.extname(filename)
        unless Attachment.valid_extension?(extension)
          raise Upload::Error, ::I18n.t(:error_attachment_extension_not_allowed, extension: extension)
        end

        max = Setting.attachment_max_size.to_i.kilobytes
        raise Upload::Error, ::I18n.t(:error_attachment_too_big, max_size: max) if size > max
      end

      def check_request!(filename, size)
        raise Upload::Error, field_error(:field_filename, :blank) if filename.blank?
        raise Upload::Error, field_error(:field_filesize, :invalid) if size.nil? || size.negative?
      end

      # A message as Redmine's validations write it ("File cannot be blank").
      def field_error(field, message)
        ::I18n.t('errors.format', attribute: ::I18n.t(field),
                                  message: ::I18n.t("activerecord.errors.messages.#{message}"))
      end
    end
  end
end
