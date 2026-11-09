# Redmine Serverless S3

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_serverless_s3/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_serverless_s3/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_serverless_s3)](https://codecov.io/gh/redmine-kit/redmine_serverless_s3)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_serverless_s3)](LICENSE)

添付ファイルを Amazon S3 に置く Redmine のプラグインです。Redmine の CloudFront のディストリビューションを通した、署名付き URL でのアップロードとダウンロード(アップロードは S3 が SHA256 を確認し、ダウンロードには Redmine の sandbox の CSP を付ける)、`/tmp` のキャッシュ、バケットの管理画面を持ちます。AWS Lambda でも、Lambda 以外でも動きます。[Serverless](https://github.com/redmine-kit/serverless) は、[Redmine Serverless](https://github.com/redmine-kit/redmine_serverless) といっしょに使います。

[English](README.md)

> **状態:** 開発の初期の段階です。バージョン 0.1.1 を作り、Redmine 7.0.3 と、LocalStack と moto でテストしています。本物の CloudFront のディストリビューションが要ることは、まだ確認していません([確認すること](docs/ja/attachments.md#to-verify))。

<a id="documentation"></a>

## ドキュメント

- Web サイト: https://redmine-kit.github.io/redmine_serverless_s3/ja/ (English: https://redmine-kit.github.io/redmine_serverless_s3/)
- Markdown: [docs/ja/README.md](docs/ja/README.md) (English: [docs/README.md](docs/README.md))。[準備](docs/ja/setup.md)、[IAM の権限](docs/ja/iam.md)、[添付ファイルと S3](docs/ja/attachments.md)、[管理画面](docs/ja/admin.md)があります。

<a id="license"></a>

## ライセンス

Redmine Serverless S3 は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](LICENSE) を参照してください。Redmine projectとは関係ありません。
