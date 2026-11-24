# frozen_string_literal: true

require 'yaml'

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_kit_aws_s3'
  spec.version = File.read(File.join(__dir__, 'lib/redmine_kit/aws/s3.rb'))[/VERSION = '([^']+)'/, 1]
  spec.summary = 'Stores attachments in Amazon S3'
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_aws_s3'
  # The Ruby versions of Redmine 7.0 (its Gemfile: ruby '>= 3.2.0', '< 4.1.0').
  spec.required_ruby_version = ['>= 3.2', '< 4.1']
  spec.require_paths = ['boot']
  spec.files = Dir['{init.rb,LICENSE}', '{app,boot,assets,config,db,lib,help}/**/*']
  # aws-sdk-s3 1.202.0 (2025-10-28) added the conditional writes of CopyObject
  # (If-None-Match), which the registration of uploads uses, after ChecksumType
  # (FULL_OBJECT, 1.178.0), which it checks; the CloudFront URL signer is in
  # every 1.x.
  spec.add_dependency 'aws-sdk-cloudfront', '~> 1.0'
  spec.add_dependency 'aws-sdk-s3', '~> 1.202'
  # rubyzip writes the zip of "Download all attachments" (BulkDownload).
  # Redmine 7.0.3 has it in its default group (~> 3.4.0); Redmine's master
  # moved it to the test group, so the plugin names it itself.
  spec.add_dependency 'rubyzip', '~> 3.4'
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_aws_s3'
  # The plugins it requires (config/dependencies.yml): installing the gem installs them.
  YAML.safe_load_file(File.join(__dir__, 'config/dependencies.yml'))['requires'].each do |name, range|
    spec.add_dependency name, range
  end
  spec.metadata['rubygems_mfa_required'] = 'true'
end
