# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The Markdown preview is kept in S3 at Redmine's own path, and reused.
    class AttachmentPreviewTest < ActiveSupport::TestCase
      include S3::AttachmentTestHelper

      fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations, :attachments

      def setup
        super
        Redmine::Markdownizer.stubs(:available?).returns(true)
        Redmine::Markdownizer.stubs(:supports?).returns(true)
        # Saved without the plugin, so only on the local disk.
        @attachment = create_issue_attachment('doc.docx', 'docx')
        @target = @attachment.send(:markdownized_preview_cache_path)
        FileUtils.rm_f(@target)
      end

      def teardown
        FileUtils.rm_f(@target)
      end

      def preview_key
        "files/derived_cache/markdownized_previews/#{@attachment.digest}_#{@attachment.filesize}.md"
      end

      def preview_put?(client)
        client.api_requests.any? { |r| r[:operation_name] == :put_object && r[:params][:key] == preview_key }
      end

      def test_markdownized_preview_is_stored_in_s3
        Redmine::Markdownizer.expects(:convert).once.with do |_source, path|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, '# Preview')
        end.returns(@target)

        with_s3(stub_client(head_object: 'NotFound')) do |client|
          assert_equal '# Preview', @attachment.markdownized_preview_content
          assert preview_put?(client)
        end
      end

      def test_markdownized_preview_is_reused_from_s3
        Redmine::Markdownizer.stubs(:convert).returns(@target)

        with_s3(stub_client(head_object: {}, get_object: { body: '# Preview' })) do |client|
          assert_equal '# Preview', @attachment.markdownized_preview_content
          assert_includes operations(client), :get_object
          assert_not preview_put?(client)
        end
      end
    end
  end
end
