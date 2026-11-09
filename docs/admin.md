# Administration page

This is the administration page of Redmine Serverless S3. Only Redmine administrators can open it (`require_admin`). The page is the "Attachments in S3" tab under the "Serverless" item of Redmine's administration menu, which all the Redmine Serverless plugins share, whether or not [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html#the-serverless-menu) is installed.

## Attachments in S3

![The Attachments in S3 tab after Check reading and writing: the environment, the settings, the results of the check, a malware finding and the last reconciliation](./images/s3-admin.png)

| Item | Contents | Source |
| --- | --- | --- |
| Environment variables | Bucket name, Region, CloudFront domain and key pair ID, whether the private key is set, the local cache directory | Environment variables ([setup.md](setup.md#configuration)), display only. The private key itself is not shown |
| Settings | Expiry of download and upload URLs (seconds), size of the local cache (MB) | Plugin settings, changed on the page. Positive whole numbers only |
| Malware scan | Whether `REDMINE_S3_MALWARE_SCAN` is on, and the files the scan refused (the last 20: time, status, file name, user) | The environment variable; the findings are kept in the plugin settings |
| Read/write check | Put a check object (`tmp/healthcheck/<UUID>`), read it, and delete it | A button runs `PutObject`, `GetObject`, `DeleteObject` |
| Reconciliation | The numbers of attachment files in the database and of objects under `files/`; the files that are not in S3 and the objects that no attachment uses (the first 100 of each) | A button starts the job `ServerlessS3ReconcileJob`, which lists `files/`. The result is kept in the plugin settings, so every environment shows the latest one |
| Delivery check | Put a check object, make a signed URL for it under `/tmp/bulk/`, and request it through CloudFront: it must return the object with the sandbox CSP and `nosniff`, and the same URL without the signature must be refused | A button runs it; the check object is deleted afterwards |

- **Use:** After moving attachments from an older Redmine ([migration.md](https://redmine-kit.github.io/serverless/migration.html)), reconciliation lets you check that nothing is missing.
- **Connection check:** When Redmine Serverless is installed, its connection check also calls `HeadBucket` on the attachment bucket.
- **No secrets shown:** AWS credentials and the CloudFront private key are not shown. AWS APIs are called only when a button is pressed.
- **Without the bucket:** The tab still opens and shows that `REDMINE_S3_BUCKET` is not set; the buttons are not shown.
- **Operations are logged:** Changing the settings, the checks and the reconciliation are written to Redmine's log with the administrator's login.

## The Serverless menu

Every Redmine Serverless plugin ships the same small shared part: `lib/redmine_serverless_admin.rb` (`RedmineServerlessAdmin`), `ServerlessAdminController` (`/admin/serverless`, which opens the first tab) and the view `serverless_admin/_tabs`. Rails loads the first copy and ignores the others, so the "Serverless" item of Redmine's administration menu is added once, whichever plugins are installed. This plugin registers its tab, "Attachments in S3", at position 50 (the last), and, when the bucket is set, an S3 check (`HeadBucket`) for the connection check of [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html#the-serverless-menu).

- **Configure:** "Configure" of the plugin in Redmine's plugin list opens this tab.

## Maximum attachment size

Redmine's "Maximum attachment size" (`attachment_max_size`, Administration › Settings › Files) can still be changed. When the plugin is on, it adds a note on the practical limit next to the setting, with a small script on the settings page: uploads through CloudFront are limited by the CloudFront Function on `/tmp/*` (uploads under `/tmp/incoming/`), which must use the same value, and by what CloudFront accepts for one PUT; on Lambda, the REST API `POST /uploads.json` is limited to 1 MB ([attachments.md](attachments.md#upload)).

## Permissions

For the reconciliation job, the role that runs jobs gets permission to list the bucket. The delivery check uses the same permissions as attachments. The list is in [iam.md](iam.md).

## Tests

The page has Redmine functional tests; system tests are not written yet ([testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).

The screenshot on this page is taken with `bin/screenshots` (headless Chromium in Docker, with Redmine's test data and the S3 of the tests; the bucket, the CloudFront values, the finding and the reconciliation are examples). Run it after changing the page.
