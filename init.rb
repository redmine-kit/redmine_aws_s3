# frozen_string_literal: true

# The plugins this one requires (config/dependencies.yml): without one,
# Redmine stops here and names it.
load File.expand_path('config/dependencies.rb', __dir__)

# Redmine runs this when it prepares the code, again on every reload. The
# replacements are installed always and do nothing unless REDMINE_S3_BUCKET
# is set (docs/attachments.md#replaced-code).
Redmine::Plugin.register :redmine_kit_aws_s3 do
  # This folder, as Redmine's plugin loader found it: plugins/redmine_kit_aws_s3 (a checkout
  # or a link), or the installed gem's folder (boot/redmine_kit_aws_s3.rb). Redmine's
  # default is plugins/<id>, which a gem doesn't have.
  directory File.dirname(__FILE__)
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
