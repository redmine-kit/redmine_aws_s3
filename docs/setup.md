# Setup

What a Redmine needs to use Redmine Serverless S3: installation, configuration, the bucket, the CloudFront distribution, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in the design stage, so the details below are the design and are checked when the code is written.

## Requirements

- Redmine 7.0 or later.
- A process that can reach S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys are stored in Redmine.
- Redmine is served through a CloudFront distribution. Browsers upload and download files through it, never through the S3 domain ([attachments.md](attachments.md#upload)).

## Installation

1. Put the plugin in `plugins/redmine_serverless_s3` and run `bundle install` (the plugin's `Gemfile` adds `aws-sdk-s3`; Redmine's `Gemfile` loads it).
2. No migrations are needed.
3. Set the bucket (below). Without it, the plugin stays off and Redmine stores attachments on disk as standard.

## Configuration

| Setting | Where | Contents |
| --- | --- | --- |
| Bucket name and Region | Environment variables | Turn the plugin on |
| CloudFront domain and key pair ID | Environment variables | The domain of Redmine's distribution (for signed URLs under `/files/`, `/thumbnails/`, `/tmp/bulk/` and `/incoming/`) and the ID of the public key in its trusted key group |
| CloudFront private key | A secret (on Serverless, a SecureString parameter under `/<instance>/env/` that [Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/) reads into the environment) | Signs the CloudFront URLs. Never written to files or logs |
| Signed URL expiry | Plugin settings | Shown on the [administration page](admin.md#attachments-in-s3). 5 minutes for downloads and 15 minutes for uploads ([attachments.md](attachments.md#upload)) |
| Size of the `/tmp` cache | Plugin settings | [attachments.md](attachments.md#the-tmp-cache) |
| `attachments_storage_path` | `config/configuration.yml` | The local cache directory. On Lambda, under `/tmp` (for example `/tmp/redmine/files`) |
| Maximum attachment size | Redmine's settings | Can still be changed; the CloudFront Function on `/incoming/*` must use the same limit ([admin.md](admin.md#maximum-attachment-size)) |

- **Variable names:** The names of the environment variables are decided when the code is written (not decided yet).

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

Redmine's standard plugin tests (`bin/rake redmine:plugins:test NAME=redmine_serverless_s3`), with S3 reproduced by the SDK's `stub_responses` in unit and functional tests, and by moto in integration and system tests. Redmine's own attachment tests also run with the plugin on ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#attachments-in-s3-redmine_serverless_s3)).

## To verify

The open questions of the design are in [attachments.md](attachments.md#to-verify).
