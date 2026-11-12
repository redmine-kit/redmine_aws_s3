# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The messages of uploads and checks come from the locales, in the user's
    # language (they were fixed English strings).
    class UploadMessagesTest < ActiveSupport::TestCase
      include S3::UploadTestHelper

      fixtures :users

      def presign_error(**params)
        error = assert_raises(Upload::Error) { upload.presign(filename: 'a.txt', size: 1, **params) }
        error.message
      end

      # Composed as Redmine composes the messages of its validations (Rails'
      # errors.format, which Redmine's ja.yml does not change).
      def test_a_missing_name_and_a_wrong_size_as_redmine_says_them
        assert_equal 'File cannot be blank', presign_error(filename: '')
        assert_equal 'Size is invalid', presign_error(size: 'x')
        ::I18n.with_locale(:ja) do
          assert_equal Attachment.new.tap(&:validate).errors.full_messages_for(:filename).first,
                       presign_error(filename: '')
          assert_equal 'サイズ は不正な値です', presign_error(size: 'x')
        end
      end

      def test_an_expired_ticket_in_japanese
        ::I18n.with_locale(:ja) do
          error = assert_raises(Upload::Error) { upload.complete('not a ticket') }

          assert_equal 'アップロードの有効期限が切れました。もう一度ファイルを追加してください。', error.message
        end
      end

      def test_the_malware_scan_has_not_finished
        assert_equal 'The malware scan of the file has not finished. Try again later.', Upload::Pending.new.message
        ::I18n.with_locale(:ja) do
          assert_equal 'ファイルのマルウェアスキャンが完了していません。しばらくしてからもう一度試してください。',
                       MalwareScan::Pending.new.message
        end
      end

      # The read/write test says what was wrong instead of RuntimeError.
      def test_different_contents_in_the_read_write_test
        with_s3(stub_client(get_object: { body: 'other' })) do
          assert_equal ['GetObject', false, 'Different contents'], Checks.read_write.second
          ::I18n.with_locale(:ja) { assert_equal '内容が一致しません', Checks.read_write.second.last }
        end
      end

      # The texts that the upload scripts show, in the page's <meta> tag.
      def test_the_texts_of_the_scripts
        texts = ::I18n.with_locale(:ja) { JSON.parse(Hooks.instance.send(:upload_messages).to_json) }

        assert_equal 'アップロードに失敗しました ({status})', texts['failedStatus']
        assert_equal 'アップロードに失敗しました', texts['failed']
        assert_equal 'ネットワークエラー', texts['networkError']
      end
    end
  end
end
