# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessS3CacheTest < ActiveSupport::TestCase
  include RedmineServerlessS3::TestHelper

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(name, size, age)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, 'x' * size)
    time = Time.now - age
    File.utime(time, time, path)
    path
  end

  def test_prune_deletes_the_least_recently_used_files
    oldest = write('2026/10/a', 400, 300)
    older = write('2026/11/b', 400, 200)
    newest = write('2026/11/c', 400, 100)
    RedmineServerlessS3::Cache.prune(root: @dir, limit: 900)

    assert_not File.exist?(oldest)
    assert File.exist?(older)
    assert File.exist?(newest)
  end

  def test_prune_keeps_the_file_just_fetched
    kept = write('a', 800, 300)
    other = write('b', 400, 100)
    RedmineServerlessS3::Cache.prune(keep: kept, root: @dir, limit: 900)

    assert File.exist?(kept)
    assert_not File.exist?(other)
  end

  def test_fetch_touches_a_cached_file
    path = write('a', 10, 3600)
    client = stub_client
    with_s3(client) do
      assert RedmineServerlessS3::Cache.fetch('files/a', path)
    end

    assert_empty client.api_requests
    assert_in_delta Time.now.to_f, File.mtime(path).to_f, 5
  end

  def test_fetch_downloads_a_missing_file
    path = File.join(@dir, '2026/11/a')
    with_s3(stub_client(get_object: { body: 'abc' })) do
      Attachment.stubs(:storage_path).returns(@dir)

      assert RedmineServerlessS3::Cache.fetch('files/2026/11/a', path)
    end

    assert_equal 'abc', File.read(path)
  end
end
