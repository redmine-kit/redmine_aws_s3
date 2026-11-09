# Redmine Serverless S3

Redmine Serverless S3(`redmine_serverless_s3`)は、添付ファイルを Amazon S3 に置く Redmine のプラグインです。アップロードはブラウザーから Redmine の CloudFront のディストリビューションを通して S3 に PUT し、ダウンロードは Redmine のドメインの CloudFront の署名付き URL にリダイレクトするので、ファイルの本体は Redmine を通りません。Redmine 本体のファイルは書き換えず、Redmine の標準の拡張の仕組みだけで作ります。今は設計段階で、資料だけがあります。

- [準備](setup.md): 前提、インストール、設定、AWS のリソース(バケット、CloudFront のディストリビューション)、ネットワーク、テスト
- [IAM の権限](iam.md): 権限、例のポリシー、リソースベースのポリシー
- [添付ファイルと S3](attachments.md): 保存、アップロード、ダウンロード、キャッシュ、差し替える処理
- [管理画面](admin.md): 設定、読み書きの確認、突き合わせ

<a id="features"></a>

## 機能

| 機能 | 中身 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| S3 の添付ファイル | 保存と削除、CloudFront を通した S3 へのアップロード(S3 が確認するチェックサム付きの PUT)、sandbox の CSP を付ける CloudFront の署名付き URL へのリダイレクト(ダウンロードとサムネイル)、`/tmp` のキャッシュ、CSV のインポートのファイル、一括のダウンロードの zip | S3 のバケットと CloudFront の設定(環境変数)がある。なければ Redmine の標準のまま | [attachments.md](attachments.md) |
| 管理画面 | バケットと設定、S3 への読み書きの確認、データベースと S3 の突き合わせ | 管理者 | [admin.md](admin.md) |

- **Lambda でも、Lambda 以外でも:** S3 に届き、CloudFront で配る Redmine なら、どこでも動きます。AWS Lambda には書き込めるディスクがなく、要求は 6 MB までなので、[Serverless](https://redmine-kit.github.io/serverless/ja/) は [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/) といっしょに入れます。
- **gem:** プラグインが使う gem(`aws-sdk-s3` など)は、プラグインの `Gemfile` に書きます。Redmine の `Gemfile` は、`plugins/*/Gemfile` も読み込みます。
- **テスト:** Redmine の標準の仕組み(`rake redmine:plugins:test`)で、差し替えた処理ごとにテストを書きます([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#attachments-in-s3-redmine_serverless_s3))。
- **migration:** 予定はありません。
