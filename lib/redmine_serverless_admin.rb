# frozen_string_literal: true

# The "Serverless" item of Redmine's administration menu, shared by the Redmine
# Serverless plugins (redmine_serverless docs/admin.md#the-serverless-menu).
# Every plugin ships this file, ServerlessAdminController and the view
# serverless_admin/_tabs unchanged; Zeitwerk and the view paths use the first
# copy and ignore the others. So the menu item is added once, whichever
# plugins are installed, and each plugin adds its tab and its connection
# check here. Change all copies together (SHARED_VERSION).
module RedmineServerlessAdmin
  SHARED_VERSION = 1

  Tab = Struct.new(:name, :label, :url, :position, keyword_init: true)
  Check = Struct.new(:name, :label, :run, keyword_init: true)
  Result = Struct.new(:name, :label, :ok, :detail, :milliseconds, keyword_init: true)

  @tabs = {}
  @checks = {}

  class << self
    # url: a route hash; label: an i18n key; position: the order of the tabs.
    def register_tab(name, label:, url:, position:)
      @tabs[name.to_s] = Tab.new(name: name.to_s, label: label, url: url, position: position)
      add_menu_item
    end

    def tabs
      @tabs.values.sort_by(&:position)
    end

    # A light call that shows whether a service can be reached; the block
    # returns a short text, or raises.
    def register_check(name, label:, &run)
      @checks[name.to_s] = Check.new(name: name.to_s, label: label, run: run)
    end

    def checks
      @checks.values
    end

    # Whether the routes have the shared entry. Redmine draws plugin routes
    # from its plugin directory; when routes are drawn without it (some of
    # Redmine's own tests change the directory), the menu item is hidden
    # instead of breaking every administration page.
    def routed?
      Rails.application.routes.routes.any? { |route| route.defaults[:controller] == 'serverless_admin' }
    end

    def run_checks
      checks.map do |check|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok, detail = begin
          [true, check.run.call.to_s]
        rescue StandardError => e
          [false, "#{e.class}: #{e.message}"]
        end
        milliseconds = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Result.new(name: check.name, label: check.label, ok: ok, detail: detail, milliseconds: milliseconds)
      end
    end

    private

    def add_menu_item
      Redmine::MenuManager.map(:admin_menu) do |menu|
        next if menu.exists?(:serverless)

        menu.push :serverless, { controller: 'serverless_admin', action: 'index' },
                  caption: :label_serverless_admin, icon: 'server-authentication',
                  html: { class: 'icon icon-server-authentication' },
                  if: ->(_project) { RedmineServerlessAdmin.routed? }
      end
    end
  end
end
