# frozen_string_literal: true

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_aws_s3'
  spec.version = File.read(File.join(__dir__, 'lib/redmine_aws/s3.rb'))[/VERSION = '([^']+)'/, 1]
  spec.summary = 'Stores Redmine attachments in Amazon S3'
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_aws_s3'
  # The Ruby versions of Redmine 7.0 (its Gemfile: ruby '>= 3.2.0', '< 4.1.0').
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['{init.rb,LICENSE}', '{app,assets,config,db,lib,help}/**/*']
  # aws-sdk-s3 1.202.0 (2025-10-28) added the conditional writes of CopyObject
  # (If-None-Match), which the registration of uploads uses, after ChecksumType
  # (FULL_OBJECT, 1.178.0), which it checks; the CloudFront URL signer is in
  # every 1.x.
  spec.add_dependency 'aws-sdk-cloudfront', '~> 1.0'
  spec.add_dependency 'aws-sdk-s3', '~> 1.202'
  # The AWS item of the administration menu, where the S3 tab is.
  spec.add_dependency 'redmine_aws', '~> 0.1'
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_aws_s3'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
