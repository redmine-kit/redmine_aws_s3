# frozen_string_literal: true

# Redmine runs this when it prepares the code, again on every reload. The
# replacements are installed always and do nothing unless REDMINE_S3_BUCKET
# is set (docs/attachments.md#replaced-code).
Redmine::Plugin.register :redmine_aws_s3 do
  # First: without redmine_aws, Redmine says that the plugin requires it,
  # before the lines below need its RedmineAws namespace.
  requires_redmine_plugin :redmine_aws, version_or_higher: '0.1.0'
  requires_redmine version_or_higher: '7.0.0'
  name 'Redmine AWS S3'
  author 'Redmine Kit'
  description 'Stores attachments in Amazon S3, uploaded and downloaded through CloudFront'
  version RedmineAws::S3::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_s3'
  author_url 'https://github.com/redmine-kit'
  settings default: RedmineAws::S3::DEFAULT_SETTINGS, partial: 'settings/redmine_aws_s3'
end

RedmineAws::S3.setup
