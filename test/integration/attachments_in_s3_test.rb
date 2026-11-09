# frozen_string_literal: true

require_relative '../test_helper'

# Attachments in S3 reproduced by moto (S3_TEST_ENDPOINT). moto 5.2.5 neither
# checks x-amz-checksum-sha256 nor returns ChecksumSHA256 from HeadObject, so
# the upload tests compute that HeadObject result from the stored bytes, as S3
# does; a checksum that does not match is tested with stub_responses
# (test/unit/upload_test.rb).
class RedmineServerlessS3AttachmentsInS3Test < Redmine::IntegrationTest
  include RedmineServerlessS3::TestHelper

  fixtures :users, :email_addresses, :projects, :roles, :members, :member_roles, :enabled_modules, :issues,
           :trackers, :projects_trackers, :issue_statuses, :enumerations, :workflows, :attachments,
           :custom_fields, :custom_values, :custom_fields_projects, :custom_fields_trackers

  def setup
    set_tmp_attachments_directory
    Attachment.clear_thumbnails
  end

  def object(key)
    RedmineServerlessS3.client.get_object(bucket: RedmineServerlessS3.bucket, key: key).body.read
  rescue Aws::S3::Errors::NoSuchKey
    nil
  end

  def keys(prefix = '')
    RedmineServerlessS3.storage.keys(prefix)
  end

  # HeadObject as S3 answers it for an object uploaded with a SHA256 checksum.
  def emulate_s3_checksums
    RedmineServerlessS3::Storage.class_eval do
      alias_method :head_without_checksum, :head
      define_method(:head) do |key, checksum: false|
        result = head_without_checksum(key)
        return result unless result && checksum

        data = client.get_object(bucket: bucket, key: key).body.read
        Struct.new(:content_length, :checksum_sha256, :checksum_type)
              .new(result.content_length, Digest::SHA256.base64digest(data), 'FULL_OBJECT')
      end
    end
    yield
  ensure
    RedmineServerlessS3::Storage.class_eval do
      alias_method :head, :head_without_checksum
      remove_method :head_without_checksum
    end
  end

  # The browser's PUT, sent to S3 as CloudFront does through OAC.
  def put_upload(url, headers, data)
    key = URI(url).path.delete_prefix('/')
    RedmineServerlessS3.client.put_object(bucket: RedmineServerlessS3.bucket, key: key, body: data,
                                          checksum_sha256: headers['x-amz-checksum-sha256'])
    key
  end

  def upload_through_cloudfront(data, filename)
    post '/s3_uploads/presign', params: { filename: filename, size: data.bytesize,
                                          sha256: sha256_base64(data), content_type: 'text/plain' }
    assert_response :success
    presigned = response.parsed_body
    key = put_upload(presigned['url'], presigned['headers'], data)
    post '/s3_uploads/complete.js', params: { ticket: presigned['ticket'], attachment_id: 1 }, xhr: true
    assert_response :success
    [key, response.body[/val\('([^']+)'\)/, 1]]
  end

  def test_the_upload_flow_through_cloudfront
    with_moto do
      log_user('jsmith', 'jsmith')
      data = "contents uploaded by the browser\n"
      incoming, token = emulate_s3_checksums { upload_through_cloudfront(data, 'browser.txt') }

      assert token.present?
      assert_nil object(incoming), 'the upload is deleted from incoming/'
      post '/projects/ecookbook/issues', params: {
        issue: { tracker_id: 1, subject: 'With an upload' },
        attachments: { '1' => { token: token } }
      }
      attachment = Issue.last.attachments.first

      assert_equal 'browser.txt', attachment.filename
      assert_equal Digest::SHA256.hexdigest(data), attachment.digest
      assert_equal data, object(attachment.s3_key)
      assert_not File.exist?(attachment.local_diskfile), 'the file did not pass through Redmine'

      get "/attachments/download/#{attachment.id}/browser.txt"
      assert_response :redirect
      unsigned, = verify_signed_url(response.location)
      assert_equal "/#{attachment.s3_key}", URI(unsigned).path

      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_include 'contents uploaded by the browser', response.body
      assert File.exist?(attachment.local_diskfile), 'the text view reads the /tmp cache'
    end
  end

  def test_identical_uploads_share_one_object
    with_moto do
      log_user('jsmith', 'jsmith')
      data = 'same bytes'
      _, first = emulate_s3_checksums { upload_through_cloudfront(data, 'one.txt') }
      _, second = emulate_s3_checksums { upload_through_cloudfront(data, 'two.txt') }
      a1 = Attachment.find_by_token(first)
      a2 = Attachment.find_by_token(second)

      assert_equal a1.s3_key, a2.s3_key
      assert_equal [a1.s3_key], keys('files/')
    end
  end

  def test_uploads_through_lambda_and_deletion
    with_moto do
      with_settings rest_api_enabled: '1' do
        post '/uploads.json?filename=api.txt', params: 'through the REST API',
                                               headers: { 'CONTENT_TYPE' => 'application/octet-stream' }
                                                 .merge(credentials('jsmith'))
        assert_response :created
      end
      attachment = Attachment.last

      assert_equal 'through the REST API', object(attachment.s3_key)
      FileUtils.rm_f(attachment.local_diskfile)
      assert attachment.readable?
      assert_equal 'through the REST API', File.read(attachment.reload.diskfile)

      attachment.destroy
      assert_empty keys('files/')
      assert_not File.exist?(attachment.local_diskfile)
    end
  end

  def test_thumbnails_are_stored_and_deleted_with_the_image
    skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

    with_moto do
      attachment = Attachment.create!(container: Issue.find(1), author: User.find(1),
                                      file: uploaded_test_file('2010/11/101123161450_testfile_1.png', 'image/png'))
      FileUtils.rm_f(attachment.local_diskfile)
      log_user('admin', 'admin')
      get "/attachments/thumbnail/#{attachment.id}/100"

      assert_response :redirect
      key = "thumbnails/#{attachment.digest}_#{attachment.filesize}_100.thumb"
      assert_equal "/#{key}", URI(verify_signed_url(response.location).first).path
      assert object(key).b.start_with?("\x89PNG".b)

      attachment.destroy
      assert_empty keys('thumbnails/')
    end
  end

  def test_download_all_stores_a_zip
    with_moto do
      issue = Issue.find(1)
      a1 = Attachment.create!(container: issue, author: User.find(1), file: mock_file(filename: 'a.txt', content: 'A'))
      Attachment.create!(container: issue, author: User.find(1), file: mock_file(filename: 'a.txt', content: 'B'))
      FileUtils.rm_f(a1.local_diskfile)
      log_user('admin', 'admin')
      get "/attachments/issues/#{issue.id}/download"

      assert_response :redirect
      key = URI(verify_signed_url(response.location).first).path.delete_prefix('/')
      assert key.start_with?('tmp/bulk/')
      names = {}
      Zip::InputStream.open(StringIO.new(object(key))) do |zip|
        while (entry = zip.get_next_entry)
          names[entry.name] = zip.read
        end
      end
      assert_equal 'A', names['a.txt']
      assert_equal 'B', names['a(1).txt']

      get "/attachments/issues/#{issue.id}/download"
      assert_equal 1, keys('tmp/bulk/').size, 'the same zip is reused'
    end
  end

  def test_csv_import_continues_in_another_environment
    with_moto do
      log_user('jsmith', 'jsmith')
      post '/imports', params: { type: 'IssueImport', file: uploaded_test_file('import_issues.csv', 'text/csv') }
      import = Import.last

      assert_equal ["imports/#{import.filename}"], keys('imports/')
      FileUtils.rm_f(import.filepath)
      post "/imports/#{import.to_param}/settings",
           params: { import_settings: { separator: ';', wrapper: '"', encoding: 'UTF-8' } }

      assert_redirected_to "/imports/#{import.to_param}/mapping"
      assert File.exist?(import.filepath)
      assert import.reload.total_items.positive?
    end
  end

  def test_reconciliation
    with_moto do
      kept = Attachment.create!(container: Issue.find(1), author: User.find(1),
                                file: mock_file(filename: 'kept.txt', content: 'kept'))
      RedmineServerlessS3.client.put_object(bucket: RedmineServerlessS3.bucket, key: 'files/2020/01/orphan', body: 'x')
      ServerlessS3ReconcileJob.perform_now
      result = RedmineServerlessS3::Reconciliation.result

      assert_includes result['unused'], 'files/2020/01/orphan'
      assert_not_includes result['missing'], kept.s3_key
      assert_includes result['missing'], Attachment.find(1).s3_key
      assert result['finished_at'].present?
    ensure
      Setting.plugin_redmine_serverless_s3 = {}
    end
  end

  def test_read_write_check
    with_moto do
      assert(RedmineServerlessS3::Checks.read_write.all? { |_, ok, _| ok })
      assert_empty keys('tmp/')
      assert_equal RedmineServerlessS3.bucket, RedmineServerlessS3::Checks.head_bucket
    end
  end
end
