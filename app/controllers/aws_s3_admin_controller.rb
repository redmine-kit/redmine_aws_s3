# frozen_string_literal: true

# The "S3" tab of the "AWS" administration page of redmine_aws
# (docs/admin.md). AWS is called only when a button is pressed.
class AwsS3AdminController < ApplicationController
  include RedmineAws::AdminTab

  before_action :require_s3, except: %i[show update]

  def show
    @settings = RedmineAws::S3::DEFAULT_SETTINGS.keys.index_with { |name| RedmineAws::S3.setting(name) }
    @reconciliation = RedmineAws::S3::Reconciliation.result
    @findings = RedmineAws::S3::MalwareScan.findings
    # The users of the findings by login, in one query.
    @finding_users = User.where(login: @findings.filter_map { |finding| finding['user'].presence }).index_by(&:login)
  end

  # Invalid values are shown again in the form, with the error at the top
  # of the tab, as the tabs of Redmine's project settings show theirs.
  def update
    values = params.fetch(:settings, {}).permit(*RedmineAws::S3::DEFAULT_SETTINGS.keys).to_h
    invalid = values.reject { |_, value| value.to_s.match?(/\A[1-9][0-9]{0,6}\z/) }
    if invalid.any?
      names = invalid.keys.map { |name| l(:"field_aws_s3_#{name}") }
      @errors = [l(:error_aws_s3_invalid_settings, names: names.join(', '))]
      show
      @settings.merge!(values)
      render :show, status: :unprocessable_content
    else
      RedmineAws::S3.update_settings(values)
      log("changed the settings #{values.keys.join(', ')}")
      flash[:notice] = l(:notice_successful_update)
      redirect_to aws_s3_admin_path
    end
  end

  def read_write
    log('ran the read/write check')
    flash[:aws_s3_checks] = RedmineAws::S3::Checks.read_write
    redirect_to aws_s3_admin_path
  end

  def delivery
    log('ran the delivery check')
    flash[:aws_s3_checks] = RedmineAws::S3::Checks.delivery
    redirect_to aws_s3_admin_path
  end

  def reconcile
    log('started the reconciliation')
    RedmineAws::S3::Reconciliation.started
    AwsS3ReconcileJob.perform_later
    flash[:notice] = l(:notice_aws_s3_reconciliation_started)
    redirect_to aws_s3_admin_path
  end

  private

  def require_s3
    render_404 unless RedmineAws::S3.enabled?
  end

  def log(message)
    logger&.info("[redmine_aws_s3] #{User.current.login} #{message}")
  end
end
