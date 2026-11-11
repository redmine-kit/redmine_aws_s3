# frozen_string_literal: true

require_relative '../test_helper'

# Avatars of Redmine 7.1 (docs/attachments.md#avatars) with S3 reproduced by
# LocalStack or moto: the image sent through CloudFront and registered by
# Redmine's own form, the cropped thumbnails kept in S3, and Redmine's own
# rules for showing them. Skipped on Redmine 7.0, which has no avatars.
class RedmineAwsS3AvatarsInS3Test < Redmine::IntegrationTest
  include RedmineAwsS3::TestHelper

  fixtures :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :projects,
           :enabled_modules

  IMAGE = '2010/11/101123161450_testfile_1.png'
  OTHER_IMAGE = '2010/12/101223161450_testfile_2.png'

  def setup
    skip 'Redmine has no avatars before 7.1' unless RedmineAwsS3.avatars?
    skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?

    set_tmp_attachments_directory
    Attachment.clear_thumbnails
  end

  def fixture(name)
    Rails.root.join('test/fixtures/files', name).to_s
  end

  def object(key)
    RedmineAwsS3.client.get_object(bucket: RedmineAwsS3.bucket, key: key).body.read
  rescue Aws::S3::Errors::NoSuchKey
    nil
  end

  def keys(prefix)
    RedmineAwsS3.storage.keys(prefix)
  end

  # The browser's side (s3_avatar_upload.js): presign, the PUT that
  # CloudFront sends to S3 through OAC, and the check. Returns the key of the
  # upload and the ticket.
  def upload(path, filename: File.basename(path))
    data = File.binread(path)
    post '/s3_uploads/avatar/presign', params: { filename: filename, size: data.bytesize, content_type: 'image/png' }
    assert_response :success
    presigned = response.parsed_body
    key = URI(presigned['url']).path.delete_prefix('/')
    RedmineAwsS3.client.put_object(bucket: RedmineAwsS3.bucket, key: key, body: data)
    post '/s3_uploads/avatar/check', params: { ticket: presigned['ticket'] }
    assert_response :success
    [key, presigned['ticket']]
  end

  def thumbnail_key(attachment, size)
    "tmp/thumbnails/#{attachment.digest}_#{attachment.filesize}_#{size}_crop.thumb"
  end

  # A photo larger than the 1 MB a request through CloudFront to Redmine can
  # carry: random pixels do not compress.
  def large_image
    path = File.join(Dir.tmpdir, "redmine-s3-avatar-#{SecureRandom.hex(4)}.png")
    system(Redmine::Thumbnail::CONVERT_BIN, '-size', '800x800', 'xc:gray', '+noise', 'Random', path,
           exception: true)
    path
  end

  def assert_avatar_from(path, user, author: user)
    avatar = user.reload.avatar

    assert avatar, 'the user has no avatar'
    assert_equal author, avatar.author
    assert_equal user, avatar.container
    assert_equal File.binread(path), object(avatar.s3_key).b
    assert object(thumbnail_key(avatar, 100)), 'the thumbnail Redmine tests the image with is in S3'
    assert_empty keys('tmp/incoming/')
    avatar
  end

  def test_upload_through_cloudfront
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      _, ticket = upload(fixture(IMAGE))
      put '/my/avatar', params: { s3_ticket: ticket }

      assert_redirected_to '/my/avatar'
      assert_equal 'Successful update.', flash[:notice]
      assert_equal '101123161450_testfile_1.png', assert_avatar_from(fixture(IMAGE), User.find(2)).filename
    end
  end

  def test_upload_of_an_image_over_1_mb
    path = large_image

    assert_operator File.size(path), :>, 1.megabyte
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      _, ticket = upload(path, filename: 'photo.png')
      put '/my/avatar', params: { s3_ticket: ticket }

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

  def test_show_serves_the_cropped_thumbnail_from_s3
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      put '/my/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }
      avatar = User.find(2).avatar
      # Another environment: neither the image nor its thumbnails on the disk.
      FileUtils.rm_f(avatar.local_diskfile)
      Attachment.clear_thumbnails
      reset!

      get "/users/2/avatar/#{User.find(2).avatar_key}/100"

      assert_response :success
      assert_equal 'image/png', response.media_type
      assert_match(/\Ainline/, response.headers['Content-Disposition'])
      assert_equal "max-age=#{1.day.to_i}, public", response.headers['Cache-Control']
      assert_equal object(thumbnail_key(avatar, 100)).b, response.body.b
      assert_not File.exist?(avatar.local_diskfile), 'the image was not read for a thumbnail in S3'

      get "/users/2/avatar/#{User.find(2).avatar_key}/48"

      assert_response :success
      assert_equal object(thumbnail_key(avatar, 50)).b, response.body.b
      assert_not_equal File.binread(fixture(IMAGE)).b, response.body.b
    end
  end

  def test_show_is_private_when_login_is_required
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      put '/my/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }
      path = "/users/2/avatar/#{User.find(2).avatar_key}/100"
      with_settings login_required: '1' do
        get path

        assert_response :success
        assert_equal "max-age=#{1.day.to_i}, private", response.headers['Cache-Control']

        reset!
        get path

        assert_response :redirect
        assert_match %r{/login}, response.location
      end
    end
  end

  def test_show_checks_the_key
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      put '/my/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }
      get "/users/2/avatar/#{'0' * 16}/100"

      assert_response :not_found
    end
  end

  def test_replace_deletes_the_old_avatar_in_s3
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      put '/my/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }
      old = User.find(2).avatar
      put '/my/avatar', params: { s3_ticket: upload(fixture(OTHER_IMAGE)).last }

      assert_redirected_to '/my/avatar'
      assert_avatar_from(fixture(OTHER_IMAGE), User.find(2))
      assert_not Attachment.exists?(old.id)
      assert_nil object(old.s3_key)
      assert_empty keys("tmp/thumbnails/#{old.digest}_")
    end
  end

  def test_delete_deletes_the_avatar_in_s3
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      put '/my/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }
      avatar = User.find(2).avatar
      delete '/my/avatar'

      assert_redirected_to '/my/avatar'
      assert_nil User.find(2).avatar_id
      assert_nil object(avatar.s3_key)
      assert_empty keys('tmp/thumbnails/')
    end
  end

  def test_an_administrator_uploads_for_another_user
    with_test_s3 do
      log_user('admin', 'admin')
      put '/users/2/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }

      assert_redirected_to '/users/2/avatar'
      assert_avatar_from(fixture(IMAGE), User.find(2), author: User.find(1))
      assert_nil User.find(1).avatar_id
    end
  end

  def test_only_an_administrator_changes_another_users_avatar
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      put '/users/3/avatar', params: { s3_ticket: upload(fixture(IMAGE)).last }

      assert_response :forbidden
      assert_nil User.find(3).avatar_id
    end
  end

  def test_the_ticket_of_another_user_is_refused
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      _, ticket = upload(fixture(IMAGE))
      reset!
      log_user('admin', 'admin')
      put '/my/avatar', params: { s3_ticket: ticket }

      assert_response :unprocessable_content
      assert_select '#errorExplanation', text: /the upload ticket is invalid or expired/
      assert_nil User.find(1).avatar_id
    end
  end

  def test_a_file_that_is_not_an_image_is_refused_as_redmine_refuses_it
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      key, ticket = upload(fixture('testfile.txt'), filename: 'not-an-image.png')
      put '/my/avatar', params: { s3_ticket: ticket }

      assert_response :unprocessable_content
      assert_select '#errorExplanation', text: /Avatar is invalid/
      assert_nil User.find(2).avatar_id
      assert_nil object(key)
      assert_empty keys('files/')
    end
  end

  def test_presign_checks_the_size
    with_test_s3 do
      log_user('jsmith', 'jsmith')
      with_settings attachment_max_size: '1' do
        post '/s3_uploads/avatar/presign', params: { filename: 'big.png', size: 2.kilobytes }
      end

      assert_response :unprocessable_content
      assert_match(/exceeds the maximum allowed file size/, response.parsed_body['errors'].first)
    end
  end

  def test_presign_needs_a_login
    with_test_s3 do
      post '/s3_uploads/avatar/presign', params: { filename: 'a.png', size: 1 }

      assert_response :redirect
      assert_match %r{/login}, response.location
    end
  end

  # GuardDuty is not reproduced locally; the test puts the tag GuardDuty would.
  def test_the_upload_waits_for_the_malware_scan
    with_test_s3 do
      with_malware_scan do
        log_user('jsmith', 'jsmith')
        data = File.binread(fixture(IMAGE))
        post '/s3_uploads/avatar/presign', params: { filename: 'scanned.png', size: data.bytesize }
        presigned = response.parsed_body
        key = URI(presigned['url']).path.delete_prefix('/')
        RedmineAwsS3.client.put_object(bucket: RedmineAwsS3.bucket, key: key, body: data)
        post '/s3_uploads/avatar/check', params: { ticket: presigned['ticket'] }

        assert_response :accepted
        assert_equal '2', response.headers['Retry-After']

        RedmineAwsS3.client.put_object_tagging(
          bucket: RedmineAwsS3.bucket, key: key,
          tagging: { tag_set: [{ key: RedmineAwsS3::MalwareScan::TAG, value: 'NO_THREATS_FOUND' }] }
        )
        post '/s3_uploads/avatar/check', params: { ticket: presigned['ticket'] }

        assert_response :success
        put '/my/avatar', params: { s3_ticket: presigned['ticket'] }

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
end

# Redmine 7.0 has no avatar form: nothing of the avatar upload is there.
class RedmineAwsS3AvatarsBefore71Test < Redmine::IntegrationTest
  include RedmineAwsS3::TestHelper

  fixtures :users, :email_addresses, :user_preferences

  def setup
    skip 'Redmine has avatars (7.1)' if RedmineAwsS3.avatars?
  end

  def test_no_avatar_upload
    with_s3(stub_client) do
      log_user('jsmith', 'jsmith')
      post '/s3_uploads/avatar/presign', params: { filename: 'a.png', size: 1 }

      assert_response :not_found
      get '/my/account'

      assert_response :success
      assert_select 'meta[name=redmine-s3-avatar-presign-url]', 0
    end
  end
end
