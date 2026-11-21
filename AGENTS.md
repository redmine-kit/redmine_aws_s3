# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine Kit AWS S3 (`redmine_kit_aws_s3`) is a Redmine plugin that stores attachments in Amazon S3. It works with or without AWS Lambda. It requires [redmine_kit_aws](https://github.com/redmine-kit/redmine_aws), which holds the "AWS" administration menu and what the AWS plugins share. [Serverless](https://github.com/redmine-kit/serverless) installs it together with [redmine_kit_aws_lambda](https://github.com/redmine-kit/redmine_aws_lambda). It is in early development.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** without the S3 bucket settings, Redmine behaves as standard.
- **Replaced code:** when Redmine code is replaced, update the table of [replaced code](docs/attachments.md#replaced-code). When Redmine is upgraded, check that the original code in that table has not changed.
- **Shared parts in redmine_kit_aws:** the administration menu, the connection check of the Status tab and the test support come from redmine_kit_aws ([its API](https://github.com/redmine-kit/redmine_aws/blob/main/docs/api.md)). What every AWS plugin needs goes there, not here.
- **Code layout:** `lib/redmine_kit/aws/s3.rb` and `lib/redmine_kit/aws/s3/` hold `RedmineKit::Aws::S3`, in the namespace that redmine_kit_aws defines (Redmine autoloads them with Zeitwerk; `test/unit/namespace_test.rb` runs `bin/rails zeitwerk:check`). Inside it, the AWS SDK is written `::Aws::S3`, `::Aws::CloudFront`. `init.rb` calls `RedmineKit::Aws::S3.setup`.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`rake redmine:plugins:test`; `bin/test` runs them in a container (Apple container, else Docker) with redmine_kit_aws from `../redmine_kit_aws` or `REDMINE_KIT_AWS_DIR`). What the tests check is in [setup.md](docs/setup.md#what-the-tests-check).
- **Keep digests SHA256:** attachment tokens, ETags, thumbnails and the sharing of identical content rely on them.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **One language per document.** The English documents are in English only and name the UI with the English locale's strings (Redmine's and this plugin's `config/locales/en.yml`); Japanese appears only in the link to the translation, a strings table's `ja` column or a value an example must match (`../AGENTS.md` › Writing › Translations).
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_aws_s3/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine Kit AWS plugin; IAM permissions there is one line that points to `docs/iam.md`), `docs/iam.md` the sections Permissions, Example policy, Resource-based policies and Not checked yet. Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.

## Development environment

- **Apple container first, Docker too** (a public repository). Scripts (`bin/test`, databases, emulators) use Apple container (`container`) when it is installed and running, else Docker (other machines, CI); `CONTAINER_CLI=docker|container` chooses. Docs give both, Apple container first. Images are built from the `Dockerfile` with either tool. In Apple container, the test containers run on the networks that every repository shares, `redmine-kit-test` and `redmine-kit-test-internal` (no way out), each with an anchor container that runs all the time (`ensure_shared_network` in `bin/container_cli`; apple/container#2051, until macOS 27.3; the organization's `../AGENTS.md`). Docker keeps a Compose network per repository.
- **Libraries at their latest versions.** Dependencies are kept at their latest stable releases, pinned exactly in the lockfiles; a version held back has its reason next to the pin.
- Both are the organization's rules (`../AGENTS.md`, "Development environment").
