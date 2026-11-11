# frozen_string_literal: true

# Reconciliation of the attachments with S3, started from the "Attachments
# in S3" tab (docs/admin.md).
class AwsS3ReconcileJob < ApplicationJob
  def perform
    RedmineAwsS3::Reconciliation.run
  end
end
