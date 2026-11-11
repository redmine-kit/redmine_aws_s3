# frozen_string_literal: true

module RedmineAwsS3
  # Prepended to SettingsController: "Configure" in the plugin list opens the
  # "S3" tab, where the settings are changed.
  module SettingsControllerPatch
    def plugin
      return super unless params[:id] == 'redmine_aws_s3' && request.get?

      flash.keep
      redirect_to aws_s3_admin_path
    end
  end
end
