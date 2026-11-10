# Setup

What a Redmine needs to use Redmine Serverless S3: installation, configuration, the bucket, the CloudFront distribution, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in early development: the code below is built and tested against moto, and the parts that need a real CloudFront distribution are listed in [To verify](#to-verify).

## Requirements

- Redmine 7.0 or later.
- A process that can reach S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys are stored in Redmine.
- Redmine is served through a CloudFront distribution. Browsers upload and download files through it, never through the S3 domain ([attachments.md](attachments.md#upload)).

## Installation

1. Put the plugin in `plugins/redmine_serverless_s3`: install the gem ([Gem](#gem)) or clone the repository ([Without the gem](#without-the-gem)).
2. Run `bundle install`. Redmine's `Gemfile` loads the plugin's, and the plugin adds `aws-sdk-s3` 1.178 or later (which has the full-object checksums, `ChecksumType`) and `aws-sdk-cloudfront` 1.x.
3. No migrations are needed.
4. Build the assets, so that the plugin's JavaScript `s3_upload.js` (and `s3_avatar_upload.js` for the avatars of Redmine 7.1) is served (or use Redmine's usual asset step):

   ```sh
   bin/rails assets:precompile
   ```

5. Set the environment variables (below). Without `REDMINE_S3_BUCKET`, the plugin stays off and Redmine stores attachments on disk as standard.

### Gem

Each version tag publishes the plugin as a gem to GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`). The current version is 0.2.0. Installing from GitHub Packages needs a GitHub token with `read:packages`, even for a public package. The gem holds the plugin's run-time files. Redmine loads plugins only from `plugins/`, so the installed gem is linked there:

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

### Without the gem

Clone the repository into `plugins/redmine_serverless_s3` and install its gems:

```sh
git clone https://github.com/redmine-kit/redmine_serverless_s3.git plugins/redmine_serverless_s3
bundle install
```

## Configuration

| Key | Description | Parameter |
| --- | --- | --- |
| `REDMINE_S3_BUCKET` | The attachment bucket. Turns the plugin on; without it, Redmine behaves as standard | Required |
| `REDMINE_S3_REGION` | The bucket's Region | Optional. Default: `AWS_REGION`, then `AWS_DEFAULT_REGION` |
| `REDMINE_CLOUDFRONT_DOMAIN` | The domain of Redmine's distribution, for signed URLs under `/files/`, `/tmp/thumbnails/`, `/tmp/bulk/` and `/tmp/incoming/` | Required. Example: `redmine.example.com` |
| `REDMINE_CLOUDFRONT_KEY_PAIR_ID` | The ID of the public key in the distribution's trusted key group | Required |
| `REDMINE_CLOUDFRONT_PRIVATE_KEY` | The private key in PEM that signs the CloudFront URLs. Never written to files or logs, and not shown on the administration page | Required. A secret. On Serverless, the SSM SecureString `/<instance>/env/REDMINE_CLOUDFRONT_PRIVATE_KEY` |
| `REDMINE_S3_MALWARE_SCAN` | Waits for GuardDuty Malware Protection for S3 before using uploads and import files ([attachments.md](attachments.md#malware-scan)) | Optional. `true` turns it on; anything else, or not set: off |

| Item | Description | Where to change |
| --- | --- | --- |
| Download URL expiry, Upload URL expiry | Default: 300 seconds for downloads and thumbnails, 900 seconds for uploads ([attachments.md](attachments.md#upload)) | Plugin settings ([administration page](admin.md#attachments-in-s3)) |
| Local cache size limit | Default: 256 MB ([attachments.md](attachments.md#the-tmp-cache)) | Plugin settings (administration page) |
| `attachments_storage_path` | The local cache directory. On Lambda, under `/tmp` (for example `/tmp/redmine/files`) | `config/configuration.yml` |
| Maximum attachment size | Can still be changed; the CloudFront Function on `/tmp/*` must use the same limit for uploads ([admin.md](admin.md#maximum-attachment-size)) | Redmine's settings |

On Serverless, [Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/) reads the parameters under `/<instance>/env/` into the environment. The S3 client uses the SDK's standard credential chain: the execution role on Lambda, an instance profile or a task role elsewhere. The plugin reads no access keys of its own.

The consistency check on the administration page runs as the Active Job `ServerlessS3ReconcileJob`. If jobs go through a queue that allows only listed job classes, such as [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/), add this class to the list.

## AWS resources

### The bucket

One bucket, with the keys in [attachments.md](attachments.md#bucket-layout).

| Item | Setting |
| --- | --- |
| Versioning | Enabled. Old versions are removed after 30 days |
| Lifecycle | `tmp/incoming/`, `tmp/bulk/` and `tmp/healthcheck/` after 1 day, `imports/` after 7 days, noncurrent versions after 30 days. Thumbnails (`tmp/thumbnails/`) are not expired |
| Encryption | SSE-S3 (the S3 default) |
| Public access | S3 Block Public Access on. A bucket policy denies requests without TLS (`aws:SecureTransport` is `false`) |
| CORS | None. Browsers use only Redmine's domain |
| Bucket policy | Deny requests without TLS. Allow Redmine's CloudFront distribution, through its origin access control (OAC), to read `files/`, `tmp/thumbnails/` and `tmp/bulk/` and to write `tmp/incoming/`. With the malware scan, deny reading `tmp/incoming/` and `imports/` before the scan finds the object clean |
| Malware scan (optional) | A GuardDuty Malware Protection plan for S3 on the bucket, for the prefixes `tmp/incoming/` and `imports/`, with tagging of the scanned objects on, and `REDMINE_S3_MALWARE_SCAN=true` ([attachments.md](attachments.md#malware-scan)) |

Only CloudFront through OAC and the roles of the processes that run Redmine reach the bucket. Browsers never get S3 presigned URLs.

### The CloudFront distribution

The plugin uses Redmine's own distribution; no second distribution is needed. Add these to it:

| Item | Setting |
| --- | --- |
| Origin | The attachments bucket, with an origin access control (OAC) that signs requests |
| Behavior `/files/*` | Attachments. GET and HEAD. Signed URLs required (the trusted key group below). The managed cache policy CachingDisabled, which forwards no query string to S3, no origin request policy, and the managed response headers policy SecurityHeadersPolicy, which adds `X-Content-Type-Options: nosniff`. A CloudFront Function on viewer response adds `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox` and sets `Content-Disposition` and `Content-Type` from the query strings `response-content-disposition` and `response-content-type` ([attachments.md](attachments.md#download)) |
| Behavior `/tmp/*` | Thumbnails (`/tmp/thumbnails/`) and zips (`/tmp/bulk/`) with GET, uploads (`/tmp/incoming/`) with PUT: all methods, HTTPS only. Signed URLs required. The same policies and viewer-response function as `/files/*`. A CloudFront Function on viewer request rejects a PUT under `/tmp/incoming/` whose `Content-Length` is over the upload limit ([attachments.md](attachments.md#upload)) |
| Trusted key group | A public key whose private key Redmine uses to sign URLs |
| Other behaviors | Redmine, as before. The function that adds the body hash stays on them only |

These behaviors hide none of Redmine's pages: Redmine has no routes that start with `/files` or `/tmp` (checked in Redmine 7.0.3 on 2026-11-09; [attachments.md](attachments.md#download)).

Keep the sandbox CSP. Attachments are served from Redmine's origin, and this policy is what keeps them from running scripts there. After every change to the distribution, check that a response under `/files/` still has it.

The private key of the key pair is created once and kept as a secret; only its public key goes into CloudFront. Serverless creates the pair with the deployment.

## IAM permissions

The permissions the plugin needs, with an example policy, are in [iam.md](iam.md).

## Network

| From | To | In a VPC without internet access |
| --- | --- | --- |
| Redmine | The S3 API of the bucket's Region | The S3 gateway endpoint (`com.amazonaws.<region>.s3`, free) on the subnets' route table |
| Browsers | Redmine's CloudFront distribution (uploads and downloads) | Over the internet; not through the VPC. Browsers never reach S3 directly |
| CloudFront | The bucket, through OAC | AWS's network; not through the VPC |

## Tests

Redmine's standard plugin tests, in Docker with Redmine 7.0.3 (or Redmine's master branch with `REDMINE_BRANCH=master`), PostgreSQL 16, and S3 from LocalStack when `LOCALSTACK_AUTH_TOKEN` is set or from moto otherwise (`bin/test` prints which):

```sh
bin/test                 # the plugin's tests, with coverage in coverage/
bin/test core            # Redmine's own tests with the plugin installed (off)
bin/test core-s3         # Redmine's attachment tests with the plugin on
bin/test system          # the system tests, in headless Chromium
bin/test <files...>      # some of the plugin's tests
REDMINE_BRANCH=master bin/test   # on Redmine's master branch (7.1, with avatars)
bin/services --system --down   # stop PostgreSQL, moto, LocalStack and Chromium
bin/lint                 # RuboCop
node test/javascripts/complete_test.mjs # the upload script's complete step
node test/javascripts/avatar_check_test.mjs # the avatar script's check step
```

### How AWS is tested

Unit and functional tests stub S3 with the SDK's `stub_responses`. Integration tests run the same suite on LocalStack in CI, with the organization's token, and on moto for pull requests from forks and local runs without the token. moto 5.2.5 does not return `ChecksumSHA256` from `HeadObject` (checked on 2026-11-09), so on moto the tests compute that `HeadObject` result from the stored bytes and skip the two tests of S3's checksums. For signed URLs, the tests make a key pair and verify each URL with the public key. LocalStack 2026.10.6 sometimes answers a request on a reused connection with `400` and no body when several test processes send at once (about 1 in 1,000 PutObject with 4 processes, none with new connections; reproduced on 2026-11-11), which S3 does not do, so the tests' S3 client keeps no idle connections (`http_idle_timeout: 0`).

### Replaced code, coverage and CI

A test compares the SHA256 of each replaced or copied Redmine method, and of `uploadBlob` in `attachments.js`, with Redmine 7.0.3 ([attachments.md](attachments.md#replaced-code)). `bin/test` measures the coverage of the plugin's `app/` and `lib/` with SimpleCov (Redmine's `COVERAGE`) and writes `coverage/coverage.xml` (Cobertura) and an HTML report. On every push and pull request, GitHub Actions runs `bin/lint`, the SHA-256 test and `bin/test`, and uploads the coverage to [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_s3) with OIDC. The tests also run on Redmine's master branch, which is not pinned and does not fail the run; there the avatar tests run, and the test of the replaced code shows which methods master has changed.

### What the tests check

Every piece of replaced code has tests, and every call to AWS is tested in this repository: with `stub_responses` for each answer S3 can give, and against LocalStack or moto for the real requests (PutObject, HeadObject with `ChecksumMode`, CopyObject, DeleteObjects, ListObjectsV2, GetObjectTagging with the tags GuardDuty would put, PutObjectTagging set by the tests).

| Target | What is checked | With |
| --- | --- | --- |
| `files_to_final_location` | Uploads through Redmine (REST API, forms) are put to `files/<year>/<month>/` with a SHA256 checksum, the digest stays SHA256, and a failed PutObject stops the save. With the malware scan, the file goes through `tmp/incoming/` and a threat is a validation error | Stubs, LocalStack or moto |
| `readable?`<br>`diskfile` | The local file is used when it is there; otherwise `HeadObject`, and `diskfile` fetches the object through a temporary file and a rename. New records fetch nothing | Stubs, LocalStack or moto |
| `delete_from_disk!`<br>`reuse_existing_file_if_possible` | The object and its thumbnails are deleted, but not a file another attachment uses. Identical content (digest and size) is shared and the newer object deleted | Stubs, LocalStack or moto |
| `thumbnail`<br>`thumbnailable?` | A thumbnail in S3 is used; otherwise it is made from the cached file with ImageMagick and put to `tmp/thumbnails/`, a cropped one under its own name. No thumbnail beyond the cache size. The redirect has `Cache-Control` | Stubs, LocalStack or moto |
| Avatars (Redmine 7.1) | Through CloudFront: an image of a few KB and one over 1 MB become the user's avatar, with the image in `files/`, the 100 px cropped thumbnail in `tmp/thumbnails/` and the upload deleted; the form without JavaScript; an administrator uploading for another user, and a user who is not one refused; another user's ticket and a file that is not an image refused with Redmine's message; replacing and deleting delete the old objects in S3. Showing: the cropped thumbnail from S3 without reading the image, not the image itself, the key checked, `Cache-Control` public, or private when login is required. With the malware scan: `202` from the check, and a form error for a file sent without JavaScript. On Redmine 7.0 nothing of it is there | LocalStack or moto |
| `/s3_uploads/presign` | Permission, extension and size are checked; the URL is a CloudFront signed URL for exactly `/tmp/incoming/<UUID>`, verified with the public key | Stubs |
| `/s3_uploads/complete` | The ticket must be valid, unexpired and the user's. The upload is copied to `files/` with `ChecksumAlgorithm` `SHA256` and deleted; the copy's `ChecksumSHA256` (`FULL_OBJECT`) becomes the digest, and its `ContentLength` must equal the declared size, otherwise the copy is deleted. Identical content is shared and the extra copy deleted. With the malware scan: `202` while there is no tag; for `THREATS_FOUND` and the other scan results, the file is blocked and deleted. The content type is the declared one on Redmine 7.0 and the one detected from the start of the copy on 7.1. The same through the REST API | Stubs, LocalStack or moto |
| `download`<br>`download_all` | Redmine's permission checks, then a redirect to a signed URL with `response-content-disposition` (Japanese names) and `response-content-type`; only PDFs inline (on Redmine 7.1, only with `?disposition=inline`, and a PDF compatible file as `application/pdf`). The zip is written to `/tmp` one file at a time, put to `tmp/bulk/` and reused for the same set | Stubs, LocalStack or moto |
| CSV import | The file is put to `imports/` and fetched in an environment that does not have it; with the malware scan, read only when clean | Stubs, LocalStack or moto |
| Administration tab | Settings, read/write test, delivery test (the CSP and `nosniff` headers, the unsigned URL denied), consistency check job, files blocked by the malware scan; administrators only; "Configure" opens the tab | Stubs, LocalStack or moto |
| Replaced Redmine code | The SHA256 of each replaced or copied method and of `uploadBlob` equals Redmine 7.0.3's, or master's for the methods master has changed. On master, also `AvatarsController#update`, `#show`, `User#update_avatar` and `Attachment#set_content_type` | — |
| Browser (system tests) | In headless Chromium (Selenium, in its own container): an upload through CloudFront with the progress bar going up to 100, the token in the form and the file in S3; `202` while the malware scan has no result, then the upload completes; a download following the redirect gets the file with the sandbox CSP and `nosniff`; the thumbnail of an uploaded image is shown; on Redmine 7.1, an avatar over 1 MB goes through CloudFront, the form reaches Redmine with the ticket and without the file, and an upload error is shown above the form. CloudFront is replaced by a small Rack application on the test server that checks the signed URL with the public key, PUTs to and GETs from the S3 of the tests and adds the distribution's response headers (`test/system/fake_cloudfront.rb`) | LocalStack or moto |
| Browser script | SHA-256 against known vectors and Node.js's crypto, fed in random pieces; `complete` sent again on `202` and given up after the last retry; the same for the avatar's `check` | Node.js |

### Not checked against AWS

On LocalStack, the tests check that a copy with `ChecksumAlgorithm` `SHA256` gets the SHA256 of the whole object, from a single PUT and from a multipart upload; on moto they are skipped and covered by stubs. CloudFront (signed URLs accepted, OAC, the functions) and GuardDuty are not reproduced locally. They are listed in [To verify](attachments.md#to-verify) and in the checks after deployment of [Serverless](https://redmine-kit.github.io/serverless/testing.html#checks-after-deployment).

### Redmine's own tests

`bin/test core` runs Redmine's tests with the plugin installed and off. In the full run on 2026-11-10 (5,832 tests), the 7 failures were the gem-related ones listed in Serverless (`:match` in rails-dom-testing). The 8 errors came from the order of Redmine's own tests: `Redmine::PluginTest` does not restore the plugin directory, so after `RoutingPluginsTest` the installed plugins' routes are gone while their menu items stay. These 8 tests pass when run on their own (2026-11-10).

`bin/test core-s3` runs Redmine's attachment tests (`test/unit/attachment_test.rb`, `test/unit/attachment_transaction_test.rb`, `test/functional/attachments_controller_test.rb`, `test/functional/attachments_visibility_test.rb`, `test/integration/attachments_test.rb`, `test/integration/api_test/attachments_test.rb`) with the plugin on, against LocalStack or moto. 138 tests pass (2026-11-10). The 17 left out expect Redmine to send the file itself (downloads, thumbnails, "download all", `X-Sendfile`), which the plugin replaces with redirects, or a thumbnail that an earlier test already stored in S3. On Redmine's master branch (7519645), 149 pass and 5 more are left out for the same reasons (Redmine 7.1's tests of the inline PDF and of a thumbnail timeout). Each parallel worker uses its own bucket, as it has its own attachments directory. [`test/core/s3_exclusions.txt`](../test/core/s3_exclusions.txt) gives the reason for each.

## To verify

What is not checked yet is in [attachments.md](attachments.md#to-verify).
