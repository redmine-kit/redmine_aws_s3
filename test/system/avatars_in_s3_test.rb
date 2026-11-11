# frozen_string_literal: true

require File.expand_path('../../../../test/application_system_test_case', __dir__)
require_relative '../test_helper'
require_relative '../support/system_s3_setup'
require_relative 'fake_cloudfront'

module RedmineAws
  module S3
    # The avatar form of Redmine 7.1 in headless Chrome
    # (assets/javascripts/s3_avatar_upload.js): the image goes through the fake
    # CloudFront to the S3 of the tests, and the form reaches Redmine with the
    # ticket instead of the file. Skipped on Redmine 7.0, which has no avatars.
    class AvatarsSystemTest < ApplicationSystemTestCase
      include S3::TestHelper
      include SystemS3Setup

      fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
               :enabled_modules

      # As in attachments_in_s3_test.rb: the browser reaches the fake CloudFront
      # on the test server over http.
      module HttpUrls
        def url_for(...)
          super.sub(%r{\Ahttps://}, 'http://')
        end
      end
      RedmineAws::S3::UrlSigner.prepend(HttpUrls)
      Capybara.app = RedmineAws::S3::FakeCloudFront.new(
        Rails.application, public_key: RedmineAws::S3::TestHelper.private_key.public_key
      )

      def setup
        skip 'Redmine has no avatars before 7.1' unless RedmineAws::S3.avatars?
        skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

        set_tmp_attachments_directory
        use_test_bucket
        @updates = []
        @subscriber = subscribe_to_updates
      end

      def teardown
        ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
        restore_s3_env
      end

      def test_the_image_goes_through_cloudfront
        path = large_image

        assert_operator File.size(path), :>, 1.megabyte
        update_avatar(path)
        assert_text 'Successful update.', wait: 120

        assert_avatar_in_s3(path)
        assert_the_form_carried_the_ticket
        assert_empty incoming_objects
        assert_image_loaded(find('.avatar-preview img.avatar'), 'the avatar did not load')
      ensure
        FileUtils.rm_f(path) if path
      end

      def test_an_upload_error_is_shown_in_the_form
        with_settings attachment_max_size: '1' do
          update_avatar(Rails.root.join('test/fixtures/files/2010/11/101123161450_testfile_1.png'))

          assert_selector '#errorExplanation', text: /exceeds the maximum allowed file size/
        end
        assert_empty @updates
        assert_nil User.find(2).avatar_id
        assert_selector 'input[type=submit][value=Update]:not([disabled])'
      end

      private

      def large_image
        path = File.join(Dir.tmpdir, "redmine-s3-avatar-#{SecureRandom.hex(4)}.png")
        system(Redmine::Thumbnail::CONVERT_BIN, '-size', '800x800', 'xc:gray', '+noise', 'Random', path,
               exception: true)
        path
      end

      # Collects the parameters of AvatarsController#update.
      def subscribe_to_updates
        ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
          @updates << payload[:params] if payload[:controller] == 'AvatarsController' && payload[:action] == 'update'
        end
      end

      # As jsmith, the image chosen in the avatar form and the form sent.
      def update_avatar(path)
        log_user('jsmith', 'jsmith')
        visit '/my/avatar'
        attach_file 'avatar', path
        click_on 'Update'
      end

      def assert_avatar_in_s3(path)
        avatar = @client.get_object(bucket: @bucket, key: User.find(2).avatar.s3_key).body.read
        assert_equal File.binread(path), avatar.b
      end

      def assert_the_form_carried_the_ticket
        assert_equal 1, @updates.size
        assert @updates.first['s3_ticket'].present?, 'the form did not carry the ticket'
        assert_nil @updates.first['avatar'], 'the form sent the file to Redmine'
      end
    end
  end
end
