# frozen_string_literal: true

module RedmineAws
  module S3
    # Rails logs "Redirected to <location>". A CloudFront signed URL that the
    # plugin redirects to opens a private file for anyone until it expires,
    # so every signed URL (its Key-Pair-Id parameter, whatever the domain) is
    # logged as [FILTERED]: config.filter_redirect is the array that Rails
    # reads at each request.
    module LogFilter
      # The query parameter of every CloudFront signed URL.
      SIGNED_URL = /[?&]Key-Pair-Id=/

      module_function

      # Called from setup, so on every code reload: adds the filter once.
      def install
        filters = Rails.application.config.filter_redirect
        filters << SIGNED_URL unless filters.include?(SIGNED_URL)
      end
    end
  end
end
