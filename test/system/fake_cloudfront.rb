# frozen_string_literal: true

module RedmineServerlessS3
  # CloudFront for the system tests, in front of Redmine on the test server:
  # the paths /files/, /tmp/thumbnails/, /tmp/bulk/ (GET) and /tmp/incoming/ (PUT) go
  # to the S3 of the tests, only with a valid signed URL (canned policy,
  # checked with the public key). Downloads get the headers that the
  # distribution adds (docs/setup.md#the-cloudfront-distribution).
  class FakeCloudFront
    PATHS = %r{\A/(?:files|tmp)/}
    CLOUDFRONT_PARAMS = /[?&]Expires=.*\z/

    def initialize(app, public_key:)
      @app = app
      @public_key = public_key
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless PATHS.match?(request.path)
      return [403, { 'content-type' => 'text/plain' }, ['not signed']] unless signed?(request)

      key = request.path.delete_prefix('/').split('/').map { |part| Rack::Utils.unescape_path(part) }.join('/')
      respond(request, key)
    end

    private

    def respond(request, key)
      upload = key.start_with?(RedmineServerlessS3::INCOMING_PREFIX)
      return upload(request, key) if request.put? && upload
      return download(request, key) if request.get? && !upload

      [405, {}, []]
    rescue Aws::S3::Errors::NoSuchKey
      [404, {}, []]
    rescue Aws::S3::Errors::ServiceError => e
      [400, { 'content-type' => 'text/plain' }, [e.message]]
    end

    def upload(request, key)
      RedmineServerlessS3.client.put_object(bucket: RedmineServerlessS3.bucket, key: key, body: request.body.read)
      [200, {}, []]
    end

    def download(request, key)
      object = RedmineServerlessS3.client.get_object(bucket: RedmineServerlessS3.bucket, key: key)
      headers = {
        'content-type' => request.params['response-content-type'] || object.content_type,
        'content-disposition' => request.params['response-content-disposition'],
        'content-security-policy' => RedmineServerlessS3::ATTACHMENT_CSP,
        'x-content-type-options' => 'nosniff'
      }.compact
      [200, headers, [object.body.read]]
    end

    # The URL as Redmine signed it: https on the CloudFront domain.
    def signed?(request)
      params = Rack::Utils.parse_query(request.query_string)
      expires = params['Expires'].to_i
      signature = params['Signature'].to_s
      return false if expires < Time.now.to_i || signature.empty?

      url = "https://#{request.host_with_port}#{request.fullpath}".sub(CLOUDFRONT_PARAMS, '')
      policy = %({"Statement":[{"Resource":"#{url}","Condition":{"DateLessThan":{"AWS:EpochTime":#{expires}}}}]})
      @public_key.verify(OpenSSL::Digest.new('SHA1'), Base64.decode64(signature.tr('-_~', '+=/')), policy)
    end
  end
end
