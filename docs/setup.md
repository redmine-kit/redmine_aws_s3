# Setup

What a Redmine needs to use Redmine Serverless S3: installation, configuration, the bucket, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in the design stage, so the details below are the design and are checked when the code is written.

## Requirements

- Redmine 7.0 or later.
- A process that can reach S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys are stored in Redmine.
- Browsers can reach S3 over the internet, because uploads and downloads go directly between the browser and S3 ([attachments.md](attachments.md#upload)).

## Installation

1. Put the plugin in `plugins/redmine_serverless_s3` and run `bundle install` (the plugin's `Gemfile` adds `aws-sdk-s3`; Redmine's `Gemfile` loads it).
2. No migrations are needed.
3. Set the bucket (below). Without it, the plugin stays off and Redmine stores attachments on disk as standard.

## Configuration

| Setting | Where | Contents |
| --- | --- | --- |
| Bucket name and Region | Environment variables | Turn the plugin on. The variable names are decided when the code is written (not decided yet) |
| Presigned URL expiry | Plugin settings | Shown on the [administration page](admin.md#attachments-in-s3). Presigned POST for uploads expires in 15 minutes ([attachments.md](attachments.md#upload)) |
| Size of the `/tmp` cache | Plugin settings | [attachments.md](attachments.md#the-tmp-cache) |
| `attachments_storage_path` | `config/configuration.yml` | The local cache directory. On Lambda, under `/tmp` (for example `/tmp/redmine/files`) |
| Maximum attachment size | Redmine's settings | Can still be changed; the plugin shows the practical limit ([admin.md](admin.md#maximum-attachment-size)) |

## The bucket

One bucket, with the keys in [attachments.md](attachments.md#bucket-layout).

| Item | Setting |
| --- | --- |
| Versioning | Enabled. Old versions are removed after 30 days |
| Lifecycle | `incoming/` and `tmp/` after 1 day, `imports/` after 7 days, noncurrent versions after 30 days |
| Encryption | SSE-S3 (the S3 default) |
| Public access | S3 Block Public Access on. A bucket policy denies requests without TLS (`aws:SecureTransport` is `false`) |
| CORS | `POST` from Redmine's origin (for example `https://redmine.example.com`), for the presigned POST |

- **No route restriction:** Do not limit the bucket or the role to a VPC endpoint or to IP addresses (`aws:SourceVpce`, `aws:SourceIp`). Browsers use the presigned URLs from the internet, and such a condition would reject them too ([attachments.md](attachments.md#bucket-layout)).

## IAM permissions

Every process that runs Redmine with the plugin (web requests, jobs, rake) gets the same permissions on the bucket. Presigned URLs are signed with these credentials, so what a browser can do is limited by both this policy and the conditions in the signature (key, size, expiry).

| Permission | Resource | Use |
| --- | --- | --- |
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` | `files/*`, `thumbnails/*`, `imports/*`, `incoming/*`, `tmp/*` in the bucket | Storing and deleting attachments and thumbnails, presigned POST and GET, copying from `incoming/` at registration, CSV imports, zip files for downloading all attachments, the read/write check (`tmp/healthcheck/`) |
| `s3:ListBucket` | The bucket | `HeadObject` on a missing object returns 404 instead of 403. Deleting thumbnails by prefix, reconciliation, `HeadBucket` in the connection check |
| `s3:GetBucketCors` | The bucket | The direct upload check on the administration page (web requests only) |

Example policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Objects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::<bucket>/files/*",
        "arn:aws:s3:::<bucket>/thumbnails/*",
        "arn:aws:s3:::<bucket>/imports/*",
        "arn:aws:s3:::<bucket>/incoming/*",
        "arn:aws:s3:::<bucket>/tmp/*"
      ]
    },
    {
      "Sid": "Bucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketCors"],
      "Resource": "arn:aws:s3:::<bucket>"
    }
  ]
}
```

Bucket policy that denies requests without TLS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TlsOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::<bucket>", "arn:aws:s3:::<bucket>/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

## Network

| From | To | In a VPC without internet access |
| --- | --- | --- |
| Redmine | The S3 API of the bucket's Region | The S3 gateway endpoint (`com.amazonaws.<region>.s3`, free) on the subnets' route table |
| Browsers | S3 (presigned POST and GET) | Over the internet; not through the VPC |

## Tests

Redmine's standard plugin tests (`bin/rake redmine:plugins:test NAME=redmine_serverless_s3`), with S3 reproduced by the SDK's `stub_responses` in unit and functional tests, and by moto in integration and system tests. Redmine's own attachment tests also run with the plugin on ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#attachments-in-s3-redmine_serverless_s3)).
