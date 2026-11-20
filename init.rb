# frozen_string_literal: true

# Redmine runs this when it prepares the code, again on every reload. The
# replacements are installed always and do nothing unless REDMINE_S3_BUCKET
# is set (docs/attachments.md#replaced-code).
Redmine::Plugin.register :redmine_kit_aws_s3 do
  # First: without redmine_kit_aws, Redmine says that the plugin requires it,
  # before the lines below need its RedmineKit::Aws namespace.
  requires_redmine_plugin :redmine_kit_aws, version_or_higher: '0.1.0'
  requires_redmine version_or_higher: '7.0.0'
  name 'Redmine Kit AWS S3'
  author 'Redmine Kit'
  description 'Stores attachments in Amazon S3'
  version RedmineKit::Aws::S3::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_s3'
  author_url 'https://github.com/redmine-kit'
  settings default: RedmineKit::Aws::S3::DEFAULT_SETTINGS, partial: 'settings/redmine_kit_aws_s3'
end

RedmineKit::Aws::S3.setup
