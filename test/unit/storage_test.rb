# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessS3StorageTest < ActiveSupport::TestCase
  include RedmineServerlessS3::TestHelper

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_put_file_asks_s3_for_a_sha256_checksum
    client = stub_client
    path = File.join(@dir, 'a.txt')
    File.write(path, 'hello')
    RedmineServerlessS3::Storage.new(client, 'b').put_file('files/a.txt', path)
    request = client.api_requests.last

    assert_equal :put_object, request[:operation_name]
    assert_equal 'SHA256', request[:params][:checksum_algorithm]
    assert_equal 'files/a.txt', request[:params][:key]
  end

  def test_download_writes_through_a_rename
    client = stub_client(get_object: { body: 'contents' })
    path = File.join(@dir, '2026/11/a.txt')

    assert RedmineServerlessS3::Storage.new(client, 'b').download('files/2026/11/a.txt', path)
    assert_equal 'contents', File.read(path)
    assert_equal ['a.txt'], Dir.children(File.dirname(path))
  end

  def test_download_of_a_missing_object
    client = stub_client(get_object: 'NoSuchKey')
    path = File.join(@dir, 'a.txt')

    assert_not RedmineServerlessS3::Storage.new(client, 'b').download('files/a.txt', path)
    assert_empty Dir.children(@dir)
  end

  def test_head_of_a_missing_object_is_nil
    client = stub_client(head_object: 'NotFound')

    assert_nil RedmineServerlessS3::Storage.new(client, 'b').head('files/a')
  end

  def test_head_with_the_checksum
    client = stub_client
    RedmineServerlessS3::Storage.new(client, 'b').head('incoming/x', checksum: true)

    assert_equal 'ENABLED', client.api_requests.last[:params][:checksum_mode]
  end

  def test_delete_sends_at_most_1000_keys_per_request
    client = stub_client
    RedmineServerlessS3::Storage.new(client, 'b').delete((1..1500).map { |i| "tmp/#{i}" })
    sizes = client.api_requests.map { |request| request[:params][:delete][:objects].size }

    assert_equal [1000, 500], sizes
  end

  def test_delete_without_keys_sends_nothing
    client = stub_client
    RedmineServerlessS3::Storage.new(client, 'b').delete([])

    assert_empty client.api_requests
  end

  def test_keys_reads_every_page
    client = stub_client(list_objects_v2: [
                           { contents: [{ key: 'files/a' }], is_truncated: true, next_continuation_token: 't' },
                           { contents: [{ key: 'files/b' }], is_truncated: false }
                         ])

    assert_equal %w[files/a files/b], RedmineServerlessS3::Storage.new(client, 'b').keys('files/')
  end

  def test_copy_escapes_the_source
    client = stub_client
    RedmineServerlessS3::Storage.new(client, 'b').copy('incoming/a b', 'files/x')

    assert_equal 'b/incoming/a%20b', client.api_requests.last[:params][:copy_source]
  end
end
