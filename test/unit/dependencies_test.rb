# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'

# The plugins this one requires and suggests (config/dependencies.yml, README.md
# "Requirements"): init.rb stops Redmine at boot without a required one
# (config/dependencies.rb), and the gem depends on exactly the required ones, so
# that installing it installs them. The same file in every plugin of Redmine Kit
# (copied from redmine_kit_ui/examples/redmine_kit_example).
class DependenciesTest < ActiveSupport::TestCase
  ROOT = File.expand_path('../..', __dir__)
  DEPENDENCIES = YAML.safe_load_file(File.join(ROOT, 'config/dependencies.yml'))

  def requires
    DEPENDENCIES['requires'] || {}
  end

  # config/dependencies.rb as init.rb loads it, with these plugin folders and
  # this dependencies.yml.
  def check(folders, dependencies = DEPENDENCIES)
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(ROOT, 'config/dependencies.rb'), dir)
      File.write(File.join(dir, 'dependencies.yml'), dependencies.to_yaml)
      paths = folders.map { |name| Redmine::PluginPath.new(File.join(dir, name)) }
      Redmine::PluginLoader.stubs(:directories).returns(paths)
      load File.join(dir, 'dependencies.rb')
    end
  end

  test 'the file names this plugin and lists plugins of Redmine Kit only' do
    assert_equal File.basename(Dir[File.join(ROOT, '*.gemspec')].first, '.gemspec'), DEPENDENCIES.fetch('plugin')
    (requires.keys + Array(DEPENDENCIES['suggests'])).each { |id| assert_match(/\Aredmine_kit_\w+\z/, id) }
    assert_empty requires.keys & Array(DEPENDENCIES['suggests'])
  end

  # before any line that could use a required plugin's code (a NameError otherwise)
  test 'init.rb checks the required plugins before anything else' do
    statements = File.readlines(File.join(ROOT, 'init.rb')).map(&:strip)
    statements = statements.reject { |line| line.empty? || line.start_with?('#') }
    assert_equal "load File.expand_path('config/dependencies.rb', __dir__)", statements.first
  end

  test 'Redmine boots with every required plugin installed, from plugins/ or as a gem' do
    assert_nothing_raised { check(requires.keys) }
    assert_nothing_raised { check(requires.keys.map { |id| "#{id}-0.1.0" }) }
  end

  test 'Redmine stops at boot without a required plugin, and names it' do
    fake = { 'plugin' => 'redmine_kit_example', 'requires' => { 'redmine_kit_needed' => '~> 0.1' } }
    error = assert_raises(Redmine::PluginRequirementError) { check(%w[redmine_kit_needed_too], fake) }
    assert_includes error.message, 'redmine_kit_example requires the plugin redmine_kit_needed'
    requires.each_key do |id|
      assert_raises(Redmine::PluginRequirementError) { check(requires.keys - [id]) }
    end
  end

  test 'the gem depends on the required plugins, at the ranges of the file' do
    spec = Gem::Specification.load(Dir[File.join(ROOT, '*.gemspec')].first)
    kit = spec.runtime_dependencies.select { |dependency| dependency.name.start_with?('redmine_kit_') }
    assert_equal(requires.transform_values { |range| Gem::Requirement.new(range) },
                 kit.to_h { |dependency| [dependency.name, dependency.requirement] })
  end
end
