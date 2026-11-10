# frozen_string_literal: true

# Redmine Serverless S3: attachments in Amazon S3, uploaded and downloaded
# through Redmine's CloudFront distribution (docs/attachments.md).
#
# The plugin is on only when REDMINE_S3_BUCKET is set; otherwise every
# replaced method calls Redmine's own code.
module RedmineServerlessS3
  # Environment variables (docs/setup.md#configuration).
  ENV_BUCKET = 'REDMINE_S3_BUCKET'
  ENV_REGION = 'REDMINE_S3_REGION'
  ENV_DOMAIN = 'REDMINE_CLOUDFRONT_DOMAIN'
  ENV_KEY_PAIR_ID = 'REDMINE_CLOUDFRONT_KEY_PAIR_ID'
  ENV_PRIVATE_KEY = 'REDMINE_CLOUDFRONT_PRIVATE_KEY'
  ENV_MALWARE_SCAN = 'REDMINE_S3_MALWARE_SCAN'

  # Defaults of the plugin settings.
  DEFAULT_SETTINGS = {
    'download_url_expiry' => '300',
    'upload_url_expiry' => '900',
    'cache_size_mb' => '256'
  }.freeze

  # The value Redmine's AttachmentsController sets on attachments.
  ATTACHMENT_CSP = "default-src 'none'; style-src 'unsafe-inline'; sandbox"

  # Everything but the attachments' files is under tmp/, as on Redmine's own
  # disk (tmp/thumbnails), so that one CloudFront cache behavior (/tmp/*)
  # serves thumbnails and the zips of "download all" and takes uploads.
  # Uploads and zips expire; thumbnails stay until their attachment is
  # deleted (docs/setup.md#the-bucket).
  THUMBNAILS_PREFIX = 'tmp/thumbnails/'
  # Redmine's cache of Markdown previews, under attachments_storage_path
  # (Attachment.markdownized_previews_storage_path), so under files/.
  PREVIEWS_PREFIX = 'files/derived_cache/markdownized_previews/'
  BULK_PREFIX = 'tmp/bulk/'
  INCOMING_PREFIX = 'tmp/incoming/'

  class << self
    attr_writer :client

    # Called from init.rb, on every code reload.
    def setup
      { Attachment => AttachmentPatch, AttachmentsController => AttachmentsControllerPatch, Import => ImportPatch,
        SettingsController => SettingsControllerPatch, MailHandler => MailHandlerPatch }.each do |target, patch|
        target.prepend(patch) unless target < patch
      end
      # Avatars of Redmine 7.1 (docs/attachments.md#avatars).
      AvatarsController.prepend(AvatarsControllerPatch) if avatars? && !(AvatarsController < AvatarsControllerPatch)
      # Loaded here so that the listener registers itself in every environment.
      Hooks.name
      RedmineServerlessAdmin.register_tab(:s3, label: :label_redmine_serverless_s3_admin,
                                               url: { controller: 'serverless_s3_admin', action: 'show' },
                                               position: 50)
      return unless enabled?

      RedmineServerlessAdmin.register_check(:s3, label: :label_redmine_serverless_s3_check) do
        Checks.head_bucket
      end
    end

    def enabled?
      bucket.present?
    end

    # The S3 key of a thumbnail at path under Redmine's tmp/thumbnails.
    def thumbnail_key(path)
      "#{THUMBNAILS_PREFIX}#{File.basename(path)}"
    end

    # Whether Redmine detects the type of an attachment from its contents and
    # ignores the declared one (Redmine 7.1, Attachment#set_content_type).
    def detects_content_type? = ::Attachment.method_defined?(:set_content_type)

    # Whether Redmine sends PDF compatible files inline only when asked
    # (Redmine 7.1, Attachment#pdf_previewable? and ?disposition=inline).
    def pdf_previewable? = ::Attachment.method_defined?(:pdf_previewable?)

    # Whether Redmine makes cropped thumbnails (Redmine 7.1, for avatars).
    def thumbnail_crop?
      Redmine::Thumbnail.method(:generate).parameters.include?(%i[key crop])
    end

    # Whether Redmine has avatars uploaded to Redmine (7.1); 7.0 has
    # Gravatar only.
    def avatars?
      defined?(::AvatarsController) && ::User.method_defined?(:update_avatar)
    end

    def bucket
      ENV.fetch(ENV_BUCKET, nil).presence
    end

    def region
      ENV[ENV_REGION].presence || ENV['AWS_REGION'].presence || ENV.fetch('AWS_DEFAULT_REGION', nil).presence
    end

    # Whether objects wait for GuardDuty's scan before use.
    def malware_scan?
      ENV.fetch(ENV_MALWARE_SCAN, '').strip.casecmp?('true')
    end

    def cloudfront_domain
      ENV.fetch(ENV_DOMAIN, nil).presence
    end

    def key_pair_id
      ENV.fetch(ENV_KEY_PAIR_ID, nil).presence
    end

    # Whether the private key is set; it is never shown.
    def private_key?
      ENV.fetch(ENV_PRIVATE_KEY, nil).present?
    end

    # The S3 client. Tests replace it (stub_responses or moto).
    def client
      @client ||= Aws::S3::Client.new(region: region)
    end

    def storage
      Storage.new(client, bucket)
    end

    def url_signer
      UrlSigner.new(domain: cloudfront_domain, key_pair_id: key_pair_id,
                    private_key: ENV.fetch(ENV_PRIVATE_KEY, nil))
    end

    def setting(name)
      settings = Setting.plugin_redmine_serverless_s3 if Setting.respond_to?(:plugin_redmine_serverless_s3)
      (settings.is_a?(Hash) && settings[name].presence) || DEFAULT_SETTINGS.fetch(name)
    end

    # Merges values into the plugin settings, keeping the other keys (such
    # as the reconciliation result).
    def update_settings(values)
      settings = Setting.plugin_redmine_serverless_s3
      settings = settings.is_a?(Hash) ? settings.to_h.stringify_keys : {}
      Setting.plugin_redmine_serverless_s3 = settings.merge(values.to_h.stringify_keys)
    end

    def download_url_expiry
      setting('download_url_expiry').to_i.clamp(1, 7.days.to_i)
    end

    def upload_url_expiry
      setting('upload_url_expiry').to_i.clamp(1, 7.days.to_i)
    end

    def cache_size
      setting('cache_size_mb').to_i.clamp(1, 10_240).megabytes
    end

    # S3 key of an attachment's file, the same form as its path under
    # attachments_storage_path.
    def file_key(disk_directory, disk_filename)
      ['files', disk_directory.presence, disk_filename].compact.join('/')
    end
  end
end
