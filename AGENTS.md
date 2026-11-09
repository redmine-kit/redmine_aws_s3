# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine Serverless S3 (`redmine_serverless_s3`) is a Redmine plugin that stores attachments in Amazon S3. It works with or without AWS Lambda. [Serverless](https://github.com/redmine-kit/serverless) installs it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless). It is in the design stage: the repository holds the design documents.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** without the S3 bucket settings, Redmine behaves as standard.
- **Replaced code:** when Redmine code is replaced, update the table of [replaced code](docs/attachments.md#replaced-code). When Redmine is upgraded, check that the original code in that table has not changed.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`rake redmine:plugins:test`). The test plan is in Serverless ([testing.md](https://github.com/redmine-kit/serverless/blob/main/docs/testing.md#attachments-in-s3)).
- **Keep digests SHA256:** attachment tokens, ETags, thumbnails and the sharing of identical content rely on them.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_serverless_s3/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine Serverless plugin). Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.
