# frozen_string_literal: true

# Redmine Kit AWS S3 as a gem (docs/setup.md#installation): Bundler requires this file
# when Redmine's Gemfile.local has `gem 'redmine_kit_aws_s3'`, or (with a checkout in
# plugins/) the plugin's Gemfile names it by path.
#
# Redmine 7.0.3 loads plugins from its plugins/ folder only
# (Redmine::PluginLoader). This hands the gem's folder to the same loader,
# after Redmine's initializers have listed plugins/: Redmine then runs
# init.rb (which registers the plugin with this folder, `directory`) and
# serves its assets, locales, views and migrations as for any plugin; the
# folder's lib/ and app/ go to Rails' code loader (Zeitwerk) as Redmine adds a
# plugin's (PluginLoader.add_autoload_paths); its routes come after Redmine's,
# as Redmine draws a plugin's. A plugin of the same id in plugins/ (a checkout
# or a link) wins, and nothing is done (redmine_kit_ui's template,
# examples/redmine_kit_example).
#
# No constant is defined here: the plugin's code comes from lib/ through the
# code loader, as in plugins/, so that it reloads and Zeitwerk checks it.
require 'active_support/lazy_load_hooks'
# The gems of the plugins it requires (config/dependencies.yml): Bundler
# installs them with this one, and their boot files hand their folders to
# Redmine's plugin loader too.
require 'yaml'
YAML.safe_load_file(File.expand_path('../config/dependencies.yml', __dir__))['requires'].each_key do |name|
  require name
end

ActiveSupport.on_load(:before_configuration, yield: true) do |app|
  dir = File.expand_path('..', __dir__)
  app.initializer 'redmine_kit_aws_s3.gem', after: :load_config_initializers do |application|
    loader = Redmine::PluginLoader
    next if loader.directories.any? { |path| File.basename(path.to_s) == 'redmine_kit_aws_s3' }

    loader.directories << Redmine::PluginPath.new(dir)
    Rails::Engine::Configuration.new(dir).tap { |config| config.paths.add 'lib', eager_load: true }
                                .all_eager_load_paths.each do |path|
      Rails.autoloaders.main.push_dir(path)
      application.config.watchable_dirs[path] = [:rb]
    end
    routes = File.join(dir, 'config/routes.rb')
    application.routes.append { instance_eval(File.read(routes), routes) } if File.file?(routes)
  end
end
