# frozen_string_literal: true

# POST /s3_uploads/avatar/presign and /s3_uploads/avatar/check
# (docs/attachments.md#avatars): the upload of an avatar (Redmine 7.1)
# through CloudFront. Any logged-in user can change their own avatar in
# Redmine, so these need a login, not the upload permission of attachments.
# The avatar is registered by Redmine's own form (AvatarsController#update)
# with the ticket, where Redmine checks who may change which avatar.
class S3AvatarUploadsController < ApplicationController
  before_action :require_avatars
  before_action :require_login

  def presign
    result = RedmineAwsS3::AvatarUpload.new(User.current).presign(
      filename: params[:filename], size: params[:size], content_type: params[:content_type]
    )
    render json: result
  rescue RedmineAwsS3::Upload::Error => e
    render json: { errors: [e.message] }, status: :unprocessable_content
  end

  # 200 when the upload can be registered; 202 while the malware scan runs.
  def check
    RedmineAwsS3::AvatarUpload.new(User.current).check!(params[:ticket])
    render json: { status: 'ok' }
  rescue RedmineAwsS3::Upload::Pending => e
    response.headers['Retry-After'] = '2'
    render json: { status: 'scanning', message: e.message }, status: :accepted
  rescue RedmineAwsS3::Upload::Error => e
    render json: { errors: [e.message] }, status: :unprocessable_content
  end

  private

  def require_avatars
    render_404 unless RedmineAwsS3.enabled? && RedmineAwsS3.avatars? && User.avatar_available?
  end
end
