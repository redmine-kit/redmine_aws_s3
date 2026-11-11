# frozen_string_literal: true

# Redmine runs this when it prepares the code, again on every reload. The
# replacements are installed always and do nothing unless REDMINE_S3_BUCKET
# is set (docs/attachments.md#replaced-code).
Redmine::Plugin.register :redmine_aws_s3 do
  name 'Redmine AWS S3'
  author 'Redmine Kit'
  description 'Stores attachments in Amazon S3, uploaded and downloaded through CloudFront'
  version '0.1.0'
  url 'https://github.com/redmine-kit/redmine_aws_s3'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'
  requires_redmine_plugin :redmine_aws, version_or_higher: '0.1.0'
  settings default: RedmineAwsS3::DEFAULT_SETTINGS, partial: 'settings/redmine_aws_s3'
end

RedmineAwsS3.setup
