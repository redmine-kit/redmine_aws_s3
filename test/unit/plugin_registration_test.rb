# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module S3
      # How init.rb registers the plugin.
      class PluginRegistrationTest < ActiveSupport::TestCase
        INIT = File.expand_path('../../init.rb', __dir__)

        # Without redmine_kit_aws, Redmine must stop at the requirement with its
        # own message ("requires the redmine_kit_aws plugin"), before any line
        # needs the RedmineKit::Aws namespace (a NameError otherwise).
        def test_the_requirement_on_redmine_kit_aws_comes_first
          block = File.read(INIT)[/^Redmine::Plugin.register :redmine_kit_aws_s3 do\n(.*?)^end/m, 1]
          statements = block.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }

          assert_match(/\Arequires_redmine_plugin :redmine_kit_aws,/, statements.first)
        end
      end
    end
  end
end
