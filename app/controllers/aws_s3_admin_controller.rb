# frozen_string_literal: true

# The "S3" tab of the "AWS" administration page of redmine_aws
# (docs/admin.md). AWS is called only when a button is pressed.
class AwsS3AdminController < ApplicationController
  include RedmineAws::AdminTab

  helper :aws_s3_admin

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
    values = settings_params
    invalid = invalid_settings(values)
    return render_invalid_settings(values, invalid) if invalid.any?

    RedmineAws::S3.update_settings(values)
    log("changed the settings #{values.keys.join(', ')}")
    flash[:notice] = l(:notice_successful_update)
    redirect_to aws_s3_admin_path
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

  def settings_params
    params.fetch(:settings, {}).permit(*RedmineAws::S3::DEFAULT_SETTINGS.keys).to_h
  end

  # The names of the values that are not positive whole numbers.
  def invalid_settings(values)
    values.keys.reject { |name| values[name].to_s.match?(/\A[1-9][0-9]{0,6}\z/) }
  end

  def render_invalid_settings(values, invalid)
    names = invalid.map { |name| l(:"field_aws_s3_#{name}") }
    @errors = [l(:error_aws_s3_invalid_settings, names: names.join(', '))]
    show
    @settings.merge!(values)
    render :show, status: :unprocessable_content
  end

  def require_s3
    render_404 unless RedmineAws::S3.enabled?
  end

  def log(message)
    logger&.info("[redmine_aws_s3] #{User.current.login} #{message}")
  end
end
