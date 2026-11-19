# frozen_string_literal: true

# Loaded by Redmine's Gemfile when the plugin is in plugins/. The installed
# gem brings the same gems through its gemspec.
gem 'aws-sdk-cloudfront', '~> 1.0'
gem 'aws-sdk-s3', '~> 1.202'
# rubyzip (BulkDownload), unless Redmine's Gemfile has it already: a second
# line would conflict with its version. Redmine 7.0.3 has it in its default
# group; master only in its test group, so there only the gem (its gemspec)
# brings it to production.
gem 'rubyzip', '~> 3.4' unless dependencies.any? { |dependency| dependency.name == 'rubyzip' }
