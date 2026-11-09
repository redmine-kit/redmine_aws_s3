# 準備

Redmine Serverless S3 を使う Redmine に要るもの(インストール、設定、バケット、CloudFront のディストリビューション、IAM の権限、ネットワーク)です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは開発の初期の段階です。下のコードは作ってあり、moto でテストしています。本物の CloudFront のディストリビューションが要る部分は、[確認すること](#to-verify)にあります。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の認証情報で S3 に届くプロセス(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。Redmine にアクセスキーは置きません。
- Redmine を CloudFront のディストリビューションで配っていること。ブラウザーは、ファイルのアップロードとダウンロードも、これを通して行い、S3 のドメインには触れません([attachments.md](attachments.md#upload))。

<a id="installation"></a>

## インストール

**プラグインの取り方:** バージョンのタグごとに、プラグインを gem として GitHub Packages(`https://rubygems.pkg.github.com/redmine-kit`)に公開します。最初のバージョンは 0.1.0 です。GitHub Packages から入れるには、公開のパッケージでも、`read:packages` の権限を持つ GitHub のトークンが要ります。gem はプラグインの動かすためのファイルを持ちます。Redmine は `plugins/` のプラグインだけを読み込むので、入れた gem をそこにリンクします。

```ruby
# Redmine の Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_serverless_s3'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <ユーザー>:<トークン>   # か、変数 BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_serverless_s3)" plugins/redmine_serverless_s3
```

gem を使わないなら、リポジトリを `plugins/redmine_serverless_s3` に clone します(`git clone https://github.com/redmine-kit/redmine_serverless_s3.git plugins/redmine_serverless_s3`)。

1. プラグインを `plugins/redmine_serverless_s3` に置き、`bundle install` を実行します(プラグインの `Gemfile` と gem が `aws-sdk-s3` と `aws-sdk-cloudfront` を足し、Redmine の `Gemfile` がプラグインの `Gemfile` を読み込みます)。
2. migration は要りません。
3. プラグインの JavaScript `s3_upload.js` を配るために、`bin/rails assets:precompile`(か、Redmine のいつもの assets の手順)を実行します。
4. 環境変数を設定します(下記)。`REDMINE_S3_BUCKET` がなければ、プラグインは動かず、Redmine は標準のとおりディスクに添付ファイルを置きます。

<a id="configuration"></a>

## 設定

| 設定 | 置き場所 | 中身 |
| --- | --- | --- |
| `REDMINE_S3_BUCKET` | 環境変数 | 添付ファイルのバケット。プラグインを有効にする。なければ、Redmine は標準のとおりに動く |
| `REDMINE_S3_REGION` | 環境変数 | バケットのリージョン。省略できる。なければ `AWS_REGION`、次に `AWS_DEFAULT_REGION` を使う |
| `REDMINE_CLOUDFRONT_DOMAIN` | 環境変数 | Redmine のディストリビューションのドメイン(例: `redmine.example.com`)。`/files/`、`/thumbnails/`、`/tmp/bulk/`、`/incoming/` の下の署名付き URL に使う |
| `REDMINE_CLOUDFRONT_KEY_PAIR_ID` | 環境変数 | ディストリビューションの信頼されたキーグループの公開鍵の ID |
| `REDMINE_CLOUDFRONT_PRIVATE_KEY` | 秘密の値から読む環境変数(Serverless では、`/<instance>/env/` の下の SecureString のパラメーターで、[Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/ja/) が環境変数に読み込む) | PEM の秘密鍵。CloudFront の URL に署名する。ファイルやログには書かず、管理画面にも出さない |
| 署名付き URL の有効期限 | プラグインの設定。[管理画面](admin.md#attachments-in-s3)で変える | ダウンロードとサムネイルは 300 秒、アップロードは 900 秒([attachments.md](attachments.md#upload)) |
| 手元のキャッシュの大きさ | プラグインの設定。管理画面で変える | 256 MB([attachments.md](attachments.md#the-tmp-cache)) |
| `attachments_storage_path` | `config/configuration.yml` | 手元のキャッシュのディレクトリ。Lambda では `/tmp` の下(例: `/tmp/redmine/files`) |
| 添付ファイルの最大の大きさ | Redmine の設定 | これまでどおり変えられる。`/incoming/*` の CloudFront Functions は、同じ上限を使う必要がある([admin.md](admin.md#maximum-attachment-size)) |

- **AWS の認証情報:** S3 のクライアントは、SDK の標準の認証情報の探し方を使います(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。プラグインが自分でアクセスキーを読むことはありません。
- **ジョブ:** 管理画面の突き合わせは、Active Job の `ServerlessS3ReconcileJob` として動きます。許可するジョブのクラスの一覧を持つキュー([Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/ja/) など)を通すときは、一覧に足します。

<a id="aws-resources"></a>

## AWS のリソース

<a id="the-bucket"></a>

### バケット

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

### CloudFront のディストリビューション

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

プラグインに要る権限と例のポリシーは、[iam.md](iam.md) にあります。

<a id="network"></a>

## ネットワーク

| どこから | どこへ | インターネットに出られない VPC の中では |
| --- | --- | --- |
| Redmine | バケットのリージョンの S3 の API | S3 のゲートウェイのエンドポイント(`com.amazonaws.<region>.s3`、無料)を、サブネットのルートテーブルに付ける |
| ブラウザー | Redmine の CloudFront のディストリビューション(アップロードとダウンロード) | インターネット越し。VPC は通らない。ブラウザーが S3 に直接届くことはない |
| CloudFront | OAC を通してバケット | AWS のネットワーク。VPC は通らない |

<a id="tests"></a>

## テスト

Redmine の標準のプラグインのテスト(`bin/rails redmine:plugins:test NAME=redmine_serverless_s3`)です。Docker の中で、Redmine 7.0.3、PostgreSQL 16、moto を使います。

```sh
bin/test                 # プラグインのテスト。カバレッジを coverage/ に出す
bin/test core            # プラグインを入れた(無効の)状態で、Redmine 本体のテスト
bin/test <ファイル...>    # プラグインのテストの一部
bin/services --down      # PostgreSQL と moto を止める
bin/lint                 # RuboCop
node test/javascripts/sha256_test.mjs   # アップロードの JavaScript の SHA-256
```

- **S3:** ユニットと機能のテストでは、SDK の `stub_responses` で S3 を置き換えます。統合のテストでは moto を使います。moto 5.2.5 は、`x-amz-checksum-sha256` を確認せず、`HeadObject` で `ChecksumSHA256` を返しません(2026-11-09 に確認)。そこで、統合のテストは、その `HeadObject` の結果を保存されたバイト列から計算し、合わないチェックサムは `stub_responses` でテストします。
- **署名付き URL:** テストで鍵のペアを作り、署名付き URL を公開鍵で検証します。
- **置き換えるコード:** 置き換えたり写したりした Redmine のメソッドと、`attachments.js` の `uploadBlob` の SHA256 を、Redmine 7.0.3 のものと比べるテストがあります([attachments.md](attachments.md#replaced-code))。
- **カバレッジ:** `bin/test` は、SimpleCov(Redmine の `COVERAGE`)でプラグインの `app/` と `lib/` のカバレッジを測り、`coverage/coverage.xml`(Cobertura)と HTML のレポートを書きます。
- **CI:** GitHub Actions が、push と pull request ごとに `bin/lint`、SHA-256 のテスト、`bin/test` を実行し、カバレッジを OIDC で [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_s3) に送ります。

<a id="to-verify"></a>

## 確認すること

まだ確認していないことは、[attachments.md](attachments.md#to-verify) にあります。
