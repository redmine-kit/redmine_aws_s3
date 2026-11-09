# 管理画面

Redmine Serverless S3 の管理画面の設計です。Redmine の管理者だけが開けます(`require_admin`)。[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/admin.html) を入れているときは、その「サーバーレス」の管理画面のタブになります。入れていないときは、Redmine の管理のメニューの 1 つの項目になります。

<a id="attachments-in-s3"></a>

## 添付ファイルの S3

| 項目 | 中身 | 取り方 |
| --- | --- | --- |
| 設定 | バケットの名前、リージョン、CloudFront のドメインとキーペアの ID、署名付き URL の期限、`/tmp` のキャッシュの大きさ | 環境変数(表示だけ)、プラグインの設定(期限など)。秘密鍵は表示しない |
| 読み書きの確認 | 確認用のオブジェクト(`tmp/healthcheck/<UUID>`)を置いて、読んで、消す | ボタンで `PutObject`、`GetObject`、`DeleteObject` |
| 突き合わせ | データベースの添付ファイルのうち、S3 にないもの。S3 にあるが、どの添付ファイルからも使われていないもの | ボタンで、ジョブとして実行し、結果を画面に出す |
| 配信の確認 | 確認のためのオブジェクトを置き、`/tmp/bulk/` の下の署名付き URL を作り、CloudFront を通して取る。オブジェクトが sandbox の CSP と `nosniff` 付きで返り、署名のない同じ URL が断られること | ボタンで実行する。確認のためのオブジェクトは最後に消す |

- **使い道:** 古い Redmine から添付ファイルを移したあと([migration.md](https://redmine-kit.github.io/serverless/ja/migration.html))に、突き合わせで漏れがないかを確認できます。
- **接続の確認:** Redmine Serverless を入れているときは、その接続の確認で、添付ファイルのバケットの `HeadBucket` も呼びます。
- **秘密の値は出さない:** AWS の認証情報は画面に出しません。AWS の API は、ボタンを押したときだけ呼びます。

<a id="maximum-attachment-size"></a>

## 添付ファイルサイズの上限

Redmine の「添付ファイルサイズの上限」(`attachment_max_size`、管理 › 設定 › ファイル)は、変えられるままにします。プラグインは、設定の画面に上限の目安の説明を足します。CloudFront を通したアップロードは、`/incoming/*` の CloudFront Functions(同じ値を使う必要がある)と、1 回の PUT で CloudFront が受け付ける大きさで限られます。Lambda では、REST API の `POST /uploads.json` は 1 MB までです([attachments.md](attachments.md#upload))。

<a id="permissions"></a>

## 権限

突き合わせのジョブのために、ジョブを動かすロールに、バケットの一覧の権限を付けます。配信の確認は、添付ファイルと同じ権限を使います。一覧は [setup.md](setup.md#iam-permissions) にあります。

<a id="tests"></a>

## テスト

画面に、Redmine の機能のテストとシステムのテストを書きます([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。
