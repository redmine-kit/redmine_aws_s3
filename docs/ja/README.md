# Redmine AWS S3

Redmine AWS S3 (`redmine_aws_s3`) は、添付ファイルを Amazon S3 に置く Redmine のプラグインです。アップロードはブラウザーから Redmine の CloudFront のディストリビューションを通して S3 に PUT し、ダウンロードは Redmine のドメインの CloudFront の署名付き URL にリダイレクトするので、ファイルの本体は Redmine を通りません。Redmine 本体のファイルは書き換えず、Redmine の標準の拡張の仕組みだけで作ります。今は開発の初期です。

- [導入](setup.md): 動作環境、インストール、設定、AWS リソース (バケット、CloudFront のディストリビューション)、ネットワーク、テスト
- [IAM 権限](iam.md): 権限、ポリシーの例、リソースベースのポリシー
- [添付ファイルと S3](attachments.md): 保存、アップロード、ダウンロード、アバター、キャッシュ、差し替える処理
- [管理画面](admin.md): 設定、接続テスト、整合性チェック

<a id="features"></a>

## 機能

| 機能 | 内容 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| S3 の添付ファイル | 保存と削除、CloudFront を通した S3 へのアップロード (SHA256 は S3 が計算する)、sandbox の CSP を付ける CloudFront の署名付き URL へのリダイレクト (ダウンロードとサムネイル)、`/tmp` のキャッシュ、CSV のインポートのファイル、一括ダウンロードの zip、GuardDuty のマルウェアスキャンを待つこと (使うときだけ) | `REDMINE_S3_BUCKET` と CloudFront の設定がある ([setup.md](setup.md#configuration))。なければ Redmine の標準のまま | [attachments.md](attachments.md) |
| アバター (Redmine 7.1) | アバターのフォームが画像を CloudFront 経由で S3 に送るので、数 MB の写真も使え、Redmine が自身のルールで登録する。切り抜いたサムネイルは S3 に置き、Redmine が返す | S3 のバケットを設定し、Redmine にアバターがある (7.1) とき。Redmine 7.0 では何も変わらない | [attachments.md](attachments.md#avatars) |
| 管理画面 | Redmine の管理メニューの「AWS」([Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/admin.html#the-aws-menu)) の下の「S3」のタブ。環境変数と設定、S3 の読み書きテストと CloudFront からの配信テスト、マルウェアスキャンでブロックしたファイル、データベースと S3 の整合性チェック | 管理者 | [admin.md](admin.md) |

<a id="outside-lambda"></a>

## Lambda 以外での利用

S3 に届き、CloudFront で配信している Redmine なら、どこでも動きます。AWS Lambda には書き込めるディスクがなく、1 つのリクエストは 6 MB までなので、[Serverless](https://redmine-kit.github.io/serverless/ja/) は [Redmine AWS Lambda](https://redmine-kit.github.io/redmine_aws_lambda/ja/) といっしょにインストールします。

<a id="gems-and-database"></a>

## gem とデータベース

依存する gem は `aws-sdk-s3` と `aws-sdk-cloudfront` です。プラグインの `Gemfile` と gem の依存に書いてあり、Redmine の `Gemfile` は `plugins/*/Gemfile` も読み込みます。また、「AWS」の管理メニューを持つプラグイン [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) (`redmine_aws`) を必要とします。gem はこれに依存し、`init.rb` はインストールされていることを確認します (`requires_redmine_plugin`)。データベースのテーブルを追加しないので、実行するマイグレーションはありません。

<a id="tests"></a>

## テスト

差し替えた処理ごとに、Redmine の標準の仕組み (`rake redmine:plugins:test`) でテストを書いています。テストが確認する内容は [setup.md](setup.md#what-the-tests-check) にあります。

<a id="sponsors"></a>

## スポンサー

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

<a id="license"></a>

## ライセンス

Redmine AWS S3 は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](../../LICENSE) を参照してください。Redmine の非公式のプラグインです。
