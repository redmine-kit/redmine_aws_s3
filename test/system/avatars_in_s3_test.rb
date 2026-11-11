# frozen_string_literal: true

require File.expand_path('../../../../test/application_system_test_case', __dir__)
require_relative '../test_helper'
require_relative 'fake_cloudfront'

# The avatar form of Redmine 7.1 in headless Chrome
# (assets/javascripts/s3_avatar_upload.js): the image goes through the fake
# CloudFront to the S3 of the tests, and the form reaches Redmine with the
# ticket instead of the file. Skipped on Redmine 7.0, which has no avatars.
class RedmineAwsS3AvatarsSystemTest < ApplicationSystemTestCase
  include RedmineAwsS3::TestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :enabled_modules

  # As in attachments_in_s3_test.rb: the browser reaches the fake CloudFront
  # on the test server over http.
  module HttpUrls
    def url_for(...)
      super.sub(%r{\Ahttps://}, 'http://')
    end
  end
  RedmineAwsS3::UrlSigner.prepend(HttpUrls)
  Capybara.app = RedmineAwsS3::FakeCloudFront.new(
    Rails.application, public_key: RedmineAwsS3::TestHelper.private_key.public_key
  )

  def setup
    skip 'Redmine has no avatars before 7.1' unless RedmineAwsS3.avatars?
    skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

    set_tmp_attachments_directory
    @client = s3_test_client
    @bucket = "redmine-system-#{SecureRandom.hex(6)}"
    @client.create_bucket(bucket: @bucket)
    @saved_env = s3_env.keys.index_with { |name| ENV.fetch(name, nil) }
    app = URI(Capybara.app_host)
    s3_env(bucket: @bucket).merge(RedmineAwsS3::ENV_DOMAIN => "#{app.host}:#{app.port}")
                           .each { |name, value| ENV[name] = value }
    RedmineAwsS3.client = @client
    page.driver.browser.file_detector = ->(args) { args.first.to_s if File.exist?(args.first.to_s) }
    @updates = []
    @subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
      @updates << payload[:params] if payload[:controller] == 'AvatarsController' && payload[:action] == 'update'
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
    @saved_env&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    RedmineAwsS3.client = nil
  end

  def large_image
    path = File.join(Dir.tmpdir, "redmine-s3-avatar-#{SecureRandom.hex(4)}.png")
    system(Redmine::Thumbnail::CONVERT_BIN, '-size', '800x800', 'xc:gray', '+noise', 'Random', path,
           exception: true)
    path
  end

  def test_the_image_goes_through_cloudfront
    path = large_image

    assert_operator File.size(path), :>, 1.megabyte
    log_user('jsmith', 'jsmith')
    visit '/my/avatar'
    attach_file 'avatar', path
    click_on 'Update'

    assert_text 'Successful update.', wait: 120
    avatar = User.find(2).avatar

    assert_equal File.binread(path), @client.get_object(bucket: @bucket, key: avatar.s3_key).body.read.b
    assert_equal 1, @updates.size
    assert @updates.first['s3_ticket'].present?, 'the form did not carry the ticket'
    assert_nil @updates.first['avatar'], 'the form sent the file to Redmine'
    assert_empty @client.list_objects_v2(bucket: @bucket, prefix: 'tmp/incoming/').contents
    image = find('.avatar-preview img.avatar')

    assert page.evaluate_script('arguments[0].complete && arguments[0].naturalWidth > 0', image),
           'the avatar did not load'
  ensure
    FileUtils.rm_f(path) if path
  end

  def test_an_upload_error_is_shown_in_the_form
    log_user('jsmith', 'jsmith')
    with_settings attachment_max_size: '1' do
      visit '/my/avatar'
      attach_file 'avatar', Rails.root.join('test/fixtures/files/2010/11/101123161450_testfile_1.png')
      click_on 'Update'

      assert_selector '#errorExplanation', text: /exceeds the maximum allowed file size/
    end
    assert_empty @updates
    assert_nil User.find(2).avatar_id
    assert_selector 'input[type=submit][value=Update]:not([disabled])'
  end
end
