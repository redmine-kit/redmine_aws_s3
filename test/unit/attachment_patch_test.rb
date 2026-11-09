# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessS3AttachmentPatchTest < ActiveSupport::TestCase
  include RedmineServerlessS3::TestHelper

  fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

  def setup
    set_tmp_attachments_directory
    User.current = nil
  end

  def operations(client)
    client.api_requests.map { |request| request[:operation_name] }
  end

  def test_off_without_the_bucket
    client = stub_client
    RedmineServerlessS3.client = client
    a = Attachment.create!(container: Issue.find(1), author: User.find(1),
                           file: mock_file(filename: 'off.txt', content: 'off'))

    assert_not RedmineServerlessS3.enabled?
    assert File.exist?(a.diskfile)
    assert a.readable?
    a.destroy
    assert_empty client.api_requests
  ensure
    RedmineServerlessS3.client = nil
  end

  def test_files_to_final_location_puts_the_file
    with_s3(stub_client) do |client|
      a = Attachment.create!(container: Issue.find(1), author: User.find(1),
                             file: mock_file(filename: 'put.txt', content: 'put'))
      put = client.api_requests.find { |request| request[:operation_name] == :put_object }

      assert_equal a.s3_key, put[:params][:key]
      assert_match %r{\Afiles/\d{4}/\d{2}/\d{12}_put\.txt\z}, a.s3_key
      assert_equal 'redmine-files', put[:params][:bucket]
    end
  end

  def test_a_failed_put_stops_the_save
    with_s3(stub_client(put_object: 'AccessDenied')) do
      a = Attachment.new(container: Issue.find(1), author: User.find(1),
                         file: mock_file(filename: 'denied.txt', content: 'x'))

      assert_raises(Aws::S3::Errors::AccessDenied) { a.save }
      assert_not Attachment.exists?(filename: 'denied.txt')
    end
  end

  def test_uploads_through_lambda_wait_for_the_malware_scan
    with_s3(stub_client(get_object_tagging: scan_tag('NO_THREATS_FOUND'))) do |client|
      with_malware_scan do
        a = Attachment.create!(container: Issue.find(1), author: User.find(1),
                               file: mock_file(filename: 'scanned.txt', content: 'scanned'))
        requests = client.api_requests.index_by { |request| request[:operation_name] }

        assert_match %r{\Atmp/incoming/}, requests[:put_object][:params][:key]
        assert_equal a.s3_key, requests[:copy_object][:params][:key]
      end
    end
  end

  def test_a_threat_in_an_upload_through_lambda_is_a_validation_error
    with_s3(stub_client(get_object_tagging: scan_tag('THREATS_FOUND'))) do
      with_malware_scan do
        a = Attachment.new(container: Issue.find(1), author: User.find(1),
                           file: mock_file(filename: 'virus.txt', content: 'x'))

        assert_not a.save
        assert_includes a.errors.full_messages.join, 'threat'
        assert_not Attachment.exists?(filename: 'virus.txt')
        assert_not File.exist?(a.local_diskfile)
      end
    end
  ensure
    Setting.plugin_redmine_serverless_s3 = {}
  end

  def test_attachments_of_received_mail_are_not_waited_for
    with_s3(stub_client) do |client|
      with_malware_scan do
        RedmineServerlessS3::MalwareScan.skip do
          Attachment.create!(container: Issue.find(1), author: User.find(1),
                             file: mock_file(filename: 'mail.txt', content: 'mail'))
        end

        assert_not_includes operations(client), :get_object_tagging
      end
    end
  end

  def test_saving_without_a_new_file_puts_nothing
    with_s3(stub_client) do |client|
      a = Attachment.find(1)
      a.description = 'changed'
      a.save!

      assert_not_includes operations(client), :put_object
    end
  end

  def test_readable_asks_s3_when_the_file_is_not_local
    with_s3(stub_client(head_object: { content_length: 1 })) do |client|
      a = Attachment.new(disk_directory: '2026/11', disk_filename: 'missing.txt')

      assert a.readable?
      assert a.readable?
      assert_equal [:head_object], operations(client)
      assert_equal 'files/2026/11/missing.txt', client.api_requests.last[:params][:key]
    end
  end

  def test_readable_is_false_when_s3_does_not_have_it
    with_s3(stub_client(head_object: 'NotFound')) do
      assert_not Attachment.new(disk_directory: '2026/11', disk_filename: 'missing.txt').readable?
    end
  end

  def test_diskfile_fetches_a_saved_attachment
    with_s3(stub_client(get_object: { body: 'from s3' })) do
      a = Attachment.find(1)
      FileUtils.rm_f(a.local_diskfile)

      assert_equal 'from s3', File.read(a.diskfile)
    end
  end

  def test_diskfile_of_a_new_record_fetches_nothing
    with_s3(stub_client) do |client|
      Attachment.new(disk_directory: '2026/11', disk_filename: 'new.txt').diskfile

      assert_empty client.api_requests
    end
  end

  def test_delete_from_disk_deletes_the_object_and_its_thumbnails
    with_s3(stub_client(list_objects_v2: { contents: [{ key: 'tmp/thumbnails/d_1_100.thumb' }] })) do |client|
      a = Attachment.create!(container: Issue.find(1), author: User.find(1),
                             file: mock_file(filename: 'gone.txt', content: 'gone'))
      key = a.s3_key
      a.destroy
      deleted = client.api_requests.select { |request| request[:operation_name] == :delete_objects }
                      .flat_map { |request| request[:params][:delete][:objects].pluck(:key) }
      listed = client.api_requests.find { |request| request[:operation_name] == :list_objects_v2 }

      assert_includes deleted, key
      assert_includes deleted, 'tmp/thumbnails/d_1_100.thumb'
      assert_equal "tmp/thumbnails/#{a.digest}_#{a.filesize}_", listed[:params][:prefix]
      assert_includes deleted, "files/derived_cache/markdownized_previews/#{a.digest}_#{a.filesize}.md"
      assert_not File.exist?(a.local_diskfile)
    end
  end

  # The Markdown preview is kept in S3 at Redmine's own path, and reused.
  def test_markdownized_preview_is_stored_in_s3_and_reused
    a = Attachment.create!(container: Issue.find(1), author: User.find(1),
                           file: mock_file(filename: 'doc.docx', content: 'docx'))
    key = "files/derived_cache/markdownized_previews/#{a.digest}_#{a.filesize}.md"
    target = a.send(:markdownized_preview_cache_path)
    Redmine::Markdownizer.stubs(:available?).returns(true)
    Redmine::Markdownizer.stubs(:supports?).returns(true)
    Redmine::Markdownizer.expects(:convert).once.with do |_source, path|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, '# Preview')
    end.returns(target)

    with_s3(stub_client(head_object: 'NotFound')) do |client|
      assert_equal '# Preview', a.markdownized_preview_content
      assert(client.api_requests.any? { |r| r[:operation_name] == :put_object && r[:params][:key] == key })
    end
    FileUtils.rm_f(target)
    Redmine::Markdownizer.stubs(:convert).returns(target)
    with_s3(stub_client(head_object: {}, get_object: { body: '# Preview' })) do |client|
      assert_equal '# Preview', a.markdownized_preview_content
      assert_includes operations(client), :get_object
      assert_not(client.api_requests.any? { |r| r[:operation_name] == :put_object && r[:params][:key] == key })
    end
  end

  def test_a_shared_file_is_not_deleted
    with_s3(stub_client) do |client|
      a1 = Attachment.create!(container: Issue.find(1), author: User.find(1),
                              file: mock_file(filename: 'one.txt', content: 'same'))
      a2 = Attachment.create!(container: Issue.find(1), author: User.find(1),
                              file: mock_file(filename: 'two.txt', content: 'same'))
      client.api_requests.clear
      a2.reload.destroy

      assert_equal a1.disk_filename, a2.disk_filename
      assert_not_includes operations(client), :delete_objects
    end
  end

  def test_same_content_is_shared_by_digest_and_size
    with_s3(stub_client) do |client|
      a1 = Attachment.create!(container: Issue.find(1), author: User.find(1),
                              file: mock_file(filename: 'first.txt', content: 'abcd'))
      a2 = Attachment.create!(container: Issue.find(1), author: User.find(1),
                              file: mock_file(filename: 'second.txt', content: 'abcd'))
      a2.reload
      deleted = client.api_requests.select { |request| request[:operation_name] == :delete_objects }
                      .flat_map { |request| request[:params][:delete][:objects].pluck(:key) }

      assert_equal a1.s3_key, a2.s3_key
      assert_equal 1, deleted.size
      assert_match(/_second\.txt\z/, deleted.first)
    end
  end

  def test_no_thumbnail_beyond_the_cache_size
    with_s3(stub_client) do
      with_plugin_settings('cache_size_mb' => '1') do
        assert Attachment.new(filename: 'a.png', filesize: 1.megabyte).thumbnailable?
        assert_not Attachment.new(filename: 'a.png', filesize: 1.megabyte + 1).thumbnailable?
      end
    end
  end

  def test_thumbnail_size_is_redmines
    a = Attachment.new
    with_settings thumbnails_size: '120' do
      assert_equal 120, a.thumbnail_size({})
    end
    assert_equal 200, a.thumbnail_size(size: 151)
    assert_equal 800, a.thumbnail_size(size: 2000)
  end

  private

  def with_plugin_settings(values)
    saved = Setting.plugin_redmine_serverless_s3
    Setting.plugin_redmine_serverless_s3 = (saved.is_a?(Hash) ? saved : {}).merge(values)
    yield
  ensure
    Setting.plugin_redmine_serverless_s3 = saved
  end
end
