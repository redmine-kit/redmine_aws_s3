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

  class << self
    attr_writer :client

    # Called from init.rb, on every code reload.
    def setup
      Attachment.prepend(AttachmentPatch) unless Attachment < AttachmentPatch
      unless AttachmentsController < AttachmentsControllerPatch
        AttachmentsController.prepend(AttachmentsControllerPatch)
      end
      Import.prepend(ImportPatch) unless Import < ImportPatch
      SettingsController.prepend(SettingsControllerPatch) unless SettingsController < SettingsControllerPatch
      MailHandler.prepend(MailHandlerPatch) unless MailHandler < MailHandlerPatch
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
