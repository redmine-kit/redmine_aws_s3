# frozen_string_literal: true

module RedmineAws
  module S3
    # The arguments of Upload#presign from the request parameters of
    # S3UploadsController and S3AvatarUploadsController. Strings only: a hash
    # or an array in place of one is dropped and refused as missing, instead
    # of being turned into text.
    module PresignParams
      NAMES = %i[filename size content_type].freeze

      module_function

      def from(params)
        permitted = params.permit(*NAMES)
        NAMES.index_with { |name| permitted[name] }
      end
    end
  end
end
