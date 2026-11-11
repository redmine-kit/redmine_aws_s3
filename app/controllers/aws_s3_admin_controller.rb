# frozen_string_literal: true

# The "S3" tab of the "AWS" administration page of redmine_aws
# (docs/admin.md). AWS is called only when a button is pressed.
class AwsS3AdminController < ApplicationController
  include RedmineAws::AdminTab

  before_action :require_s3, except: %i[show update]

  def show
    @settings = RedmineAwsS3::DEFAULT_SETTINGS.keys.index_with { |name| RedmineAwsS3.setting(name) }
    @reconciliation = RedmineAwsS3::Reconciliation.result
  end

  def update
    values = params.fetch(:settings, {}).permit(*RedmineAwsS3::DEFAULT_SETTINGS.keys).to_h
    invalid = values.reject { |_, value| value.to_s.match?(/\A[1-9][0-9]{0,6}\z/) }
    if invalid.any?
      names = invalid.keys.map { |name| l(:"field_aws_s3_#{name}") }
      flash[:error] = l(:error_aws_s3_invalid_settings, names: names.join(', '))
    else
      RedmineAwsS3.update_settings(values)
      log("changed the settings #{values.to_json}")
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to aws_s3_admin_path
  end

  def read_write
    log('ran the read/write check')
    flash[:aws_s3_checks] = RedmineAwsS3::Checks.read_write
    redirect_to aws_s3_admin_path
  end

  def delivery
    log('ran the delivery check')
    flash[:aws_s3_checks] = RedmineAwsS3::Checks.delivery
    redirect_to aws_s3_admin_path
  end

  def reconcile
    log('started the reconciliation')
    RedmineAwsS3::Reconciliation.started
    AwsS3ReconcileJob.perform_later
    flash[:notice] = l(:notice_aws_s3_reconciliation_started)
    redirect_to aws_s3_admin_path
  end

  private

  def require_s3
    render_404 unless RedmineAwsS3.enabled?
  end

  def log(message)
    logger&.info("[redmine_aws_s3] #{User.current.login} #{message}")
  end
end
