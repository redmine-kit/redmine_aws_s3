# 管理画面

Redmine AWS S3 の管理画面です。システム管理者だけが開けます (`require_admin`)。画面は、[Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/admin.html#the-aws-menu) が追加し、すべての Redmine AWS のプラグインが共有する、Redmine の管理メニューの「AWS」の下の「S3」のタブです。

<a id="attachments-in-s3"></a>

## S3

![「読み書きテスト」のあとの「S3」のタブ。環境変数、テストの結果、マルウェアスキャンでブロックしたファイル、最後の整合性チェック、設定](./images/s3-admin.png)

| 欄 | 内容 | 取得元 |
| --- | --- | --- |
| 環境変数 | 「バケット」、「リージョン」、「CloudFront ドメイン」、「CloudFront キーペア ID」、「CloudFront 秘密鍵」(「設定済み」か「未設定」)、「GuardDuty マルウェアスキャン」(「有効」か「無効」)、「ローカルキャッシュ」。それぞれの値の横に環境変数の名前を出す。「ローカルキャッシュ」の横は `attachments_storage_path`。画面で変更しない値 (これ、接続テストと整合性チェックの結果) は、「管理」›「情報」と同じく、見出しの行のない一覧に出す ([Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/api.html#values) の部分テンプレート `aws_admin/values`) | 環境変数 ([setup.md](setup.md#configuration)) と `config/configuration.yml`。表示のみ。秘密鍵そのものは出さない |
| 接続テスト | 「読み書きテスト」は、テスト用のオブジェクト (`tmp/healthcheck/<UUID>`) を置いて、読んで、消す。「配信テスト」は、テスト用のオブジェクトを置き、`/tmp/bulk/` の下の署名付き URL を作り、CloudFront を通して、署名ありとなしで取る。結果は 1 件ごとに、名称、Redmine の成功か失敗のアイコン、詳細を 1 行に出す ([下記](#connection-tests)) | テキストのリンク。配信テストのオブジェクトは最後に消す |
| マルウェアスキャンでブロックしたファイル | マルウェアスキャンでブロックした最新の 20 件のファイル。列は「日時」、「スキャン結果」、「ファイル」、「ユーザー」(Redmine のユーザーへのリンク)。「GuardDuty マルウェアスキャン」が「有効」のときか、ブロックしたファイルの記録があるときに出す | プラグインの設定に残す ([attachments.md](attachments.md#malware-scan)) |
| 整合性チェック | 「整合性チェックを実行」で、`files/` を一覧してデータベースの添付ファイルと比べるジョブ `AwsS3ReconcileJob` を始める。実行中は「ステータス: 実行中」と「開始日時」を出す。ジョブが失敗したとき (`s3:ListBucket` がないときなど) は「ステータス: 失敗」とし、「詳細」に例外のクラスを出し、メッセージはジョブがログに記録する。開始から 1 時間たっても終わらない実行 (ワーカーのタイムアウト) は、そこに「タイムアウト」と出す。終わったら、「最終実行」、「添付ファイル数」、「S3 オブジェクト数」(`files/` の下)、「S3 にないファイル」、「未使用のオブジェクト」を出し、そのあとに、その 2 つの名前の下に一覧を出す (それぞれ最初の 100 件) | テキストのリンク。結果はプラグインの設定に残すので、どの実行環境でも最新の結果が出る |
| 設定 | 「ダウンロード URL の有効期限」と「アップロード URL の有効期限」(秒)、「ローカルキャッシュサイズの上限」(MB) | プラグインの設定。画面で変える。正の整数に限り、有効期限は 604800 秒 (7 日)、キャッシュは 10240 MB まで。それを超えると Redmine のメッセージ (「… は … 以下の値にしてください」) を出す。正しくない入力は保存せずにフォームに残し、その項目のラベルを挙げたエラーをタブの先頭に出す |

<a id="connection-tests"></a>

接続テストの結果です。

| 名称 | テスト | OK になる条件 |
| --- | --- | --- |
| PutObject、GetObject、DeleteObject | 読み書きテスト | それぞれの呼び出しが成功し、GetObject が置いた内容を返す |
| 署名付き URL | 配信テスト | 署名付き URL で、CloudFront がオブジェクトを返す (200) |
| CSP sandbox | 配信テスト | 応答の `Content-Security-Policy` に `sandbox` がある |
| nosniff | 配信テスト | 応答に `X-Content-Type-Options: nosniff` がある |
| 署名なし URL 拒否 | 配信テスト | 署名を除いた同じ URL が 401 か 403 を返す |
| 配信 | 配信テスト | テストがエラーで止まったときに限り出す |

- **失敗した呼び出し:** 失敗した呼び出しの詳細には、例外のクラスだけを表示します (例: `Aws::S3::Errors::AccessDenied`)。Redmine AWS の「ステータス」タブと同じです。ホスト、アカウント、リソースを含むことがある例外のメッセージは画面に表示せず、テストの名称、クラス、メッセージを Redmine のログに書きます (`[redmine_aws_s3] connection test PutObject failed: …`)。

- **使い道:** 古い Redmine から添付ファイルを移したあと ([migration.md](https://redmine-kit.github.io/serverless/ja/migration.html)) に、整合性チェックで漏れがないかを確認できます。
- **「ステータス」のタブ:** バケットがあるときは、Redmine AWS の「ステータス」のタブの「接続テスト」に「S3」の行が加わります。添付ファイルのバケットの `HeadBucket` を呼び、バケットの名前を出します。
- **秘密の値は出さない:** AWS の認証情報と CloudFront の秘密鍵は画面に出しません。AWS の API は、リンクを押したときに限り呼びます。
- **バケットがないとき:** タブは開き、「REDMINE_S3_BUCKET が未設定のため、添付ファイルはローカルディスクに保存します。」と出します。環境変数と設定は出し、接続テスト、ブロックしたファイル、整合性チェックは出しません。
- **操作の記録:** 設定の変更 (値ではなく設定の名前)、接続テスト、整合性チェックは、システム管理者のログイン名とともに Redmine のログに書きます。

<a id="the-aws-menu"></a>

## AWS メニュー

Redmine の管理メニューの「AWS」の項目 (最初のタブを開く `/admin/aws`) は [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/admin.html#the-aws-menu) が追加し、それぞれの Redmine AWS のプラグインがそこにタブを登録します (`RedmineAws::Admin`)。このプラグインは、「S3」のタブを位置 50 に登録し、バケットがあるときは、「ステータス」のタブの「接続テスト」に「S3」の行 (`HeadBucket`) を追加します。

- **設定:** Redmine のプラグインの一覧で、このプラグインの「設定」を押すと、「S3」のタブが開きます。

<a id="maximum-attachment-size"></a>

## 添付ファイルサイズの上限

Redmine の「添付ファイルサイズの上限」(`attachment_max_size`、「管理」›「設定」›「ファイル」) は、変えられるままにします。プラグインが有効なとき、設定の画面の小さなスクリプトで、この設定の横に「S3 では CloudFront Function (/tmp/*) の上限も同じ値にしてください。Lambda では POST /uploads.json は 1 MB まで」と添えます。CloudFront を通したアップロードは、`/tmp/*` の CloudFront Functions (`/tmp/incoming/` へのアップロードに同じ値を使う必要がある) と、1 回の PUT で CloudFront が受け付ける大きさで限られます。Lambda では、REST API の `POST /uploads.json` は 1 MB までです ([attachments.md](attachments.md#upload))。

<a id="permissions"></a>

## 権限

整合性チェックのジョブのために、ジョブを動かすロールに、バケットの一覧の権限を付けます。配信テストは、添付ファイルと同じ権限を使います。一覧は [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面には Redmine の機能テストがあります。システムテストはまだ書いていません ([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。

このページの画面のスクリーンショットは、`bin/screenshots` で撮ります (Docker の中のヘッドレスの Chromium と、Redmine のテストデータと、テストの S3。バケット、CloudFront の値、ブロックしたファイル、整合性チェックは例)。画面を変えたら実行します。

<a id="terms"></a>

## 用語

画面の用語は、AWS に用語があるものは、AWS の日本語のドキュメントに合わせています (2026-11-10 に確認)。GuardDuty の日本語のドキュメントは機械翻訳です。

| 画面 (ja / en) | AWS の用語 | 出典 | 状態 |
| --- | --- | --- | --- |
| GuardDuty マルウェアスキャン / GuardDuty malware scan | 「マルウェアスキャン」 | https://docs.aws.amazon.com/ja_jp/guardduty/latest/ug/monitoring-malware-protection-s3-scans-gdu.html | ドキュメント |
| スキャン結果 / Scan result | 「スキャン結果」。タグの `GuardDutyMalwareScanStatus` | 同じページ | ドキュメント |
| 脅威を検出 / Threats found | `THREATS_FOUND` | 同じページ。値は英語のまま。日本語は、説明の「潜在する脅威を検出しました」から作った | コンソールで要確認 |
| サポート対象外 / Unsupported | `UNSUPPORTED` | 同じページ。サポートしないファイルではスキャンをスキップするという説明から作った | コンソールで要確認 |
| アクセス拒否 / Access denied | `ACCESS_DENIED` | 同じページ。説明の「GuardDuty はこのオブジェクトにアクセスできず」から作った | コンソールで要確認 |
| 失敗 / Failed | `FAILED` | 同じページ。スキャンのステータスの「失敗」から作った | コンソールで要確認 |
| 不明 / Unknown | ほかの値 | GuardDuty があとで追加するかもしれない値は、生の値ではなくこのラベルで表示する | 製品の用語 |
| バケット / Bucket、S3 オブジェクト数 / S3 objects | 「バケット」、「オブジェクト」 | https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/Welcome.html | ドキュメント |
| CloudFront キーペア ID / CloudFront key pair ID | 「キーペア ID」 | https://docs.aws.amazon.com/ja_jp/AmazonCloudFront/latest/DeveloperGuide/private-content-trusted-signers.html | ドキュメント |
| 整合性チェック / Consistency check | — | この製品の用語。AWS に対応する用語はない | 製品の用語 |
| マルウェアスキャンでブロックしたファイル / Files blocked by malware scan | — | 「ブロック」は、スキャンのあとに Redmine が受け付けないファイルを指す、この製品の用語。GuardDuty が行うのは、オブジェクトへのタグ付けまで | 製品の用語 |
