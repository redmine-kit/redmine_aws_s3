# frozen_string_literal: true

module RedmineServerlessS3
  # Prepended to SettingsController: "Configure" in the plugin list opens the
  # "Attachments in S3" tab, where the settings are changed.
  module SettingsControllerPatch
    def plugin
      return super unless params[:id] == 'redmine_serverless_s3' && request.get?

      flash.keep
      redirect_to serverless_s3_admin_path
    end
  end
end
