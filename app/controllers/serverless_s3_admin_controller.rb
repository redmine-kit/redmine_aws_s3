# frozen_string_literal: true

# The "Attachments in S3" tab of the shared "Serverless" administration page
# (docs/admin.md). AWS is called only when a button is pressed.
class ServerlessS3AdminController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :serverless

  before_action :require_admin
  before_action :require_s3, except: %i[show update]

  def show
    @settings = RedmineServerlessS3::DEFAULT_SETTINGS.keys.index_with { |name| RedmineServerlessS3.setting(name) }
    @reconciliation = RedmineServerlessS3::Reconciliation.result
  end

  def update
    values = params.fetch(:settings, {}).permit(*RedmineServerlessS3::DEFAULT_SETTINGS.keys).to_h
    invalid = values.reject { |_, value| value.to_s.match?(/\A[1-9][0-9]{0,6}\z/) }
    if invalid.any?
      flash[:error] = l(:error_redmine_serverless_s3_invalid_settings, names: invalid.keys.join(', '))
    else
      RedmineServerlessS3.update_settings(values)
      log("changed the settings #{values.to_json}")
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to serverless_s3_admin_path
  end

  def read_write
    log('ran the read/write check')
    flash[:serverless_s3_checks] = RedmineServerlessS3::Checks.read_write
    redirect_to serverless_s3_admin_path
  end

  def delivery
    log('ran the delivery check')
    flash[:serverless_s3_checks] = RedmineServerlessS3::Checks.delivery
    redirect_to serverless_s3_admin_path
  end

  def reconcile
    log('started the reconciliation')
    RedmineServerlessS3::Reconciliation.started
    ServerlessS3ReconcileJob.perform_later
    flash[:notice] = l(:notice_redmine_serverless_s3_reconciliation_started)
    redirect_to serverless_s3_admin_path
  end

  private

  def require_s3
    render_404 unless RedmineServerlessS3.enabled?
  end

  def log(message)
    logger&.info("[redmine_serverless_s3] #{User.current.login} #{message}")
  end
end
