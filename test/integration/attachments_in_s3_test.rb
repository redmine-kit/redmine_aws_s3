# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/attachments_in_s3_setup'

module RedmineAws
  module S3
    # Uploads from the browser through CloudFront, and the malware scan.
    class AttachmentsInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AttachmentsInS3Setup

      DATA = "contents uploaded by the browser\n"

      def test_an_upload_through_cloudfront_is_attached
        with_test_s3 do
          incoming, attachment = attach_upload

          assert_nil object(incoming), 'the upload is deleted from tmp/incoming/'
          assert_equal 'browser.txt', attachment.filename
          assert_equal Digest::SHA256.hexdigest(DATA), attachment.digest
          assert_equal DATA, object(attachment.s3_key)
          assert_not File.exist?(attachment.local_diskfile), 'the file did not pass through Redmine'
        end
      end

      def test_an_upload_is_downloaded_through_cloudfront
        with_test_s3 do
          _, attachment = attach_upload
          get "/attachments/download/#{attachment.id}/browser.txt"

          assert_response :redirect
          unsigned, = verify_signed_url(response.location)
          assert_equal "/#{attachment.s3_key}", URI(unsigned).path
        end
      end

      def test_the_text_view_of_an_upload_reads_the_tmp_cache
        with_test_s3 do
          _, attachment = attach_upload
          get "/attachments/#{attachment.id}"

          assert_response :success
          assert_include 'contents uploaded by the browser', response.body
          assert File.exist?(attachment.local_diskfile), 'the text view reads the /tmp cache'
        end
      end

      def test_identical_uploads_share_one_object
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          _, first = emulate_s3_checksums { upload_through_cloudfront('same bytes', 'one.txt') }
          _, second = emulate_s3_checksums { upload_through_cloudfront('same bytes', 'two.txt') }
          a1 = Attachment.find_by_token(first)
          a2 = Attachment.find_by_token(second)

          assert_equal a1.s3_key, a2.s3_key
          assert_equal [a1.s3_key], keys('files/')
        end
      end

      def test_the_upload_waits_for_the_malware_scan
        with_test_s3 do
          with_malware_scan do
            key, ticket = presign_and_put('scanned by GuardDuty', 'scanned.txt')
            emulate_s3_checksums { complete_after_the_scan(key, ticket) }
            attachment = Attachment.last

            assert_equal 'scanned.txt', attachment.filename
            assert_equal 'scanned by GuardDuty', object(attachment.s3_key)
            assert_nil object(key)
          end
        end
      end

      def test_a_threat_found_by_the_malware_scan_is_refused
        with_test_s3 do
          with_malware_scan do
            key = refuse_a_threat

            assert_response :unprocessable_content
            assert_includes response.parsed_body['errors'].first, 'threat'
            assert_nil object(key)
          end
        end
      ensure
        Setting.plugin_redmine_aws_s3 = {}
      end

      def test_a_threat_found_by_the_malware_scan_is_recorded
        with_test_s3 do
          with_malware_scan do
            refuse_a_threat

            assert_equal 'bad.txt', RedmineAws::S3::MalwareScan.findings.first['filename']
          end
        end
      ensure
        Setting.plugin_redmine_aws_s3 = {}
      end

      private

      # As jsmith, DATA uploaded through CloudFront and attached to a new
      # issue; returns the key in tmp/incoming/ and the attachment.
      def attach_upload
        log_user('jsmith', 'jsmith')
        incoming, token = emulate_s3_checksums { upload_through_cloudfront(DATA, 'browser.txt') }
        assert token.present?
        post '/projects/ecookbook/issues', params: {
          issue: { tracker_id: 1, subject: 'With an upload' }, attachments: { '1' => { token: token } }
        }
        [incoming, Issue.last.attachments.first]
      end

      # Completes the upload before the scan's tag (202) and after it.
      def complete_after_the_scan(key, ticket)
        complete_upload(ticket)
        assert_response :accepted
        tag_scan(key, 'NO_THREATS_FOUND')
        complete_upload(ticket)
        assert_response :success
      end

      # An upload that the scan found a threat in, completed; returns its key.
      def refuse_a_threat
        key, ticket = presign_and_put('not a real threat', 'bad.txt')
        tag_scan(key, 'THREATS_FOUND')
        assert_no_difference('Attachment.count') { complete_upload(ticket) }
        key
      end
    end
  end
end
