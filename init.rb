# frozen_string_literal: true

# Redmine runs this when it prepares the code, again on every reload. The
# replacements are installed always and do nothing unless REDMINE_S3_BUCKET
# is set (docs/attachments.md#replaced-code).
Redmine::Plugin.register :redmine_serverless_s3 do
  name 'Redmine Serverless S3'
  author 'Redmine Kit'
  description 'Stores attachments in Amazon S3, uploaded and downloaded through CloudFront'
  version '0.1.2'
  url 'https://github.com/redmine-kit/redmine_serverless_s3'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'
  settings default: RedmineServerlessS3::DEFAULT_SETTINGS, partial: 'settings/redmine_serverless_s3'
end

RedmineServerlessS3.setup
