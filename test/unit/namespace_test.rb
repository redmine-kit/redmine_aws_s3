# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'

module RedmineAws
  module S3
    # The plugin's code is under the RedmineAws namespace of redmine_aws
    # (lib/redmine_aws/s3.rb and lib/redmine_aws/s3/), which Redmine's code
    # loader (Zeitwerk) spreads over both plugins' lib/. Checked in new
    # processes, as at start-up.
    class NamespaceTest < ActiveSupport::TestCase
      def rails(*)
        out, status = Open3.capture2e({ 'RAILS_ENV' => 'test' }, 'bin/rails', *, chdir: Rails.root.to_s)
        assert status.success?, out
        out
      end

      def test_zeitwerk_loads_every_file
        assert_includes rails('zeitwerk:check'), 'All is good!'
      end

      def test_both_plugins_start
        script = 'print RedmineAws::VERSION, " ", RedmineAws::S3::VERSION, " ", ' \
                 'RedmineAws::Admin.tabs.map(&:name).join(",")'

        assert_equal "#{RedmineAws::VERSION} #{VERSION} status,s3", rails('runner', script).lines.last.to_s.strip
      end
    end
  end
end
