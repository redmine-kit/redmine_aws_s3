# frozen_string_literal: true

# POST /s3_uploads/presign and /s3_uploads/complete (docs/attachments.md#upload):
# the same permission as Redmine's POST /uploads, and the same response as
# it on completion.
class S3UploadsController < ApplicationController
  before_action :require_s3
  before_action :authorize_upload

  accept_api_auth :presign, :complete

  def presign
    result = RedmineAws::S3::Upload.new(User.current).presign(**RedmineAws::S3::PresignParams.from(params))
    render json: result
  rescue RedmineAws::S3::Upload::Error => e
    render json: { errors: [e.message] }, status: :unprocessable_content
  end

  def complete
    @attachment = RedmineAws::S3::Upload.new(User.current).complete(params[:ticket])
    respond_to do |format|
      format.js { render template: 'attachments/upload' }
      format.api { render_attachment }
    end
  rescue RedmineAws::S3::Upload::Pending => e
    scanning(e.message)
  rescue RedmineAws::S3::Upload::Error => e
    upload_error(e.message)
  end

  private

  # As Redmine's POST /uploads answers the API.
  def render_attachment
    if @attachment.persisted?
      render template: 'attachments/upload', status: :created
    else
      render_validation_errors(@attachment)
    end
  end

  def upload_error(message)
    respond_to do |format|
      format.js do
        render json: { errors: [message] }, status: :unprocessable_content, content_type: 'application/json'
      end
      format.api { render_api_errors(message) }
    end
  end

  # 202: the malware scan has not finished; the same request can be sent again.
  def scanning(message)
    response.headers['Retry-After'] = '2'
    respond_to do |format|
      format.js do
        render json: { status: 'scanning', message: message }, status: :accepted, content_type: 'application/json'
      end
      format.api { head :accepted }
    end
  end

  def require_s3
    render_404 unless RedmineAws::S3.enabled?
  end

  def authorize_upload
    authorize_global('attachments', 'upload')
  end
end
