# frozen_string_literal: true

# The "Serverless" item of the administration menu: opens the first tab of the
# installed Redmine Serverless plugins (lib/redmine_serverless_admin.rb).
# Shared by every plugin; keep the copies identical.
class ServerlessAdminController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :serverless

  before_action :require_admin

  def index
    tab = RedmineServerlessAdmin.tabs.first
    tab ? redirect_to(tab.url) : render_404
  end
end
