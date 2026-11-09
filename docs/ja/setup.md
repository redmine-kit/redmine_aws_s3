# 準備

Redmine Serverless S3 を使う Redmine に要るもの(入れ方、設定、バケット、IAM の権限、ネットワーク)です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは設計段階なので、下の内容は設計で、コードを書くときに確認します。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の認証情報で S3 に届くプロセス(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。Redmine にアクセスキーは置きません。
- ブラウザーがインターネット越しに S3 に届くこと。アップロードとダウンロードは、ブラウザーと S3 のあいだで直接やり取りするためです([attachments.md](attachments.md#upload))。

<a id="installation"></a>

## 入れ方

1. プラグインを `plugins/redmine_serverless_s3` に置き、`bundle install` を実行します(プラグインの `Gemfile` が `aws-sdk-s3` を足し、Redmine の `Gemfile` がそれを読み込みます)。
2. migration は要りません。
3. バケットを設定します(下記)。設定がなければ、プラグインは動かず、Redmine は標準のとおりディスクに添付ファイルを置きます。

<a id="configuration"></a>

## 設定

| 設定 | 置き場所 | 中身 |
| --- | --- | --- |
| バケットの名前とリージョン | 環境変数 | プラグインを有効にする。変数の名前は、コードを書くときに決める(未定) |
| 署名付き URL の有効期限 | プラグインの設定 | [管理画面](admin.md#attachments-in-s3)に出す。アップロードの署名付きの POST は 15 分で切れる([attachments.md](attachments.md#upload)) |
| `/tmp` のキャッシュの大きさ | プラグインの設定 | [attachments.md](attachments.md#the-tmp-cache) |
| `attachments_storage_path` | `config/configuration.yml` | 手元のキャッシュのディレクトリ。Lambda では `/tmp` の下(例: `/tmp/redmine/files`) |
| 添付ファイルの最大の大きさ | Redmine の設定 | これまでどおり変えられる。実際の上限はプラグインが画面に出す([admin.md](admin.md#maximum-attachment-size)) |

<a id="the-bucket"></a>

## バケット

バケットは 1 つで、キーは [attachments.md](attachments.md#bucket-layout) のとおりです。

| 項目 | 設定 |
| --- | --- |
| バージョニング | 有効。古いバージョンは 30 日で消す |
| ライフサイクル | `incoming/` と `tmp/` は 1 日、`imports/` は 7 日、古いバージョンは 30 日で消す |
| 暗号化 | SSE-S3(S3 の既定) |
| 公開 | S3 のパブリックアクセスのブロックを有効にする。TLS でない要求は、バケットポリシーで拒む(`aws:SecureTransport` が `false`) |
| CORS | Redmine のオリジン(例: `https://redmine.example.com`)からの `POST` を許す。署名付きの POST のため |

- **経路では絞らない:** バケットやロールを、VPC エンドポイントや IP アドレスで絞らないでください(`aws:SourceVpce`、`aws:SourceIp`)。ブラウザーはインターネットから署名付き URL を使うので、その条件で拒まれてしまいます([attachments.md](attachments.md#bucket-layout))。

<a id="iam-permissions"></a>

## IAM の権限

プラグインを入れた Redmine を動かすプロセス(画面の要求、ジョブ、rake)には、どれもバケットへの同じ権限を渡します。署名付き URL はこの認証情報で署名するので、ブラウザーができることは、このポリシーと署名の条件(キー、大きさ、有効期限)の両方で決まります。

| 権限 | リソース | 使いみち |
| --- | --- | --- |
| `s3:GetObject`、`s3:PutObject`、`s3:DeleteObject` | バケットの `files/*`、`thumbnails/*`、`imports/*`、`incoming/*`、`tmp/*` | 添付ファイルとサムネイルの保存と削除、署名付きの POST と GET、登録のときの `incoming/` からの写し、CSV のインポート、一括のダウンロードの zip、読み書きの確認(`tmp/healthcheck/`) |
| `s3:ListBucket` | バケット | ないオブジェクトへの `HeadObject` を、403 でなく 404 にする。前方一致でのサムネイルの削除、突き合わせ、接続の確認の `HeadBucket` |
| `s3:GetBucketCors` | バケット | 管理画面の、直接のアップロードの確認(画面の要求だけ) |

ポリシーの例です。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Objects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::<bucket>/files/*",
        "arn:aws:s3:::<bucket>/thumbnails/*",
        "arn:aws:s3:::<bucket>/imports/*",
        "arn:aws:s3:::<bucket>/incoming/*",
        "arn:aws:s3:::<bucket>/tmp/*"
      ]
    },
    {
      "Sid": "Bucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketCors"],
      "Resource": "arn:aws:s3:::<bucket>"
    }
  ]
}
```

TLS でない要求を拒むバケットポリシーです。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TlsOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::<bucket>", "arn:aws:s3:::<bucket>/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

<a id="network"></a>

## ネットワーク

| どこから | どこへ | インターネットに出られない VPC の中では |
| --- | --- | --- |
| Redmine | バケットのリージョンの S3 の API | S3 のゲートウェイのエンドポイント(`com.amazonaws.<region>.s3`、無料)を、サブネットのルートテーブルに付ける |
| ブラウザー | S3(署名付きの POST と GET) | インターネット越し。VPC は通らない |

<a id="tests"></a>

## テスト

Redmine の標準のプラグインのテスト(`bin/rake redmine:plugins:test NAME=redmine_serverless_s3`)です。S3 は、ユニットと機能のテストでは SDK の `stub_responses`、統合とシステムのテストでは moto で再現します。Redmine 本体の添付ファイルのテストも、プラグインを有効にして実行します([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#attachments-in-s3-redmine_serverless_s3))。
