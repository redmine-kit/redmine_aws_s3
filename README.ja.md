# Redmine Serverless S3

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_serverless_s3/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_serverless_s3/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_serverless_s3?label=Coverage)](https://codecov.io/gh/redmine-kit/redmine_serverless_s3)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_serverless_s3?label=License)](LICENSE)
[![Tested with LocalStack](https://img.shields.io/badge/Tested%20with-LocalStack-39227A?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9Ii0wLjM4IC0wLjAwIDg4Ljg4IDg4Ljg4Ij48cGF0aCBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGNsaXAtcnVsZT0iZXZlbm9kZCIgZD0iTTc2LjI5ODMgNjEuODcyN0M3Ny4zMDA2IDYxLjg3MjcgNzcuODAyNSA2My4wODQ1IDc3LjA5MzggNjMuNzkzMkw1Mi43MTYzIDg4LjE2ODhDNTIuMDA3NiA4OC44Nzc1IDUwLjc5NTcgODguMzc1NiA1MC43OTU3IDg3LjM3MzRMNTAuNzk1NyA2Mi45OTc3QzUwLjc5NTcgNjIuMzc2NCA1MS4yOTk0IDYxLjg3MjcgNTEuOTIwOCA2MS44NzI3TDc2LjI5ODMgNjEuODcyN1pNMS4xMjczMiAzOC45MDM2QzAuMTI1MDIgMzguOTAzNiAtMC4zNzY5MzMgMzcuNjkxOCAwLjMzMTgwNyAzNi45ODMyTDI0LjcwOTMgMTIuNjA3NUMyNS40MTggMTEuODk4OCAyNi42Mjk4IDEyLjQwMDcgMjYuNjI5OCAxMy40MDI5TDI2LjYyOTggMzcuNzc4NkMyNi42Mjk4IDM4LjM5OTkgMjYuMTI2MSAzOC45MDM2IDI1LjUwNDggMzguOTAzNkwxLjEyNzMyIDM4LjkwMzZaIiBmaWxsPSJ1cmwoI3BhaW50MF9saW5lYXJfMjBfMykiLz48cGF0aCBkPSJNNTQuMTkzNCAzNC45MDI5TDg2Ljg0ODkgMzQuOTAyOUM4Ny40NzAyIDM0LjkwMjkgODcuOTczOSAzNC4zOTkzIDg3Ljk3MzkgMzMuNzc4TDg3Ljk3MzkgMS4xMjQ4OEM4Ny45NzM5IDAuNTAzNTgyIDg3LjQ3MDIgLTguMDE1MjdlLTA1IDg2Ljg0ODkgLTguMDIwN2UtMDVMNTQuMTkzNCAtOC4zMDYxOGUtMDVDNTMuNTcyMSAtOC4zMTE2MmUtMDUgNTMuMDY4NCAwLjUwMzU3OSA1My4wNjg0IDEuMTI0ODdMNTMuMDY4NCAzMy43NzhDNTMuMDY4NCAzNC4zOTkzIDUzLjU3MjEgMzQuOTAyOSA1NC4xOTM0IDM0LjkwMjlaIiBmaWxsPSJ1cmwoI3BhaW50MV9saW5lYXJfMjBfMykiLz48cGF0aCBkPSJNNzguMzgxOCA1Ni4yNDhMMzMuMzgwMSA1Ni4yNDhDMzIuNzU4OCA1Ni4yNDggMzIuMjU1MSA1NS43NDQzIDMyLjI1NTEgNTUuMTIzTDMyLjI1NTEgMTAuMTI0NkMzMi4yNTUxIDkuNTAzMzMgMzIuNzU4OCA4Ljk5OTY3IDMzLjM4MDEgOC45OTk2N0w0Ni4zMTgxIDguOTk5NjdDNDYuOTM5NCA4Ljk5OTY3IDQ3LjQ0MzEgOS41MDMzMyA0Ny40NDMxIDEwLjEyNDZMNDcuNDQzMSAzOS4zNzM2QzQ3LjQ0MzEgMzkuOTk0OSA0Ny45NDY4IDQwLjQ5ODYgNDguNTY4MiA0MC40OTg2TDc4LjM4MTggNDAuNDk4NkM3OS4wMDMxIDQwLjQ5ODYgNzkuNTA2OCA0MS4wMDIyIDc5LjUwNjggNDEuNjIzNUw3OS41MDY4IDU1LjEyM0M3OS41MDY4IDU1Ljc0NDMgNzkuMDAzMSA1Ni4yNDggNzguMzgxOCA1Ni4yNDhaIiBmaWxsPSJ1cmwoI3BhaW50Ml9saW5lYXJfMjBfMykiLz48ZGVmcz4KPGxpbmVhckdyYWRpZW50IGlkPSJwYWludDBfbGluZWFyXzIwXzMiIHgxPSI3Ny41MDM1IiB5MT0iMTIuMDQ0NCIgeDI9IjEzLjk1MTYiIHkyPSI3NC45NjgiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIj4KPHN0b3Agc3RvcC1jb2xvcj0iIzREMjlCNCIvPgo8c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiM4MzZGRkYiLz4KPC9saW5lYXJHcmFkaWVudD4KPGxpbmVhckdyYWRpZW50IGlkPSJwYWludDFfbGluZWFyXzIwXzMiIHgxPSI1MC4wMTA3IiB5MT0iMzYuNjU3IiB4Mj0iOTMuOTk2NCIgeTI9Ii02LjU0ODg3IiBncmFkaWVudFVuaXRzPSJ1c2VyU3BhY2VPblVzZSI+CjxzdG9wIHN0b3AtY29sb3I9IiM3MEZGRTUiLz4KPHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjNjI5NUUxIi8+CjwvbGluZWFyR3JhZGllbnQ+CjxsaW5lYXJHcmFkaWVudCBpZD0icGFpbnQyX2xpbmVhcl8yMF8zIiB4MT0iNzMuODM3NyIgeTE9IjE5LjM3NTkiIHgyPSIzMi40NzA1IiB5Mj0iNTguNjU0NCIgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25Vc2UiPgo8c3RvcCBvZmZzZXQ9IjAuMDA3NDc1MTEiIHN0b3AtY29sb3I9IiM2NTRGRUMiLz4KPHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjNzFCMkZGIi8+CjwvbGluZWFyR3JhZGllbnQ+CjwvZGVmcz48L3N2Zz4=)](https://localstack.cloud)

添付ファイルを Amazon S3 に置く Redmine のプラグインです。Redmine の CloudFront のディストリビューションを通した、署名付き URL でのアップロードとダウンロード(アップロードは S3 が SHA256 を確認し、ダウンロードには Redmine の sandbox の CSP を付ける)、`/tmp` のキャッシュ、バケットの管理画面を持ちます。AWS Lambda でも、Lambda 以外でも動きます。[Serverless](https://github.com/redmine-kit/serverless) は、[Redmine Serverless](https://github.com/redmine-kit/redmine_serverless) といっしょに使います。

[English](README.md)

> **状態:** 開発の初期の段階です。バージョン 0.1.2 を作り、Redmine 7.0.3 と、LocalStack と moto でテストしています。本物の CloudFront のディストリビューションが要ることは、まだ確認していません([確認すること](docs/ja/attachments.md#to-verify))。

<a id="documentation"></a>

## ドキュメント

- Web サイト: https://redmine-kit.github.io/redmine_serverless_s3/ja/ (English: https://redmine-kit.github.io/redmine_serverless_s3/)
- Markdown: [docs/ja/README.md](docs/ja/README.md) (English: [docs/README.md](docs/README.md))。[導入](docs/ja/setup.md)、[IAM の権限](docs/ja/iam.md)、[添付ファイルと S3](docs/ja/attachments.md)、[管理画面](docs/ja/admin.md)があります。

<a id="sponsors"></a>

## スポンサー

<a href="https://www.keyselect.co.jp/">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/keyselect-logo-dark.svg">
    <img alt="KEY SELECT" src=".github/assets/keyselect-logo.svg" width="136" height="29">
  </picture>
</a>
&emsp;&emsp;
<a href="https://localstack.cloud">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/localstack-logo-dark.svg">
    <img alt="LocalStack" src=".github/assets/localstack-logo.svg" width="98" height="23">
  </picture>
</a>

<a id="license"></a>

## ライセンス

Redmine Serverless S3 は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](LICENSE) を参照してください。Redmine の非公式のプラグインです。
