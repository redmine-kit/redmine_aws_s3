# Administration page

This is the design of the administration page of Redmine Serverless S3. Only Redmine administrators can open it (`require_admin`). When [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html) is installed, the page is a tab of its "Serverless" administration page. Without it, the page is an item of its own in Redmine's administration menu.

## Attachments in S3

| Item | Contents | Source |
| --- | --- | --- |
| Settings | Bucket name, Region, presigned URL expiry, size of the `/tmp` cache | Environment variables (display only), plugin settings (expiry, etc.) |
| Read/write check | Put a check object (`tmp/healthcheck/<UUID>`), read it, and delete it | A button runs `PutObject`, `GetObject`, `DeleteObject` |
| Reconciliation | Attachments in the database that are not in S3. Objects in S3 not used by any attachment | A button runs it as a job and shows the result on the page |
| Direct upload check | Whether the bucket CORS allows `POST` from Redmine's domain | `GetBucketCors` |

- **Use:** After moving attachments from an older Redmine ([migration.md](https://redmine-kit.github.io/serverless/migration.html)), reconciliation lets you check that nothing is missing.
- **Connection check:** When Redmine Serverless is installed, its connection check also calls `HeadBucket` on the attachment bucket.
- **No secrets shown:** AWS credentials are not shown. AWS APIs are called only when a button is pressed.

## Maximum attachment size

Redmine's "Maximum attachment size" (`attachment_max_size`, Administration › Settings › Files) can still be changed. The plugin adds a note on the practical limit to the settings page: uploads from the UI are limited to a size whose SHA256 can be computed within 60 seconds at registration, and on Lambda the REST API `POST /uploads.json` is limited to 1 MB ([attachments.md](attachments.md#upload)).

## Permissions

For this page, the role that runs Redmine's web requests gets permission to read the bucket CORS. For the reconciliation job, the role that runs jobs gets permission to list the bucket. Details are in [iam.md](https://redmine-kit.github.io/serverless/iam.html).

## Tests

The page has Redmine functional tests and system tests ([testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).
