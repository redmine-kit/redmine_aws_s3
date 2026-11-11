# frozen_string_literal: true

module RedmineAws
  module S3
    # Loads the upload script on every page (attachments can be added in many
    # forms), and the avatar upload script on the avatar pages of Redmine 7.1.
    # On the settings pages loads the script that adds a note on the upload
    # limit (docs/admin.md#maximum-attachment-size). Each script says at its
    # top why it is needed.
    class Hooks < Redmine::Hook::ViewListener
      def view_layouts_base_html_head(context = {})
        return '' unless RedmineAws::S3.enabled?

        tags = upload
        tags.concat(max_size_note) if context[:controller].is_a?(SettingsController)
        tags.concat(avatar_upload) if avatar_page?(context[:controller])
        safe_join(tags, "\n")
      end

      private

      def upload
        [
          tag.meta(name: 'redmine-s3-presign-url', content: url_for(controller: '/s3_uploads', action: 'presign',
                                                                    only_path: true)),
          tag.meta(name: 'redmine-s3-complete-url', content: url_for(controller: '/s3_uploads', action: 'complete',
                                                                     format: 'js', only_path: true)),
          javascript_include_tag('s3_upload', plugin: 'redmine_aws_s3')
        ]
      end

      # The avatar form of Redmine 7.1 (docs/attachments.md#avatars).
      def avatar_page?(controller)
        RedmineAws::S3.avatars? && controller.is_a?(::AvatarsController) && User.avatar_available?
      end

      def avatar_upload
        [
          tag.meta(name: 'redmine-s3-avatar-presign-url',
                   content: url_for(controller: '/s3_avatar_uploads', action: 'presign', only_path: true)),
          tag.meta(name: 'redmine-s3-avatar-check-url',
                   content: url_for(controller: '/s3_avatar_uploads', action: 'check', only_path: true)),
          javascript_include_tag('s3_avatar_upload', plugin: 'redmine_aws_s3')
        ]
      end

      def max_size_note
        [tag.meta(name: 'redmine-s3-max-size-note', content: l(:text_aws_s3_max_size)),
         javascript_include_tag('s3_settings', plugin: 'redmine_aws_s3')]
      end
    end
  end
end
