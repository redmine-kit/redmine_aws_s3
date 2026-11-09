# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessS3UploadTest < ActiveSupport::TestCase
  include RedmineServerlessS3::TestHelper

  fixtures :users, :attachments

  CONTENT = 'uploaded contents'

  def setup
    set_tmp_attachments_directory
    @user = User.find(2)
  end

  def upload
    RedmineServerlessS3::Upload.new(@user)
  end

  def presign(**)
    upload.presign(filename: 'report.txt', size: CONTENT.bytesize, sha256: sha256_base64(CONTENT),
                   content_type: 'text/plain', **)
  end

  def head_of(content, checksum: sha256_base64(content), type: 'FULL_OBJECT')
    { content_length: content.bytesize, checksum_sha256: checksum, checksum_type: type }
  end

  def test_presign_returns_a_signed_put_url_for_incoming
    with_s3(stub_client) do |client|
      result = presign
      unsigned, expires = verify_signed_url(result[:url])

      assert_match %r{\Ahttps://#{DOMAIN}/tmp/incoming/[0-9a-f-]{36}\z}, unsigned
      assert_in_delta Time.now.to_i + 900, expires, 5
      assert_equal({ 'x-amz-checksum-sha256' => sha256_base64(CONTENT) }, result[:headers])
      assert result[:ticket].present?
      assert_empty client.api_requests
    end
  end

  def test_presign_checks_the_extension
    with_s3(stub_client) do
      with_settings attachment_extensions_denied: 'exe' do
        error = assert_raises(RedmineServerlessS3::Upload::Error) { presign(filename: 'tool.exe') }
        assert_includes error.message, '.exe'
      end
    end
  end

  def test_presign_checks_the_size
    with_s3(stub_client) do
      with_settings attachment_max_size: '1' do
        assert_raises(RedmineServerlessS3::Upload::Error) { presign(size: 1025) }
        assert presign(size: 1024)
      end
    end
  end

  def test_presign_checks_the_sha256
    with_s3(stub_client) do
      assert_raises(RedmineServerlessS3::Upload::Error) { presign(sha256: 'abc') }
      assert_raises(RedmineServerlessS3::Upload::Error) { presign(sha256: Digest::SHA256.hexdigest(CONTENT)) }
      assert_raises(RedmineServerlessS3::Upload::Error) { presign(size: '-1') }
      assert_raises(RedmineServerlessS3::Upload::Error) { presign(filename: '') }
    end
  end

  def test_complete_copies_the_upload_and_registers_the_attachment
    with_s3(stub_client(head_object: [head_of(CONTENT), 'NotFound'])) do |client|
      ticket = presign[:ticket]
      attachment = upload.complete(ticket)
      requests = client.api_requests.index_by { |request| request[:operation_name] }

      assert attachment.persisted?
      assert_equal Digest::SHA256.hexdigest(CONTENT), attachment.digest
      assert_equal CONTENT.bytesize, attachment.filesize
      assert_equal 'report.txt', attachment.filename
      assert_equal 'text/plain', attachment.content_type
      assert_equal @user, attachment.author
      assert_match %r{\A\d{4}/\d{2}\z}, attachment.disk_directory
      assert_match(/\A\d{12}_report\.txt\z/, attachment.disk_filename)
      assert_equal attachment.s3_key, requests[:copy_object][:params][:key]
      assert_match %r{\Aredmine-files/tmp/incoming/}, requests[:copy_object][:params][:copy_source]
      assert_match %r{\Atmp/incoming/}, requests[:delete_objects][:params][:delete][:objects].first[:key]
    end
  end

  def test_complete_shares_a_file_with_the_same_content
    existing = Attachment.find(1)
    content = 'shared'
    existing.update_columns(digest: Digest::SHA256.hexdigest(content), filesize: content.bytesize)
    with_s3(stub_client(head_object: head_of(content))) do |client|
      ticket = upload.presign(filename: 'copy.gif', size: content.bytesize, sha256: sha256_base64(content))[:ticket]
      attachment = upload.complete(ticket)

      assert_equal existing.disk_filename, attachment.disk_filename
      assert_equal existing.disk_directory, attachment.disk_directory
      assert_not_includes client.api_requests.pluck(:operation_name), :copy_object
    end
  end

  def test_a_checksum_that_does_not_match_deletes_the_upload
    with_s3(stub_client(head_object: head_of('other contents', type: 'FULL_OBJECT'))) do |client|
      ticket = presign[:ticket]

      assert_no_difference 'Attachment.count' do
        assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(ticket) }
      end
      deleted = client.api_requests.find { |request| request[:operation_name] == :delete_objects }

      assert_match %r{\Atmp/incoming/}, deleted[:params][:delete][:objects].first[:key]
    end
  end

  def test_a_size_that_does_not_match_deletes_the_upload
    head = head_of(CONTENT).merge(content_length: CONTENT.bytesize + 1)
    with_s3(stub_client(head_object: head)) do |client|
      assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(presign[:ticket]) }
      assert_includes client.api_requests.pluck(:operation_name), :delete_objects
    end
  end

  def test_an_object_without_a_full_object_checksum_is_refused
    with_s3(stub_client(head_object: head_of(CONTENT, type: 'COMPOSITE'))) do
      assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(presign[:ticket]) }
    end
    with_s3(stub_client(head_object: head_of(CONTENT).merge(checksum_sha256: nil))) do
      assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(presign[:ticket]) }
    end
  end

  def test_a_missing_upload_is_refused
    with_s3(stub_client(head_object: 'NotFound')) do
      error = assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(presign[:ticket]) }
      assert_includes error.message, 'not in S3'
    end
  end

  def test_the_ticket_belongs_to_its_user
    with_s3(stub_client(head_object: head_of(CONTENT))) do |client|
      ticket = presign[:ticket]

      assert_raises(RedmineServerlessS3::Upload::Error) { RedmineServerlessS3::Upload.new(User.find(3)).complete(ticket) }
      assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete("#{ticket}x") }
      assert_empty client.api_requests
    end
  end

  def test_the_ticket_expires
    with_s3(stub_client(head_object: head_of(CONTENT))) do
      ticket = presign[:ticket]
      travel 901.seconds do
        assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(ticket) }
      end
    end
  end

  def test_complete_waits_for_a_clean_scan
    tags = scan_tag('NO_THREATS_FOUND')
    with_s3(stub_client(get_object_tagging: tags, head_object: [head_of(CONTENT), 'NotFound'])) do |client|
      with_malware_scan do
        attachment = upload.complete(presign[:ticket])

        assert attachment.persisted?
        assert_equal %i[get_object_tagging head_object], client.api_requests.pluck(:operation_name).first(2)
      end
    end
  end

  def test_complete_while_the_scan_runs_is_pending
    with_s3(stub_client(get_object_tagging: scan_tag(nil))) do |client|
      with_malware_scan do
        ticket = presign[:ticket]

        assert_raises(RedmineServerlessS3::Upload::Pending) { upload.complete(ticket) }
        assert_equal [:get_object_tagging], client.api_requests.pluck(:operation_name)
      end
    end
  end

  def test_complete_refuses_a_threat
    with_s3(stub_client(get_object_tagging: scan_tag('THREATS_FOUND'))) do |client|
      with_malware_scan do
        assert_no_difference 'Attachment.count' do
          error = assert_raises(RedmineServerlessS3::Upload::Error) { upload.complete(presign[:ticket]) }
          assert_includes error.message, 'threat'
        end
        assert_includes client.api_requests.pluck(:operation_name), :delete_objects
        assert_not_includes client.api_requests.pluck(:operation_name), :head_object
      end
    end
  ensure
    Setting.plugin_redmine_serverless_s3 = {}
  end
end
