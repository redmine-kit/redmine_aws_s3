# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'

module RedmineKit
  module Aws
    module S3
      # The plugin's code is under the RedmineKit::Aws namespace of redmine_kit_aws
      # (lib/redmine_kit/aws/s3.rb and lib/redmine_kit/aws/s3/), which Redmine's code
      # loader (Zeitwerk) spreads over both plugins' lib/. Checked in new
      # processes, as at start-up.
      class NamespaceTest < ActiveSupport::TestCase
        def rails(*)
          out, status = Open3.capture2e({ 'RAILS_ENV' => 'test' }, 'bin/rails', *, chdir: Rails.root.to_s)
          assert status.success?, out
          out
        end

        # RedmineKit is the namespace of every plugin of the organization; the
        # code loader makes it from their lib/redmine_kit/ directories. A plugin
        # with lib/redmine_kit.rb would own it.
        def test_no_plugin_file_defines_redmine_kit
          dir = Redmine::Plugin.find(:redmine_kit_aws_s3).directory

          assert_not File.exist?(File.join(dir, 'lib/redmine_kit.rb')), 'lib/redmine_kit.rb defines RedmineKit'
        end

        def test_zeitwerk_loads_every_file
          assert_includes rails('zeitwerk:check'), 'All is good!'
        end

        def test_both_plugins_start
          script = 'print RedmineKit::Aws::VERSION, " ", RedmineKit::Aws::S3::VERSION, " ", ' \
                   'RedmineKit::Aws::Admin.tabs.map(&:name).join(",")'

          assert_equal "#{RedmineKit::Aws::VERSION} #{VERSION} status,s3", rails('runner', script).lines.last.to_s.strip
        end
      end
    end
  end
end
