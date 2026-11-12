# frozen_string_literal: true

module RedmineAws
  module S3
    # Uploads and saves whose conditional writes S3 refuses: shared by the
    # tests of the 412 and 409 answers.
    module ConditionalWrites
      NOW = Time.utc(2026, 11, 9, 12, 0, 0)

      def complete_upload(client)
        travel_to(NOW) { with_s3(client) { upload.complete(presign[:ticket]) } }
      end

      # CopyObject's answer as S3 sends it: S3 checks a 200 answer of CopyObject
      # for an error in its body, which stubbed data does not have.
      def copied
        { status_code: 200, headers: {},
          body: '<?xml version="1.0" encoding="UTF-8"?><CopyObjectResult><ETag>"e"</ETag></CopyObjectResult>' }
      end

      # S3's answer to a conditional write when the key has an object (412).
      def precondition_failed
        ::Aws::S3::Errors::PreconditionFailed.new(nil, 'At least one of the pre-conditions you specified did not hold')
      end

      # The params of every request of the operation, in order.
      def params_of(client, operation)
        client.api_requests.select { |request| request[:operation_name] == operation }.pluck(:params)
      end

      def create_attachment(filename)
        Attachment.create!(container: Issue.find(1), author: User.find(1),
                           file: mock_file(filename: filename, content: 'saved'))
      end

      # S3's answer to conditional writes at the same time (409).
      def conflict
        ::Aws::S3::Errors::ConditionalRequestConflict.new(nil, 'A conflicting conditional operation is in progress')
      end
    end
  end
end
