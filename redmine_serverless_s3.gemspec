# frozen_string_literal: true

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_serverless_s3'
  spec.version = '0.1.3'
  spec.summary = 'Stores Redmine attachments in Amazon S3'
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_serverless_s3'
  spec.required_ruby_version = '>= 4.0'
  spec.files = Dir['{init.rb,LICENSE}', '{app,assets,config,db,lib,help}/**/*']
  # aws-sdk-s3 1.178.0 (2025-01-15) added ChecksumType (FULL_OBJECT), which
  # the registration of uploads checks; the CloudFront URL signer is in every 1.x.
  spec.add_dependency 'aws-sdk-cloudfront', '~> 1.0'
  spec.add_dependency 'aws-sdk-s3', '~> 1.178'
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_serverless_s3'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
