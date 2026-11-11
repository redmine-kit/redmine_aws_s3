# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module S3
    # The code of Redmine 7.0.3 that the plugin replaces or copies
    # (docs/attachments.md#replaced-code). When Redmine changes one of these, the
    # test fails: check the plugin against the new code, then update the SHA256.
    # A method with two values has been checked on Redmine's master branch too
    # (7519645, 2026-11-10).
    class ReplacedCodeTest < ActiveSupport::TestCase
      METHODS = {
        'Attachment#files_to_final_location' => %w[35b195687039465548e4b2822521dfb436af2c8202196562687b9f6f2cc412a2
                                                   b5da3dce052cf6dbbd1e67ec45e4a7f48d8ffa66b0d09c60cc0365fb5b32062e],
        'Attachment#diskfile' => '65c7710000bd7f7c123ccb6dbcaa9f6081fec6ca7cbd4325891d859cf7ae5d06',
        'Attachment#readable?' => '3efe672350e43acda27a1b66780b8e213e69367c98794b81f42f51b09a3e1361',
        'Attachment#thumbnailable?' => 'f51c88d043d780f80962c1cca702b83884dc6a7bf1a199415aa23af04538f466',
        'Attachment#thumbnail' => %w[9f8cd48e6af280df350883d0b3890df7de4eb7958914409f1e2a8d8c791becd3
                                     b6c8fc72e7fc5097a23f619566c62b3f0760d6afb873416dac6542d9506a8792],
        'Attachment#thumbnail_path' => '0ed1c88fbcc36dcc590140c227c1a50e4fd17cf0c0513c25d11d3057761f8110',
        'Attachment#reuse_existing_file_if_possible' =>
          '23dc82dbed448edfc47f17988e76a57b1a790a905fa2ed6e795c2d1f4ef210d5',
        'Attachment#delete_from_disk!' => '11dd94b8432905a5ff4f69a25e5b430bcc666eb8c8b39a3ab2b8a29a1774b833',
        'Attachment#delete_from_disk' => '7350cb5de45c10384e1e24b213a4fd80e32e4883ebdda39f293053c0026fc2a8',
        'Attachment.create_diskfile' => '22590f5f00f124bf9897115b997b6d4d03d4362c3cd6b9a7717a8ddae47513d8',
        'Attachment.archive_attachments' => 'cef93d2c3ce9e6949fc2671b9d3fc71552570c6a425ff045d1240d9eaaa60637',
        'AttachmentsController#download' => %w[852831fc5c7f06f7e2734e83db703effcf11126fcd3ad087fb1270f41dc6d6de
                                               2b84702779a404a31ca6df44ea71503bec5ccc3ffd1e947c346950ccd68205f1],
        'AttachmentsController#thumbnail' => '597832c4b67e4b3f7aabcd8cc35fd2e4971dd43f322399a4ac6c72086f6d4fe1',
        'AttachmentsController#download_all' => '465add51609ed87930851a1606ef254e429ecd6541fd5e5563c27b365a751f43',
        'AttachmentsController#upload' => %w[bf039628848d5781ee6731f2bc7ba2e955093de87453ea27f4659d79a9ffdb08
                                             81d22f901eead6ceab8bbfe5bfd0974f9d4406dfc8c3d7d5cfba4a8592e66c9e],
        'AttachmentsController#detect_content_type' =>
          'af8f5a4f9fa115386d9c9fa29479385a8ad8175a4c583f4cfba16d154d710c9c',
        'AttachmentsController#disposition' => %w[0decc4e4ff5bcb3f0e95d8f3cb024e66b4985cda1f0b50f5b484c69a85af9d9d
                                                  6e80ed9899ef394588cca7a036ef9da07f269e37a8c1042d60889d49aeedade7],
        'Import#file=' => '9d116d41955e90e605011bf1031276df911af65d625757f1c5e86d88b83bb4db',
        'Import#file_exists?' => 'f15c3d5b959609e41ade42a05e81c868f8c5338da55150b1cd72d7c24ad01d2c',
        'Import#filepath' => 'db9251dfaa6d8784c433fc523be573f5836fa1730e9ac573b6ca442472db751f',
        'Import#remove_file' => '4660ab4540e968e5058b576672829017310570b8e88dde74034b7f3083682edd',
        'MailHandler#receive' => '6db5ad4dc00eac4c6cf68367bbc69654a58f178a9c0e57e26c1440c4e1f67f86',
        'SettingsController#plugin' => 'afe34e0132b3743946110b8feff0aaa4f5ccd72ec6dddbe9c09cf16db89ceab1'
      }.freeze

      # Code of Redmine 7.1 only, on the master branch (7519645). Avatars
      # (docs/attachments.md#avatars): update is replaced; show and
      # User#update_avatar run unchanged with the file the plugin reads from S3
      # and the thumbnails it keeps there.
      REDMINE_71_METHODS = {
        'AvatarsController#update' => '2335df066abbcc818b1d86a4febb3dd92cebcb57643aa055d289c891f5911fba',
        'AvatarsController#show' => '71036e3a205882ffe9b9f6d089c6daa138af3b619b9f5f2438eb0b6ae2c00c0e',
        'User#update_avatar' => 'aa221757e3483aaebf7043155e42656a965544c48ed805e6268479633c64d7a1',
        # The upload through CloudFront detects the type the same way.
        'Attachment#set_content_type' => '8ac3aad67464907ba5289db1afb216409f57915b00a516b369fc6a404098406d'
      }.freeze

      JAVASCRIPT = {
        'uploadBlob' => %w[b05426c4ee9c2a1c37cbcd4f8052f53028177a88c317b68f34d86e169ac77375
                           b549d9e41e35ff5fa99e14e87d047d6058c318e456e50c8868b5bf07a6abe04a]
      }.freeze

      METHODS.each do |target, sha256|
        define_method("test_#{target.tr('#.?!=', '__pbs')}") do
          assert_includes Array(sha256), Digest::SHA256.hexdigest(source_of(original_method(target))),
                          "#{target} of Redmine changed"
        end
      end

      REDMINE_71_METHODS.each do |target, sha256|
        define_method("test_#{target.tr('#.?!=', '__pbs')}") do
          skip 'Redmine 7.0 does not have this code' unless RedmineAws::S3.avatars?

          assert_equal sha256, Digest::SHA256.hexdigest(source_of(original_method(target))),
                       "#{target} of Redmine changed"
        end
      end

      JAVASCRIPT.each do |name, sha256|
        define_method("test_attachments_js_#{name}") do
          file = Rails.root.join('app/assets/javascripts/attachments.js').read
          code = file[/^function #{name}\(.*?^}\n/m]

          assert_includes Array(sha256), Digest::SHA256.hexdigest(code.to_s),
                          "#{name} in attachments.js of Redmine changed"
        end
      end

      private

      # Redmine's own method, under the plugin's prepended one.
      # 'Class#instance_method' or 'Class.class_method'.
      def original_method(target)
        klass, name = target.split('#')
        return klass.split('.').then { |owner, method| owner.constantize.method(method) } unless name

        owner = klass.constantize
        method = owner.instance_method(name)
        method = method.super_method until method.owner == owner
        method
      end

      # The lines of the method, from its def to the end at the same indentation.
      def source_of(method)
        file, line = method.source_location
        lines = File.readlines(file)[(line - 1)..]
        indent = lines.first[/\A */]
        body = lines.take_while { |text| !text.start_with?("#{indent}end") }
        (body + ["#{indent}end\n"]).join
      end
    end
  end
end
