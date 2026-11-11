# frozen_string_literal: true

module RedmineAwsS3
  # Prepended to AvatarsController of Redmine 7.1 (docs/attachments.md#avatars).
  # The browser sends the image to S3 through CloudFront and submits Redmine's
  # form with the ticket of the upload instead of the file; Redmine's own
  # update registers it as it registers a file sent in the form. Avatars are
  # shown by Redmine's own show, with the thumbnails kept in S3
  # (AttachmentPatch#thumbnail).
  module AvatarsControllerPatch
    def update
      ticket = params[:s3_ticket].presence if RedmineAwsS3.enabled? && params[:avatar].blank?
      return update_with_errors { super } unless ticket

      RedmineAwsS3::AvatarUpload.new(User.current).open(ticket) do |file|
        params[:avatar] = file
        # Scanned in tmp/incoming/ already; not again when Redmine saves it.
        RedmineAwsS3::MalwareScan.skip { update_with_errors { super } }
      end
    rescue RedmineAwsS3::Upload::Error => e
      @user.errors.add(:base, e.message)
      render :edit, status: :unprocessable_content
    end

    private

    # User#update_avatar saves the attachment with save!, so a file the
    # malware scan refuses (a file sent in the form, through Lambda) is shown
    # as an error of the form instead of a server error.
    def update_with_errors
      yield
    rescue ActiveRecord::RecordNotSaved => e
      raise unless RedmineAwsS3.enabled? && e.record.is_a?(Attachment) && e.record.errors.any?

      e.record.errors.full_messages.each { |message| @user.errors.add(:base, message) }
      render :edit, status: :unprocessable_content
    end
  end
end
