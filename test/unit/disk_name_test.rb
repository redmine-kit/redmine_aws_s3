# frozen_string_literal: true

require_relative '../test_helper'

class RedmineAwsS3DiskNameTest < ActiveSupport::TestCase
  include RedmineAwsS3::TestHelper

  fixtures :attachments

  Name = RedmineAwsS3::DiskName

  def test_ascii_names_are_kept
    assert_equal 'report-1.txt', Name.ascii('report-1.txt')
  end

  def test_other_names_are_hashed_with_their_extension
    ['報告.pdf', "#{'a' * 60}.txt"].each do |filename|
      hashed = ActiveSupport::Digest.hexdigest(filename)
      ext = File.extname(filename)
      expected = hashed.length + ext.length <= Name::MAX_LENGTH ? hashed + ext : hashed

      assert_equal expected, Name.ascii(filename)
    end
  end

  def test_a_taken_name_moves_to_the_next_second
    travel_to Time.utc(2026, 11, 9, 12, 0, 0) do
      with_s3(stub_client(head_object: [{ content_length: 1 }, 'NotFound'])) do
        assert_equal '261109120001_a.txt', Name.free('a.txt', '2026/11')
      end
    end
  end
end
