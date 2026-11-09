# IAM permissions

Every process that runs Redmine with the plugin (web requests, jobs, rake) gets the same permissions on the bucket. Browsers do not use these credentials: uploads and downloads go through CloudFront with URLs signed by the CloudFront private key.

## Permissions

| Action | Resource | Why |
| --- | --- | --- |
| `s3:GetObject`<br>`s3:PutObject`<br>`s3:DeleteObject` | In the bucket:<br>`files/*`<br>`imports/*`<br>`tmp/*` | Storing and deleting attachments, Markdown previews and thumbnails, `HeadObject` with the checksum and copying from `tmp/incoming/` at registration, deleting uploads that do not match, CSV imports, zip files for downloading all attachments, the read/write check (`tmp/healthcheck/`) |
| `s3:GetObjectTagging` | In the bucket:<br>`tmp/incoming/*`<br>`imports/*` | Reading GuardDuty's scan result, when the malware scan is on ([attachments.md](attachments.md#malware-scan)) |
| `s3:ListBucket` | The bucket | `HeadObject` on a missing object returns 404 instead of 403. Deleting thumbnails by prefix, reconciliation, `HeadBucket` in the connection check |
| Reading the CloudFront private key | The secret that holds it (on Serverless, `ssm:GetParametersByPath` on `/<instance>/env/`, through [Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/)) | Signing CloudFront URLs |

## Example policy

For every process that runs Redmine with the plugin:

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
        "arn:aws:s3:::<bucket>/imports/*",
        "arn:aws:s3:::<bucket>/tmp/*"
      ]
    },
    {
      "Sid": "ScanResults",
      "Effect": "Allow",
      "Action": "s3:GetObjectTagging",
      "Resource": ["arn:aws:s3:::<bucket>/tmp/incoming/*", "arn:aws:s3:::<bucket>/imports/*"]
    },
    {
      "Sid": "Bucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket>"
    }
  ]
}
```

## Resource-based policies

Bucket policy that allows CloudFront through OAC:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudFrontRead",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::<bucket>/files/*",
        "arn:aws:s3:::<bucket>/tmp/thumbnails/*",
        "arn:aws:s3:::<bucket>/tmp/bulk/*"
      ],
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account>:distribution/<distribution ID>" } }
    },
    {
      "Sid": "CloudFrontUpload",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<bucket>/tmp/incoming/*",
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account>:distribution/<distribution ID>" } }
    }
  ]
}
```

Bucket policy that denies reading uploads and import files before the malware scan finds them clean, when the scan is used. Both conditions must hold for the denial, so GuardDuty's own role can still read the object to scan it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ScannedOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": ["arn:aws:s3:::<bucket>/tmp/incoming/*", "arn:aws:s3:::<bucket>/imports/*"],
      "Condition": {
        "StringNotEquals": {
          "s3:ExistingObjectTag/GuardDutyMalwareScanStatus": "NO_THREATS_FOUND",
          "aws:PrincipalArn": "arn:aws:iam::<account>:role/<GuardDuty Malware Protection role>"
        }
      }
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

## Not checked yet

- Whether CloudFront with OAC passes a PUT to `tmp/incoming/` with the checksum header, and the other items in [attachments.md](attachments.md#to-verify).
