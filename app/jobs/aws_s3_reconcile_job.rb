# frozen_string_literal: true

# Reconciliation of the attachments with S3, started from the "Attachments
# in S3" tab (docs/admin.md). A failure is kept for the tab (the class of
# the error) and logged with its message, and the job still fails.
class AwsS3ReconcileJob < ApplicationJob
  def perform
    RedmineKit::Aws::S3::Reconciliation.run
  rescue StandardError => e
    Rails.logger.error("[redmine_kit_aws_s3] consistency check failed: #{e.class}: #{e.message}")
    RedmineKit::Aws::S3::Reconciliation.failed(e)
    raise
  end
end
