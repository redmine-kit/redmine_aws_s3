# frozen_string_literal: true

# The rows of the values that the "S3" tab shows, for redmine_aws's partial
# aws_admin/values (as Administration › Information shows values).
module AwsS3AdminHelper
  # The environment variables, each with the variable as its note.
  def aws_s3_environment_rows
    s3 = RedmineAws::S3
    [[:bucket, s3::ENV_BUCKET, s3.bucket], [:region, s3::ENV_REGION, s3.region],
     [:domain, s3::ENV_DOMAIN, s3.cloudfront_domain], [:key_pair_id, s3::ENV_KEY_PAIR_ID, s3.key_pair_id],
     [:private_key, s3::ENV_PRIVATE_KEY, l(s3.private_key? ? :label_aws_s3_set : :label_aws_s3_not_set)],
     [:malware_scan, s3::ENV_MALWARE_SCAN, l(s3.malware_scan? ? :label_aws_s3_enabled : :label_aws_s3_disabled)]]
      .map { |name, env, value| { name: l(:"field_aws_s3_#{name}"), value: value || '-', note: env } }
      .push(name: l(:field_aws_s3_storage_path), value: Attachment.storage_path, note: 'attachments_storage_path')
  end

  # The results of a connection test: [name, ok, detail].
  def aws_s3_check_rows(results)
    results.map { |name, ok, detail| { name: name, ok: ok, value: detail } }
  end

  # The last consistency check, running or finished.
  def aws_s3_reconciliation_rows(result)
    case RedmineAws::S3::Reconciliation.state(result)
    when :running then aws_s3_running_rows(result)
    when :failed then aws_s3_failed_rows(result)
    else aws_s3_finished_rows(result)
    end
  end

  def aws_s3_finished_rows(result)
    [{ name: l(:field_aws_s3_finished_at), value: format_time(Time.iso8601(result['finished_at'])) }] +
      %w[attachments objects missing_count unused_count].map { |key| aws_s3_count_row(result, key) }
  end

  # A count of the consistency check; the objects are those under files/.
  def aws_s3_count_row(result, key)
    { name: l(:"field_aws_s3_#{key.delete_suffix('_count')}"), value: number_with_delimiter(result[key]),
      note: ('files/' if key == 'objects') }
  end

  def aws_s3_running_rows(result)
    [{ name: l(:field_status), value: l(:label_aws_s3_running) }, aws_s3_started_row(result)]
  end

  # Stopped by an error (its class), or not finished in time ("Timed out").
  def aws_s3_failed_rows(result)
    [{ name: l(:field_status), value: l(:label_aws_failed) }, aws_s3_started_row(result),
     { name: l(:label_details), value: result['error'].presence || l(:label_aws_s3_timed_out) }]
  end

  def aws_s3_started_row(result)
    started = RedmineAws::S3::Reconciliation.started_at(result)
    { name: l(:field_aws_s3_started_at), value: started ? format_time(started) : '-' }
  end
end
