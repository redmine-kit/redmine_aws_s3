# frozen_string_literal: true

# The "S3" tab of the "AWS" administration page of redmine_kit_aws
# (docs/admin.md). AWS is called only when a button is pressed. Redmine's
# page (HTML, with redirects and flash messages), and the same data and
# actions as JSON for the new UI's tab (AwsS3Admin of frontend/;
# AwsS3AdminHelper#aws_s3_admin_json).
class AwsS3AdminController < ApplicationController
  include RedmineKit::Aws::AdminTab

  helper :aws_s3_admin

  before_action :require_s3, except: %i[show update]

  def show
    load_tab
    respond_to do |format|
      format.html
      format.json { render json: view_context.aws_s3_admin_json }
    end
  end

  # Invalid values are shown again in the form, with the error at the top
  # of the tab, as the tabs of Redmine's project settings show theirs.
  def update
    values = settings_params
    errors = settings_errors(values)
    return render_invalid_settings(values, errors) if errors.any?

    RedmineKit::Aws::S3.update_settings(values)
    log("changed the settings #{values.keys.join(', ')}")
    done(l(:notice_successful_update))
  end

  def read_write
    log('ran the read/write check')
    checked(RedmineKit::Aws::S3::Checks.read_write)
  end

  def delivery
    log('ran the delivery check')
    checked(RedmineKit::Aws::S3::Checks.delivery)
  end

  def reconcile
    log('started the reconciliation')
    RedmineKit::Aws::S3::Reconciliation.started
    AwsS3ReconcileJob.perform_later
    done(l(:notice_aws_s3_reconciliation_started))
  end

  private

  # What the tab shows.
  def load_tab
    @settings = RedmineKit::Aws::S3::DEFAULT_SETTINGS.keys.index_with { |name| RedmineKit::Aws::S3.setting(name) }
    @reconciliation = RedmineKit::Aws::S3::Reconciliation.result
    @findings = RedmineKit::Aws::S3::MalwareScan.findings
    # The users of the findings by login, in one query.
    @finding_users = User.where(login: @findings.filter_map { |finding| finding['user'].presence }).index_by(&:login)
  end

  # Back to the tab with the notice, or the notice as JSON.
  def done(notice)
    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to aws_s3_admin_path
      end
      format.json { render json: { notice: notice, errors: [] } }
    end
  end

  # A connection test's results: shown once on the tab after the redirect,
  # or as JSON, the same rows (AwsS3AdminHelper#aws_s3_check_rows).
  def checked(results)
    respond_to do |format|
      format.html do
        flash[:aws_s3_checks] = results
        redirect_to aws_s3_admin_path
      end
      format.json { render json: { results: view_context.aws_s3_check_rows(results) } }
    end
  end

  # The plugin's settings, each a single value; a parameter of another shape
  # (a string, an array) is ignored.
  def settings_params
    values = params[:settings]
    values.is_a?(ActionController::Parameters) ? values.permit(*RedmineKit::Aws::S3::DEFAULT_SETTINGS.keys).to_h : {}
  end

  # The names of the values that are not positive whole numbers.
  def invalid_settings(values)
    values.keys.reject { |name| values[name].to_s.match?(/\A[1-9][0-9]{0,6}\z/) }
  end

  # The values that are not positive whole numbers in one message, then
  # each one over its maximum, as Redmine's validations say it.
  def settings_errors(values)
    invalid = invalid_settings(values)
    errors = invalid.any? ? [l(:error_aws_s3_invalid_settings, names: setting_names(invalid))] : []
    errors + (values.keys - invalid).filter_map { |name| over_maximum(name, values[name].to_i) }
  end

  def setting_names(names)
    names.map { |name| l(:"field_aws_s3_#{name}") }.join(', ')
  end

  def over_maximum(name, value)
    max = RedmineKit::Aws::S3::SettingLimits::MAXIMA.fetch(name)
    return if value <= max

    ::I18n.t('errors.format', attribute: l(:"field_aws_s3_#{name}"),
                              message: ::I18n.t('activerecord.errors.messages.less_than_or_equal_to', count: max))
  end

  def render_invalid_settings(values, errors)
    respond_to do |format|
      format.html do
        @errors = errors
        load_tab
        @settings.merge!(values)
        render :show, status: :unprocessable_content
      end
      format.json { render json: { errors: errors }, status: :unprocessable_content }
    end
  end

  def require_s3
    render_404 unless RedmineKit::Aws::S3.enabled?
  end

  def log(message)
    logger&.info("[redmine_kit_aws_s3] #{User.current.login} #{message}")
  end
end
