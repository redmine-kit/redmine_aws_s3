# Administration page

This is the design of the administration page of Redmine Serverless S3. Only Redmine administrators can open it (`require_admin`). The page is the "Attachments in S3" tab under the "Serverless" item of Redmine's administration menu, which all the Redmine Serverless plugins share, whether or not [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html#the-serverless-menu) is installed.

## Attachments in S3

| Item | Contents | Source |
| --- | --- | --- |
| Settings | Bucket name, Region, CloudFront domain and key pair ID, signed URL expiry, size of the `/tmp` cache | Environment variables (display only), plugin settings (expiry, etc.). The private key is not shown |
| Read/write check | Put a check object (`tmp/healthcheck/<UUID>`), read it, and delete it | A button runs `PutObject`, `GetObject`, `DeleteObject` |
| Reconciliation | Attachments in the database that are not in S3. Objects in S3 not used by any attachment | A button runs it as a job and shows the result on the page |
| Delivery check | Put a check object, make a signed URL for it under `/tmp/bulk/`, and request it through CloudFront: it must return the object with the sandbox CSP and `nosniff`, and the same URL without the signature must be refused | A button runs it; the check object is deleted afterwards |

- **Use:** After moving attachments from an older Redmine ([migration.md](https://redmine-kit.github.io/serverless/migration.html)), reconciliation lets you check that nothing is missing.
- **Connection check:** When Redmine Serverless is installed, its connection check also calls `HeadBucket` on the attachment bucket.
- **No secrets shown:** AWS credentials are not shown. AWS APIs are called only when a button is pressed.

## Maximum attachment size

Redmine's "Maximum attachment size" (`attachment_max_size`, Administration › Settings › Files) can still be changed. The plugin adds a note on the practical limit to the settings page: uploads through CloudFront are limited by the CloudFront Function on `/incoming/*`, which must use the same value, and by what CloudFront accepts for one PUT; on Lambda, the REST API `POST /uploads.json` is limited to 1 MB ([attachments.md](attachments.md#upload)).

## Permissions

For the reconciliation job, the role that runs jobs gets permission to list the bucket. The delivery check uses the same permissions as attachments. The list is in [iam.md](iam.md).

## Tests

The page has Redmine functional tests and system tests ([testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).
