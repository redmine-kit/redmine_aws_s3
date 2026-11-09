# Setup

What a Redmine needs to use Redmine Serverless S3: installation, configuration, the bucket, the CloudFront distribution, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in early development: the code below is built and tested against moto, and the parts that need a real CloudFront distribution are listed in [To verify](#to-verify).

## Requirements

- Redmine 7.0 or later.
- A process that can reach S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys are stored in Redmine.
- Redmine is served through a CloudFront distribution. Browsers upload and download files through it, never through the S3 domain ([attachments.md](attachments.md#upload)).

## Installation

**Getting the plugin:** Each version tag publishes the plugin as a gem to GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`). The current version is 0.1.1. Installing from GitHub Packages needs a GitHub token with `read:packages`, even for a public package. The gem holds the plugin's run-time files; Redmine loads plugins only from `plugins/`, so the installed gem is linked there:

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

1. Put the plugin in `plugins/redmine_serverless_s3` and run `bundle install` (the plugin's `Gemfile` and the gem add `aws-sdk-s3` 1.178 or later, which has the full-object checksums (`ChecksumType`), and `aws-sdk-cloudfront` 1.x; Redmine's `Gemfile` loads the plugin's).
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
| `REDMINE_S3_MALWARE_SCAN` | Environment variable | `true` to wait for GuardDuty Malware Protection for S3 before using uploads and import files ([attachments.md](attachments.md#malware-scan)). Anything else, or not set: off |
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
| Bucket policy | Deny requests without TLS. Allow Redmine's CloudFront distribution, through its origin access control (OAC), to read `files/`, `thumbnails/` and `tmp/bulk/` and to write `incoming/`. With the malware scan, deny reading `incoming/` and `imports/` before the scan finds the object clean |
| Malware scan (optional) | A GuardDuty Malware Protection plan for S3 on the bucket, for the prefixes `incoming/` and `imports/`, with tagging of the scanned objects on, and `REDMINE_S3_MALWARE_SCAN=true` ([attachments.md](attachments.md#malware-scan)) |

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

Redmine's standard plugin tests, in Docker with Redmine 7.0.3, PostgreSQL 16, and S3 from LocalStack when `LOCALSTACK_AUTH_TOKEN` is set or from moto otherwise (`bin/test` prints which):

```sh
bin/test                 # the plugin's tests, with coverage in coverage/
bin/test core            # Redmine's own tests with the plugin installed (off)
bin/test core-s3         # Redmine's attachment tests with the plugin on
bin/test system          # the system tests, in headless Chromium
bin/test <files...>      # some of the plugin's tests
bin/services --system --down   # stop PostgreSQL, moto, LocalStack and Chromium
bin/lint                 # RuboCop
node test/javascripts/sha256_test.mjs   # the SHA-256 of the upload script
```

- **S3:** Unit and functional tests stub S3 with the SDK's `stub_responses`. Integration tests run the same suite on LocalStack (in CI, with the organization's token) or on moto (pull requests from forks, local runs without the token). moto 5.2.5 neither checks `x-amz-checksum-sha256` nor returns `ChecksumSHA256` from `HeadObject` (checked on 2026-11-09), so on moto the tests compute that `HeadObject` result from the stored bytes and skip the two tests of these S3 checks.
- **Signed URLs:** The tests make a key pair and verify each signed URL with the public key.
- **Replaced code:** A test compares the SHA256 of each replaced or copied Redmine method, and of `uploadBlob` in `attachments.js`, with Redmine 7.0.3 ([attachments.md](attachments.md#replaced-code)).
- **Coverage:** `bin/test` measures the coverage of the plugin's `app/` and `lib/` with SimpleCov (Redmine's `COVERAGE`) and writes `coverage/coverage.xml` (Cobertura) and an HTML report.
- **CI:** GitHub Actions runs `bin/lint`, the SHA-256 test and `bin/test` on every push and pull request, and uploads the coverage to [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_s3) with OIDC.

### What the tests check

Every piece of replaced code has tests, and every call to AWS is tested in this repository: with `stub_responses` for each answer S3 can give, and against LocalStack or moto for the real requests (PutObject, HeadObject with `ChecksumMode`, CopyObject, DeleteObjects, ListObjectsV2, GetObjectTagging with the tags GuardDuty would put, PutObjectTagging set by the tests).

| Target | What is checked | With |
| --- | --- | --- |
| `files_to_final_location` | Uploads through Redmine (REST API, forms) are put to `files/<year>/<month>/` with a SHA256 checksum, the digest stays SHA256, and a failed PutObject stops the save. With the malware scan, the file goes through `incoming/` and a threat is a validation error | Stubs, LocalStack or moto |
| `readable?`, `diskfile` | The local file is used when it is there; otherwise `HeadObject`, and `diskfile` fetches the object through a temporary file and a rename. New records fetch nothing | Stubs, LocalStack or moto |
| `delete_from_disk!`, `reuse_existing_file_if_possible` | The object and its thumbnails are deleted, but not a file another attachment uses. Identical content (digest and size) is shared and the newer object deleted | Stubs, LocalStack or moto |
| `thumbnail`, `thumbnailable?` | A thumbnail in S3 is used; otherwise it is made from the cached file with ImageMagick and put to `thumbnails/`. No thumbnail beyond the cache size. The redirect has `Cache-Control` | Stubs, LocalStack or moto |
| `/s3_uploads/presign` | Permission, extension, size and SHA256 format are checked; the URL is a CloudFront signed URL for exactly `/incoming/<UUID>`, verified with the public key | Stubs |
| `/s3_uploads/complete` | The ticket must be valid, unexpired and the user's. `ChecksumSHA256` (`FULL_OBJECT`) and `ContentLength` must equal the declared values, otherwise the object is deleted. Identical content is shared. With the malware scan: `202` while there is no tag, refusal and deletion for `THREATS_FOUND` and the other statuses. The same through the REST API | Stubs, LocalStack or moto |
| `download`, `download_all` | Redmine's permission checks, then a redirect to a signed URL with `response-content-disposition` (Japanese names) and `response-content-type`; only PDFs inline. The zip is written to `/tmp` one file at a time, put to `tmp/bulk/` and reused for the same set | Stubs, LocalStack or moto |
| CSV import | The file is put to `imports/` and fetched in an environment that does not have it; with the malware scan, read only when clean | Stubs, LocalStack or moto |
| Administration tab | Settings, read/write check, delivery check (the CSP and `nosniff` headers, the unsigned URL refused), reconciliation job, malware findings; administrators only; "Configure" opens the tab | Stubs, LocalStack or moto |
| Replaced Redmine code | The SHA256 of each replaced or copied method and of `uploadBlob` equals Redmine 7.0.3's | — |
| Browser (system tests) | In headless Chromium (Selenium, in its own container): an upload through CloudFront with the progress bar going up to 100, the token in the form and the file in S3; `202` while the malware scan has no result, then the upload completes; a download following the redirect gets the file with the sandbox CSP and `nosniff`; the thumbnail of an uploaded image is shown. CloudFront is replaced by a small Rack application on the test server that checks the signed URL with the public key, PUTs to and GETs from the S3 of the tests and adds the distribution's response headers (`test/system/fake_cloudfront.rb`) | LocalStack or moto |
| Browser script | SHA-256 against known vectors and Node.js's crypto, fed in random pieces; `complete` sent again on `202` and given up after the last retry | Node.js |

- **Not checked against AWS:** On LocalStack, the tests check that S3 refuses a PUT whose contents do not match `x-amz-checksum-sha256` and returns the full-object checksum; on moto they are skipped and covered by stubs. CloudFront (signed URLs accepted, OAC, the response headers policy) and GuardDuty are not reproduced locally. These are in [To verify](attachments.md#to-verify) and in the checks after deployment of [Serverless](https://redmine-kit.github.io/serverless/testing.html#checks-after-deployment).
- **Redmine's own tests:** `bin/test core` runs Redmine's tests with the plugin installed and off. In the full run on 2026-11-10 (5,832 tests), the 7 failures were the gem-related ones listed in Serverless (`:match` in rails-dom-testing), and 8 errors came from the order of Redmine's own tests: `Redmine::PluginTest` does not restore the plugin directory, so after `RoutingPluginsTest` the installed plugins' routes are gone while their menu items stay. The 8 tests pass when run on their own (2026-11-10).
- **Redmine's attachment tests with the plugin on:** `bin/test core-s3` runs Redmine's attachment tests (`test/unit/attachment_test.rb`, `test/unit/attachment_transaction_test.rb`, `test/functional/attachments_controller_test.rb`, `test/functional/attachments_visibility_test.rb`, `test/integration/attachments_test.rb`, `test/integration/api_test/attachments_test.rb`) with the plugin on, against LocalStack or moto. 140 tests pass (2026-11-10). The 15 left out expect Redmine to send the file itself (downloads, thumbnails, "download all", `X-Sendfile`), which the plugin replaces with redirects, or a thumbnail that an earlier test already stored in S3; [`test/core/s3_exclusions.txt`](../test/core/s3_exclusions.txt) lists each with the reason.

## To verify

What is not checked yet is in [attachments.md](attachments.md#to-verify).
