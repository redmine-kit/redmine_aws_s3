# frozen_string_literal: true

module RedmineServerlessS3
  # Prepended to AttachmentsController (docs/attachments.md#download). After
  # Redmine's own checks, downloads and thumbnails redirect to CloudFront
  # signed URLs, and "download all" stores the zip in S3 first.
  module AttachmentsControllerPatch
    def download
      return super unless RedmineServerlessS3.enabled?

      @attachment.increment_download if @attachment.container.is_a?(Version) || @attachment.container.is_a?(Project)
      redirect_to_signed_url(@attachment.s3_key, @attachment.filename, detect_content_type(@attachment),
                             disposition(@attachment))
    end

    def thumbnail
      return super unless RedmineServerlessS3.enabled?

      key = @attachment.s3_thumbnail(size: params[:size])
      unless key
        head :not_found
        return
      end
      expires_in RedmineServerlessS3.download_url_expiry.seconds
      redirect_to_signed_url(key, @attachment.filename, detect_content_type(@attachment, true), 'attachment')
    end

    def download_all
      return super unless RedmineServerlessS3.enabled?

      file_name = "#{@container.class.to_s.downcase}-#{@container.id}-attachments.zip"
      key = RedmineServerlessS3::BulkDownload.new(@attachments).store
      if key
        redirect_to_signed_url(key, file_name, Redmine::MimeType.of(file_name), 'attachment')
      else
        render_404
      end
    end

    private

    def redirect_to_signed_url(key, filename, content_type, disposition)
      url = RedmineServerlessS3.url_signer.url_for(
        key,
        { 'response-content-disposition' =>
            ActionDispatch::Http::ContentDisposition.format(disposition: disposition, filename: filename),
          'response-content-type' => content_type },
        expires_in: RedmineServerlessS3.download_url_expiry
      )
      redirect_to url, allow_other_host: true
    end
  end
end
