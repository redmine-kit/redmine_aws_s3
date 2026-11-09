# frozen_string_literal: true

module RedmineServerlessS3
  # Prepended to MailHandler: attachments of received mail are not waited
  # for, because SES gives its own virus verdict (docs/attachments.md#malware-scan).
  module MailHandlerPatch
    def receive(email, options = {})
      MalwareScan.skip { super }
    end
  end
end
