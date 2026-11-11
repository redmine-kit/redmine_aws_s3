# frozen_string_literal: true

require_relative '../test_helper'

class RedmineAwsS3ImportPatchTest < ActiveSupport::TestCase
  include RedmineAwsS3::TestHelper

  fixtures :users

  def new_import
    import = IssueImport.new(user: User.find(2))
    import.file = uploaded_test_file('import_issues.csv', 'text/csv')
    import.save!
    import
  end

  def test_the_file_is_stored_in_s3
    with_s3(stub_client) do |client|
      import = new_import
      put = client.api_requests.find { |request| request[:operation_name] == :put_object }

      assert_equal "imports/#{import.filename}", put[:params][:key]
      assert File.exist?(import.filepath)
    end
  end

  def test_a_file_not_in_this_environment_is_fetched
    with_s3(stub_client(get_object: { body: "subject\nfrom s3\n" })) do
      import = new_import
      FileUtils.rm_f(import.filepath)

      assert Import.find(import.id).file_exists?
      assert_equal "subject\nfrom s3\n", File.read(import.filepath)
    end
  end

  def test_a_file_in_neither_place
    with_s3(stub_client(get_object: 'NoSuchKey')) do
      import = new_import
      FileUtils.rm_f(import.filepath)

      assert_not Import.find(import.id).file_exists?
    end
  end

  def test_destroying_the_import_deletes_the_object
    with_s3(stub_client) do |client|
      import = new_import
      import.destroy
      deleted = client.api_requests.find { |request| request[:operation_name] == :delete_objects }

      assert_equal "imports/#{import.filename}", deleted[:params][:delete][:objects].first[:key]
      assert_not File.exist?(import.filepath)
    end
  end

  def test_the_file_is_read_after_a_clean_scan
    with_s3(stub_client(get_object_tagging: [scan_tag(nil), scan_tag('NO_THREATS_FOUND')])) do
      with_malware_scan do
        import = new_import

        assert_not Import.find(import.id).file_exists?
        assert Import.find(import.id).file_exists?
      end
    end
  end

  def test_a_threat_in_an_import_file
    with_s3(stub_client(get_object_tagging: scan_tag('THREATS_FOUND'))) do
      with_malware_scan do
        import = new_import

        assert_not Import.find(import.id).file_exists?
        assert_not File.exist?(import.filepath)
      end
    end
  ensure
    Setting.plugin_redmine_aws_s3 = {}
  end

  def test_off_without_the_bucket
    client = stub_client
    RedmineAwsS3.client = client
    import = new_import
    import.destroy

    assert_empty client.api_requests
  ensure
    RedmineAwsS3.client = nil
  end
end
