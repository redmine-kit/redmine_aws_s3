# Setup

What a Redmine needs to use Redmine Serverless S3: installation, configuration, the bucket, the CloudFront distribution, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in early development: the code below is built and tested against moto, and the parts that need a real CloudFront distribution are listed in [To verify](#to-verify).

## Requirements

- Redmine 7.0 or later.
- A process that can reach S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys are stored in Redmine.
- Redmine is served through a CloudFront distribution. Browsers upload and download files through it, never through the S3 domain ([attachments.md](attachments.md#upload)).

## Installation

**Getting the plugin:** Each version tag publishes the plugin as a gem to GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`). The first version is 0.1.0. Installing from GitHub Packages needs a GitHub token with `read:packages`, even for a public package. The gem holds the plugin's run-time files; Redmine loads plugins only from `plugins/`, so the installed gem is linked there:

```ruby
# Redmine's Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_serverless_s3'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <user>:<token>   # or the variable BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_serverless_s3)" plugins/redmine_serverless_s3
```

Without the gem, clone the repository into `plugins/redmine_serverless_s3` (`git clone https://github.com/redmine-kit/redmine_serverless_s3.git plugins/redmine_serverless_s3`).

1. Put the plugin in `plugins/redmine_serverless_s3` and run `bundle install` (the plugin's `Gemfile` and the gem add `aws-sdk-s3` and `aws-sdk-cloudfront`; Redmine's `Gemfile` loads the plugin's).
2. No migrations are needed.
3. Run `bin/rails assets:precompile` (or Redmine's usual asset step) so that the plugin's JavaScript `s3_upload.js` is served.
4. Set the environment variables (below). Without `REDMINE_S3_BUCKET`, the plugin stays off and Redmine stores attachments on disk as standard.

## Configuration

| Setting | Where | Contents |
| --- | --- | --- |
| `REDMINE_S3_BUCKET` | Environment variable | The attachment bucket. Turns the plugin on; without it, Redmine behaves as standard |
| `REDMINE_S3_REGION` | Environment variable | The bucket's Region. Optional: `AWS_REGION`, then `AWS_DEFAULT_REGION`, are used without it |
| `REDMINE_CLOUDFRONT_DOMAIN` | Environment variable | The domain of Redmine's distribution, such as `redmine.example.com`, for signed URLs under `/files/`, `/thumbnails/`, `/tmp/bulk/` and `/incoming/` |
| `REDMINE_CLOUDFRONT_KEY_PAIR_ID` | Environment variable | The ID of the public key in the distribution's trusted key group |
| `REDMINE_CLOUDFRONT_PRIVATE_KEY` | Environment variable, from a secret (on Serverless, a SecureString parameter under `/<instance>/env/` that [Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/) reads into the environment) | The private key in PEM. Signs the CloudFront URLs. Never written to files or logs, and not shown on the administration page |
| Signed URL expiry | Plugin settings, on the [administration page](admin.md#attachments-in-s3) | 300 seconds for downloads and thumbnails, 900 seconds for uploads ([attachments.md](attachments.md#upload)) |
| Size of the local cache | Plugin settings, on the administration page | 256 MB ([attachments.md](attachments.md#the-tmp-cache)) |
| `attachments_storage_path` | `config/configuration.yml` | The local cache directory. On Lambda, under `/tmp` (for example `/tmp/redmine/files`) |
| Maximum attachment size | Redmine's settings | Can still be changed; the CloudFront Function on `/incoming/*` must use the same limit ([admin.md](admin.md#maximum-attachment-size)) |

- **AWS credentials:** The S3 client uses the SDK's standard credential chain (the execution role on Lambda, an instance profile or a task role elsewhere). The plugin reads no access keys of its own.
- **Jobs:** The reconciliation on the administration page runs as the Active Job `ServerlessS3ReconcileJob`. Where jobs go through a queue with a list of allowed job classes (such as [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/)), add it to the list.

## AWS resources

### The bucket

One bucket, with the keys in [attachments.md](attachments.md#bucket-layout).

| Item | Setting |
| --- | --- |
| Versioning | Enabled. Old versions are removed after 30 days |
| Lifecycle | `incoming/` and `tmp/` after 1 day, `imports/` after 7 days, noncurrent versions after 30 days |
| Encryption | SSE-S3 (the S3 default) |
| Public access | S3 Block Public Access on. A bucket policy denies requests without TLS (`aws:SecureTransport` is `false`) |
| CORS | None. Browsers use only Redmine's domain |
| Bucket policy | Deny requests without TLS. Allow Redmine's CloudFront distribution, through its origin access control (OAC), to read `files/`, `thumbnails/` and `tmp/bulk/` and to write `incoming/` |

- **Who reaches the bucket:** CloudFront through OAC, and the roles of the processes that run Redmine. Browsers never get S3 presigned URLs.

### The CloudFront distribution

The plugin uses Redmine's own distribution; no second distribution is needed. Add these to it:

| Item | Setting |
| --- | --- |
| Origin | The attachments bucket, with an origin access control (OAC) that signs requests |
| Behaviors `/files/*`, `/thumbnails/*`, `/tmp/bulk/*` | GET and HEAD. Signed URLs required (the trusted key group below). The cache key and the origin request include the query strings `response-content-disposition` and `response-content-type`; no cookies, no `Authorization` header. A response headers policy with `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox` and `X-Content-Type-Options: nosniff` |
| Behavior `/incoming/*` | All methods (PUT is needed). Signed URLs required. No caching. The origin request forwards the `x-amz-checksum-sha256` header. A CloudFront Function on viewer request rejects a `Content-Length` over the upload limit |
| Trusted key group | A public key whose private key Redmine uses to sign URLs |
| Other behaviors | Redmine, as before. The function that adds the body hash stays on them only |

- **Redmine's paths:** Redmine has no routes that start with `/files`, `/thumbnails` or `/tmp` (checked in Redmine 7.0.3 on 2026-11-09), so these behaviors do not hide Redmine's pages ([attachments.md](attachments.md#download)).
- **The sandbox CSP must stay:** Attachments are served from Redmine's origin, and the sandbox CSP is what keeps them from running scripts there. Check after every change of the distribution that a response under `/files/` has it.
- **Creating the key pair:** The private key is created once and kept as a secret; only its public key goes into CloudFront. Serverless creates it with the deployment.

## IAM permissions

The permissions the plugin needs, with an example policy, are in [iam.md](iam.md).

## Network

| From | To | In a VPC without internet access |
| --- | --- | --- |
| Redmine | The S3 API of the bucket's Region | The S3 gateway endpoint (`com.amazonaws.<region>.s3`, free) on the subnets' route table |
| Browsers | Redmine's CloudFront distribution (uploads and downloads) | Over the internet; not through the VPC. Browsers never reach S3 directly |
| CloudFront | The bucket, through OAC | AWS's network; not through the VPC |

## Tests

Redmine's standard plugin tests (`bin/rails redmine:plugins:test NAME=redmine_serverless_s3`), in Docker with Redmine 7.0.3, PostgreSQL 16 and moto:

```sh
bin/test                 # the plugin's tests, with coverage in coverage/
bin/test core            # Redmine's own tests with the plugin installed (off)
bin/test <files...>      # some of the plugin's tests
bin/services --down      # stop PostgreSQL and moto
bin/lint                 # RuboCop
node test/javascripts/sha256_test.mjs   # the SHA-256 of the upload script
```

- **S3:** Unit and functional tests stub S3 with the SDK's `stub_responses`. Integration tests use moto. moto 5.2.5 neither checks `x-amz-checksum-sha256` nor returns `ChecksumSHA256` from `HeadObject` (checked on 2026-11-09), so the integration tests compute that `HeadObject` result from the stored bytes, and a checksum that does not match is tested with `stub_responses`.
- **Signed URLs:** The tests make a key pair and verify each signed URL with the public key.
- **Replaced code:** A test compares the SHA256 of each replaced or copied Redmine method, and of `uploadBlob` in `attachments.js`, with Redmine 7.0.3 ([attachments.md](attachments.md#replaced-code)).
- **Coverage:** `bin/test` measures the coverage of the plugin's `app/` and `lib/` with SimpleCov (Redmine's `COVERAGE`) and writes `coverage/coverage.xml` (Cobertura) and an HTML report.
- **CI:** GitHub Actions runs `bin/lint`, the SHA-256 test and `bin/test` on every push and pull request, and uploads the coverage to [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_s3) with OIDC.

## To verify

What is not checked yet is in [attachments.md](attachments.md#to-verify).
