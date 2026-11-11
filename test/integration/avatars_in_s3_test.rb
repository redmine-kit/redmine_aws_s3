# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/avatars_in_s3_setup'

module RedmineAws
  module S3
    # Avatars of Redmine 7.1: the image sent through CloudFront and registered
    # by Redmine's own form, and the malware scan.
    class AvatarsInS3Test < Redmine::IntegrationTest
      include S3::TestHelper
      include AvatarsInS3Setup

      def test_upload_through_cloudfront
        with_test_s3 do
          jsmith_with_avatar

          assert_redirected_to '/my/avatar'
          assert_equal 'Successful update.', flash[:notice]
          assert_equal '101123161450_testfile_1.png', assert_avatar_from(fixture(IMAGE), User.find(2)).filename
        end
      end

      def test_upload_of_an_image_over_1_mb
        path = large_image

        assert_operator File.size(path), :>, 1.megabyte
        with_test_s3 do
          jsmith_with_avatar(path)

          assert_redirected_to '/my/avatar'
          assert_avatar_from(path, User.find(2))
        end
      ensure
        FileUtils.rm_f(path) if path
      end

      def test_the_form_without_javascript_sends_the_file_to_redmine
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          put '/my/avatar', params: { avatar: uploaded_test_file(IMAGE, 'image/png') }

          assert_redirected_to '/my/avatar'
          assert_avatar_from(fixture(IMAGE), User.find(2))
        end
      end

      def test_the_avatar_page_loads_the_upload_script
        with_test_s3 do
          log_user('jsmith', 'jsmith')
          get '/my/avatar'

          assert_response :success
          assert_select 'meta[name=redmine-s3-avatar-presign-url][content=?]', '/s3_uploads/avatar/presign'
          assert_select 'meta[name=redmine-s3-avatar-check-url][content=?]', '/s3_uploads/avatar/check'
          assert_select 'script[src*=s3_avatar_upload]'
          assert_select 'form[action="/my/avatar"] input[type=file][name=avatar]'
        end
      end

      def test_the_check_answers_202_while_the_scan_runs
        with_test_s3 do
          with_malware_scan do
            _, ticket = scanned_upload
            post '/s3_uploads/avatar/check', params: { ticket: ticket }

            assert_response :accepted
            assert_equal '2', response.headers['Retry-After']
          end
        end
      end

      def test_the_upload_is_registered_after_the_scan
        with_test_s3 do
          with_malware_scan do
            ticket = check_after_the_scan(*scanned_upload)
            put '/my/avatar', params: { s3_ticket: ticket }

            assert_redirected_to '/my/avatar'
            assert_avatar_from(fixture(IMAGE), User.find(2))
          end
        end
      end

      # The form sent without JavaScript goes through Lambda and the scan of
      # uploads through Lambda; without a result the form shows an error.
      def test_the_form_without_javascript_shows_the_scan_as_an_error
        with_test_s3 do
          with_malware_scan do
            log_user('jsmith', 'jsmith')
            put '/my/avatar', params: { avatar: uploaded_test_file(IMAGE, 'image/png') }

            assert_response :unprocessable_content
            assert_select '#errorExplanation', text: /still being scanned/
            assert_nil User.find(2).avatar_id
          end
        end
      end

      private

      # A photo larger than the 1 MB a request through CloudFront to Redmine can
      # carry: random pixels do not compress.
      def large_image
        path = File.join(Dir.tmpdir, "redmine-s3-avatar-#{SecureRandom.hex(4)}.png")
        system(Redmine::Thumbnail::CONVERT_BIN, '-size', '800x800', 'xc:gray', '+noise', 'Random', path,
               exception: true)
        path
      end

      # The check after the tag of the scan; returns the ticket.
      def check_after_the_scan(key, ticket)
        tag_scan(key, 'NO_THREATS_FOUND')
        post '/s3_uploads/avatar/check', params: { ticket: ticket }
        assert_response :success
        ticket
      end

      # As jsmith, the image presigned and put, not checked yet (GuardDuty
      # is not reproduced locally; the tests put the tag GuardDuty would).
      def scanned_upload
        log_user('jsmith', 'jsmith')
        presign_and_put(File.binread(fixture(IMAGE)), 'scanned.png')
      end
    end
  end
end
