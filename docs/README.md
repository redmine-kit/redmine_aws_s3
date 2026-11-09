# Redmine Serverless S3

Redmine Serverless S3 (`redmine_serverless_s3`) is a Redmine plugin that stores attachments in Amazon S3. Uploads go directly from the browser to S3, and downloads redirect to S3 presigned URLs, so file contents do not pass through Redmine. It does not modify Redmine's own files and uses only Redmine's standard extension mechanisms. The plugin is in the design stage, and only the documentation exists.

- [Attachments and S3](attachments.md): storage, uploads, downloads, cache, replaced code
- [Administration page](admin.md): settings, read/write check, reconciliation

## Features

| Feature | Contents | Enabled when |
| --- | --- | --- |
| S3 attachments | Storing and deleting, uploads to S3 (presigned POST), redirects to presigned URLs (downloads and thumbnails), the `/tmp` cache, CSV import files, zip files for downloading all attachments | S3 bucket settings (environment variables) exist. Without them, Redmine behaves as standard |
| Administration page | Bucket and settings, S3 read/write check, reconciliation between the database and S3 | Administrators |

- **With or without Lambda:** The plugin works in any Redmine that can reach S3. On AWS Lambda, there is no writable disk and requests are limited to 6 MB, so [Serverless](https://redmine-kit.github.io/serverless/) installs it together with [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/).
- **Gems:** Gems the plugin uses (such as `aws-sdk-s3`) go in the plugin's `Gemfile`. Redmine's `Gemfile` also loads `plugins/*/Gemfile`.
- **Tests:** Tests are written for each piece of replaced code, using Redmine's standard mechanism (`rake redmine:plugins:test`) ([testing.md](https://redmine-kit.github.io/serverless/testing.html#attachments-in-s3-redmine_serverless_s3)).
- **Migrations:** None planned.
