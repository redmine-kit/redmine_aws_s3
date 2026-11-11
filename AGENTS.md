# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine AWS S3 (`redmine_aws_s3`) is a Redmine plugin that stores attachments in Amazon S3. It works with or without AWS Lambda. It requires [redmine_aws](https://github.com/redmine-kit/redmine_aws), which holds the "AWS" administration menu and what the AWS plugins share. [Serverless](https://github.com/redmine-kit/serverless) installs it together with [redmine_aws_lambda](https://github.com/redmine-kit/redmine_aws_lambda). It is in early development.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** without the S3 bucket settings, Redmine behaves as standard.
- **Replaced code:** when Redmine code is replaced, update the table of [replaced code](docs/attachments.md#replaced-code). When Redmine is upgraded, check that the original code in that table has not changed.
- **Shared parts in redmine_aws:** the administration menu, the connection check of the Status tab and the test support come from redmine_aws ([its API](https://github.com/redmine-kit/redmine_aws/blob/main/docs/api.md)). What every AWS plugin needs goes there, not here.
- **Code layout:** `lib/redmine_aws/s3.rb` and `lib/redmine_aws/s3/` hold `RedmineAws::S3`, in the namespace that redmine_aws defines (Redmine autoloads them with Zeitwerk; `test/unit/namespace_test.rb` runs `bin/rails zeitwerk:check`). Inside it, the AWS SDK is written `::Aws::S3`, `::Aws::CloudFront`. `init.rb` calls `RedmineAws::S3.setup`.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`rake redmine:plugins:test`; `bin/test` runs them in Docker with redmine_aws from `../redmine_aws` or `REDMINE_AWS_DIR`). The test plan is in Serverless ([setup.md](docs/setup.md#what-the-tests-check)).
- **Keep digests SHA256:** attachment tokens, ETags, thumbnails and the sharing of identical content rely on them.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_aws_s3/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine AWS plugin; IAM permissions there is one line that points to `docs/iam.md`), `docs/iam.md` the sections Permissions, Example policy, Resource-based policies and Not checked yet. Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.
