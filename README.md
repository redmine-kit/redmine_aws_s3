# Redmine Serverless S3

A Redmine plugin that stores attachments in Amazon S3: direct uploads from the browser (presigned POST), downloads and thumbnails through presigned URLs, a `/tmp` cache, and an administration page for the bucket. It works with or without AWS Lambda; [Serverless](https://github.com/redmine-kit/serverless) uses it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless).

[日本語](README.ja.md)

> **Status:** design stage. The repository holds the design documents; nothing is implemented yet.

## Documentation

- Website: https://redmine-kit.github.io/redmine_serverless_s3/ (日本語: https://redmine-kit.github.io/redmine_serverless_s3/ja/)
- Markdown: [docs/README.md](docs/README.md) (日本語: [docs/ja/README.md](docs/ja/README.md)), with [attachments and S3](docs/attachments.md) and the [administration page](docs/admin.md)

## License

Redmine Serverless S3 is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE). Not affiliated with the Redmine project.
