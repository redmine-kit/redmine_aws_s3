# frozen_string_literal: true

# The plugins this plugin requires (config/dependencies.yml, `requires`),
# checked first in init.rb, before anything uses them: without one, Redmine
# stops at boot and names it. Redmine 7.0.3 runs every plugin's init.rb after it
# has listed the folders of all plugins (plugins/ and those the gems' boot files
# add), so the list says whether a plugin is installed whatever order the
# init.rb files run in; requires_redmine_plugin sees only the plugins
# registered before and can't. A gem's folder carries its version or revision
# (redmine_kit_subprojects-0.1.0). The same file in every plugin of Redmine Kit
# (copied from redmine_kit_ui/examples/redmine_kit_example).
require 'yaml'

lambda do
  dependencies = YAML.safe_load_file(File.join(__dir__, 'dependencies.yml'))
  folders = Redmine::PluginLoader.directories.map { |path| File.basename(path.to_s) }
  (dependencies['requires'] || {}).each_key do |id|
    next if folders.any? { |name| name == id || name.match?(/\A#{Regexp.escape(id)}-[\w.]+\z/) }

    raise Redmine::PluginRequirementError,
          "#{dependencies.fetch('plugin')} requires the plugin #{id}: install it (README.md, \"Required plugins\")"
  end
end.call
