# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The plugin's locale files: the same keys in every language, and no key
    # that repeats one of redmine_aws, which the AWS plugins share.
    class LocalesTest < ActiveSupport::TestCase
      LANGUAGES = %w[en ja].freeze

      # Looked up by GuardDuty's status name (MalwareScan.status_label), so
      # it keeps its own key although redmine_aws has the same words.
      OWN_KEYS = %w[label_aws_s3_scan_result_failed].freeze

      def strings(plugin, language)
        path = File.join(Redmine::Plugin.find(plugin).directory, "config/locales/#{language}.yml")
        YAML.safe_load_file(path).fetch(language)
      end

      # Each key with its strings in every language.
      def translations(plugin)
        by_language = LANGUAGES.map { |language| strings(plugin, language) }
        by_language.first.keys.index_with { |key| by_language.map { |language| language[key] } }
      end

      def test_every_language_has_the_same_keys
        keys = LANGUAGES.map { |language| strings(:redmine_aws_s3, language).keys.sort }

        assert_equal keys.first, keys.last
      end

      def test_strings_of_redmine_aws_are_not_repeated
        shared = translations(:redmine_aws).values
        repeated = translations(:redmine_aws_s3).except(*OWN_KEYS).select { |_, texts| shared.include?(texts) }

        assert_empty repeated.keys, 'use the key of redmine_aws'
      end
    end
  end
end
