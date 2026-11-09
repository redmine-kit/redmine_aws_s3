# frozen_string_literal: true

module RedmineServerlessS3
  # Loads the upload script on every page (attachments can be added in many
  # forms), and on the settings page adds a note on the upload limit
  # (docs/admin.md#maximum-attachment-size).
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      return '' unless RedmineServerlessS3.enabled?

      tags = [
        tag.meta(name: 'redmine-s3-presign-url', content: url_for(controller: '/s3_uploads', action: 'presign',
                                                                  only_path: true)),
        tag.meta(name: 'redmine-s3-complete-url', content: url_for(controller: '/s3_uploads', action: 'complete',
                                                                   format: 'js', only_path: true)),
        javascript_include_tag('s3_upload', plugin: 'redmine_serverless_s3')
      ]
      tags << max_size_note if context[:controller].is_a?(SettingsController)
      safe_join(tags, "\n")
    end

    private

    def max_size_note
      javascript_tag(<<~JS)
        document.addEventListener('DOMContentLoaded', function() {
          var input = document.getElementById('settings_attachment_max_size');
          if (!input || !input.parentNode) { return; }
          var em = document.createElement('em');
          em.className = 'info';
          em.textContent = #{l(:text_redmine_serverless_s3_max_size).to_json};
          input.parentNode.appendChild(em);
        });
      JS
    end
  end
end
