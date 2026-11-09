# Redmine Serverless S3

Redmine Serverless S3 (`redmine_serverless_s3`) is a Redmine plugin that stores attachments in Amazon S3. Uploads are PUT from the browser through Redmine's CloudFront distribution to S3, and downloads redirect to CloudFront signed URLs on Redmine's domain, so file contents do not pass through Redmine. It does not modify Redmine's own files and uses only Redmine's standard extension mechanisms. The plugin is in early development (version 0.1.1).

- [Setup](setup.md): requirements, installation, configuration, AWS resources (the bucket, the CloudFront distribution), network, tests
- [IAM permissions](iam.md): permissions, example policy, resource-based policies
- [Attachments and S3](attachments.md): storage, uploads, downloads, cache, replaced code
- [Administration page](admin.md): settings, read/write check, reconciliation

## Features

| Feature | Contents | Enabled when | Page |
| --- | --- | --- | --- |
| S3 attachments | Storing and deleting, uploads through CloudFront to S3 (PUT with a checksum that S3 checks), redirects to CloudFront signed URLs with the sandbox CSP (downloads and thumbnails), the `/tmp` cache, CSV import files, zip files for downloading all attachments, an optional wait for GuardDuty's malware scan | `REDMINE_S3_BUCKET` is set, with the CloudFront settings ([setup.md](setup.md#configuration)). Without it, Redmine behaves as standard | [attachments.md](attachments.md) |
| Administration page | The "Attachments in S3" tab under the shared "Serverless" menu: bucket and settings, S3 read/write check, delivery check through CloudFront, reconciliation between the database and S3 | Administrators | [admin.md](admin.md) |

- **With or without Lambda:** The plugin works in any Redmine that can reach S3 and is served through CloudFront. On AWS Lambda, there is no writable disk and requests are limited to 6 MB, so [Serverless](https://redmine-kit.github.io/serverless/) installs it together with [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/).
- **Gems:** `aws-sdk-s3` and `aws-sdk-cloudfront`, in the plugin's `Gemfile` and the gem's dependencies. Redmine's `Gemfile` also loads `plugins/*/Gemfile`.
- **Tests:** Tests are written for each piece of replaced code, using Redmine's standard mechanism (`rake redmine:plugins:test`) ([setup.md](setup.md#what-the-tests-check)).
- **Migrations:** None.

## Sponsors

<Sponsors><a href="https://localstack.cloud">LocalStack</a></Sponsors>

## License

Redmine Serverless S3 is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](../LICENSE). An unofficial Redmine plugin.
