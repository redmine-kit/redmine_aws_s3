# 準備

Redmine Serverless S3 を使う Redmine に要るもの(インストール、設定、バケット、CloudFront のディストリビューション、IAM の権限、ネットワーク)です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは設計段階なので、下の内容は設計で、コードを書くときに確認します。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の認証情報で S3 に届くプロセス(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。Redmine にアクセスキーは置きません。
- Redmine を CloudFront のディストリビューションで配っていること。ブラウザーは、ファイルのアップロードとダウンロードも、これを通して行い、S3 のドメインには触れません([attachments.md](attachments.md#upload))。

<a id="installation"></a>

## インストール

1. プラグインを `plugins/redmine_serverless_s3` に置き、`bundle install` を実行します(プラグインの `Gemfile` が `aws-sdk-s3` を足し、Redmine の `Gemfile` がそれを読み込みます)。
2. migration は要りません。
3. バケットを設定します(下記)。設定がなければ、プラグインは動かず、Redmine は標準のとおりディスクに添付ファイルを置きます。

<a id="configuration"></a>

## 設定

| 設定 | 置き場所 | 中身 |
| --- | --- | --- |
| バケットの名前とリージョン | 環境変数 | プラグインを有効にする |
| CloudFront のドメインとキーペアの ID | 環境変数 | Redmine のディストリビューションのドメイン(`/files/`、`/thumbnails/`、`/tmp/bulk/`、`/incoming/` の下の署名付き URL に使う)と、その信頼されたキーグループの公開鍵の ID |
| CloudFront の秘密鍵 | 秘密の値(Serverless では、`/<instance>/env/` の下の SecureString のパラメーターで、[Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/ja/) が環境変数に読み込む) | CloudFront の URL に署名する。ファイルやログには書かない |
| 署名付き URL の有効期限 | プラグインの設定 | [管理画面](admin.md#attachments-in-s3)に出す。ダウンロードは 5 分、アップロードは 15 分([attachments.md](attachments.md#upload)) |
| `/tmp` のキャッシュの大きさ | プラグインの設定 | [attachments.md](attachments.md#the-tmp-cache) |
| `attachments_storage_path` | `config/configuration.yml` | 手元のキャッシュのディレクトリ。Lambda では `/tmp` の下(例: `/tmp/redmine/files`) |
| 添付ファイルの最大の大きさ | Redmine の設定 | これまでどおり変えられる。`/incoming/*` の CloudFront Functions は、同じ上限を使う必要がある([admin.md](admin.md#maximum-attachment-size)) |

- **変数の名前:** 環境変数の名前は、コードを書くときに決めます(未定)。

<a id="the-bucket"></a>

## バケット

バケットは 1 つで、キーは [attachments.md](attachments.md#bucket-layout) のとおりです。

| 項目 | 設定 |
| --- | --- |
| バージョニング | 有効。古いバージョンは 30 日で消す |
| ライフサイクル | `incoming/` と `tmp/` は 1 日、`imports/` は 7 日、古いバージョンは 30 日で消す |
| 暗号化 | SSE-S3(S3 の既定) |
| 公開 | S3 のパブリックアクセスのブロックを有効にする。TLS でない要求は、バケットポリシーで拒む(`aws:SecureTransport` が `false`) |
| CORS | なし。ブラウザーは Redmine のドメインだけを使う |
| バケットポリシー | TLS でない要求を拒む。Redmine の CloudFront のディストリビューションに、オリジンアクセスコントロール(OAC)を通して、`files/`、`thumbnails/`、`tmp/bulk/` の読み取りと、`incoming/` への書き込みを許す |

- **バケットに届くもの:** OAC を通した CloudFront と、Redmine を動かすプロセスのロールです。ブラウザーに S3 の署名付き URL は渡しません。

<a id="the-cloudfront-distribution"></a>

## CloudFront のディストリビューション

プラグインは、Redmine 自身のディストリビューションを使い、2 つめのディストリビューションは要りません。次のものを足します。

| 項目 | 設定 |
| --- | --- |
| オリジン | 添付ファイルのバケット。要求に署名するオリジンアクセスコントロール(OAC)を付ける |
| ビヘイビア `/files/*`、`/thumbnails/*`、`/tmp/bulk/*` | GET と HEAD。署名付き URL を必須にする(下の信頼されたキーグループ)。キャッシュのキーとオリジンへの要求に、クエリーの `response-content-disposition` と `response-content-type` を入れ、Cookie と `Authorization` のヘッダーは入れない。レスポンスヘッダーポリシーで `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox` と `X-Content-Type-Options: nosniff` を付ける |
| ビヘイビア `/incoming/*` | すべてのメソッド(PUT が要る)。署名付き URL を必須にする。キャッシュしない。オリジンへの要求で `x-amz-checksum-sha256` のヘッダーを渡す。ビューワーリクエストの CloudFront Functions で、アップロードの上限を超える `Content-Length` を断る |
| 信頼されたキーグループ | Redmine が URL の署名に使う秘密鍵の、公開鍵 |
| ほかのビヘイビア | 今までどおり Redmine。本文のハッシュを入れる関数は、これらだけに付ける |

- **Redmine のパス:** Redmine には、`/files`、`/thumbnails`、`/tmp` で始まるルートがないので(2026-11-09 に Redmine 7.0.3 で確認)、これらのビヘイビアが Redmine の画面を隠すことはありません([attachments.md](attachments.md#download))。
- **sandbox の CSP を外さない:** 添付ファイルは Redmine のオリジンから返り、そこでスクリプトを動かさないようにしているのは sandbox の CSP です。ディストリビューションを変えるたびに、`/files/` の下の応答にそれが付いていることを確認します。
- **キーペアを作る:** 秘密鍵は一度だけ作って秘密の値として持ち、CloudFront には公開鍵だけを入れます。Serverless は、デプロイで作ります。

<a id="iam-permissions"></a>

## IAM の権限

プラグインを入れた Redmine を動かすプロセス(画面の要求、ジョブ、rake)には、どれもバケットへの同じ権限を渡します。ブラウザーはこの認証情報を使いません。アップロードとダウンロードは、CloudFront の秘密鍵で署名した URL で、CloudFront を通ります。

| 権限 | リソース | 使いみち |
| --- | --- | --- |
| `s3:GetObject`、`s3:PutObject`、`s3:DeleteObject` | バケットの `files/*`、`thumbnails/*`、`imports/*`、`incoming/*`、`tmp/*` | 添付ファイルとサムネイルの保存と削除、登録のときのチェックサム付きの `HeadObject` と `incoming/` からの写し、合わないアップロードの削除、CSV のインポート、一括のダウンロードの zip、読み書きの確認(`tmp/healthcheck/`) |
| `s3:ListBucket` | バケット | ないオブジェクトへの `HeadObject` を、403 でなく 404 にする。前方一致でのサムネイルの削除、突き合わせ、接続の確認の `HeadBucket` |
| CloudFront の秘密鍵を読む | それを入れた秘密の値(Serverless では、[Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/ja/) を通した、`/<instance>/env/` への `ssm:GetParametersByPath`) | CloudFront の URL の署名 |

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
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket>"
    }
  ]
}
```

OAC を通した CloudFront を許すバケットポリシーです。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudFrontRead",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::<bucket>/files/*",
        "arn:aws:s3:::<bucket>/thumbnails/*",
        "arn:aws:s3:::<bucket>/tmp/bulk/*"
      ],
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account>:distribution/<distribution ID>" } }
    },
    {
      "Sid": "CloudFrontUpload",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<bucket>/incoming/*",
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account>:distribution/<distribution ID>" } }
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
| ブラウザー | Redmine の CloudFront のディストリビューション(アップロードとダウンロード) | インターネット越し。VPC は通らない。ブラウザーが S3 に直接届くことはない |
| CloudFront | OAC を通してバケット | AWS のネットワーク。VPC は通らない |

<a id="tests"></a>

## テスト

Redmine の標準のプラグインのテスト(`bin/rake redmine:plugins:test NAME=redmine_serverless_s3`)です。S3 は、ユニットと機能のテストでは SDK の `stub_responses`、統合とシステムのテストでは moto で再現します。Redmine 本体の添付ファイルのテストも、プラグインを有効にして実行します([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#attachments-in-s3-redmine_serverless_s3))。
