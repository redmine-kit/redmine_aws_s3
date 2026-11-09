# 準備

Redmine Serverless S3 を使う Redmine に要るもの(インストール、設定、バケット、CloudFront のディストリビューション、IAM の権限、ネットワーク)です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは開発の初期の段階です。下のコードは作ってあり、moto でテストしています。本物の CloudFront のディストリビューションが要る部分は、[確認すること](#to-verify)にあります。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の認証情報で S3 に届くプロセス(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。Redmine にアクセスキーは置きません。
- Redmine を CloudFront のディストリビューションで配っていること。ブラウザーは、ファイルのアップロードとダウンロードも、これを通して行い、S3 のドメインには触れません([attachments.md](attachments.md#upload))。

<a id="installation"></a>

## インストール

**プラグインの取り方:** バージョンのタグごとに、プラグインを gem として GitHub Packages(`https://rubygems.pkg.github.com/redmine-kit`)に公開します。いまのバージョンは 0.1.1 です。GitHub Packages から入れるには、公開のパッケージでも、`read:packages` の権限を持つ GitHub のトークンが要ります。gem はプラグインの動かすためのファイルを持ちます。Redmine は `plugins/` のプラグインだけを読み込むので、入れた gem をそこにリンクします。

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

1. プラグインを `plugins/redmine_serverless_s3` に置き、`bundle install` を実行します(プラグインの `Gemfile` と gem が、オブジェクト全体のチェックサム(`ChecksumType`)を持つ 1.178 以降の `aws-sdk-s3` と、1.x の `aws-sdk-cloudfront` を足し、Redmine の `Gemfile` がプラグインの `Gemfile` を読み込みます)。
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
| `REDMINE_S3_MALWARE_SCAN` | 環境変数 | `true` で、アップロードとインポートのファイルを使う前に、GuardDuty Malware Protection for S3 の結果を待つ([attachments.md](attachments.md#malware-scan))。ほかの値やないときは使わない |
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
| バケットポリシー | TLS でない要求を拒む。Redmine の CloudFront のディストリビューションに、オリジンアクセスコントロール(OAC)を通して、`files/`、`thumbnails/`、`tmp/bulk/` の読み取りと、`incoming/` への書き込みを許す。マルウェアのスキャンを使うときは、問題がないとわかる前の `incoming/` と `imports/` の読み取りを拒む |
| マルウェアのスキャン(使うときだけ) | バケットに GuardDuty Malware Protection for S3 のプランを付け、対象を `incoming/` と `imports/` にし、スキャンしたオブジェクトへのタグ付けを有効にする。`REDMINE_S3_MALWARE_SCAN=true` にする([attachments.md](attachments.md#malware-scan)) |

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

Redmine の標準のプラグインのテスト(`bin/rails redmine:plugins:test NAME=redmine_serverless_s3`)です。Docker の中で、Redmine 7.0.3、PostgreSQL 16 と、`LOCALSTACK_AUTH_TOKEN` があれば LocalStack、なければ moto の S3 を使います。

```sh
bin/test                 # プラグインのテスト。カバレッジを coverage/ に出す
bin/test core            # プラグインを入れた(無効の)状態で、Redmine 本体のテスト
bin/test core-s3         # プラグインを有効にして、Redmine の添付ファイルのテスト
bin/test system          # システムのテスト。ヘッドレスの Chromium で
bin/test <ファイル...>    # プラグインのテストの一部
bin/services --system --down   # PostgreSQL、moto、LocalStack、Chromium を止める
bin/lint                 # RuboCop
node test/javascripts/sha256_test.mjs   # アップロードの JavaScript の SHA-256
```

- **S3:** ユニットと機能のテストでは、SDK の `stub_responses` で S3 を置き換えます。統合のテストは、同じテストを LocalStack(CI で、組織のトークンがあるとき)か moto(フォークからの pull request や、トークンのない手元の実行)で動かします。どちらを使ったかは `bin/test` が出します。moto 5.2.5 は、`x-amz-checksum-sha256` を確認せず、`HeadObject` で `ChecksumSHA256` を返しません(2026-11-09 に確認)。そこで moto では、その `HeadObject` の結果を保存されたバイト列から計算し、この 2 つの S3 の確認のテストは飛ばします。
- **署名付き URL:** テストで鍵のペアを作り、署名付き URL を公開鍵で検証します。
- **置き換えるコード:** 置き換えたりコピーしたりした Redmine のメソッドと、`attachments.js` の `uploadBlob` の SHA256 を、Redmine 7.0.3 のものと比べるテストがあります([attachments.md](attachments.md#replaced-code))。
- **カバレッジ:** `bin/test` は、SimpleCov(Redmine の `COVERAGE`)でプラグインの `app/` と `lib/` のカバレッジを測り、`coverage/coverage.xml`(Cobertura)と HTML のレポートを書きます。
- **CI:** GitHub Actions が、push と pull request ごとに `bin/lint`、SHA-256 のテスト、`bin/test` を実行し、カバレッジを OIDC で [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_s3) に送ります。

<a id="what-the-tests-check"></a>

### テストで確認すること

置き換えるコードにはすべてテストがあり、AWS への呼び出しはすべてこのリポジトリでテストします。S3 が返しうる答えごとに `stub_responses` で、実際の要求は LocalStack か moto に対して確認します(PutObject、`ChecksumMode` 付きの HeadObject、CopyObject、DeleteObjects、ListObjectsV2、GuardDuty が付けるはずのタグでの GetObjectTagging、テストが付ける PutObjectTagging)。

| 対象 | 確認すること | 使うもの |
| --- | --- | --- |
| `files_to_final_location` | Redmine を通るアップロード(REST API、フォーム)を、SHA256 のチェックサム付きで `files/<年>/<月>/` に置き、digest は SHA256 のまま。PutObject が失敗したら保存しない。マルウェアのスキャンを使うときは `incoming/` を通し、脅威は検証のエラーにする | スタブ、LocalStack か moto |
| `readable?`、`diskfile` | ローカルにファイルがあればそれを使い、なければ `HeadObject`。`diskfile` は一時ファイルと名前の変更でオブジェクトを取る。新しいレコードでは何も取らない | スタブ、LocalStack か moto |
| `delete_from_disk!`、`reuse_existing_file_if_possible` | オブジェクトとサムネイルを消す。ほかの添付ファイルが使うファイルは消さない。同じ内容(digest とサイズ)は共有し、新しいオブジェクトを消す | スタブ、LocalStack か moto |
| `thumbnail`、`thumbnailable?` | S3 のサムネイルがあれば使い、なければキャッシュのファイルから ImageMagick で作って `thumbnails/` に置く。キャッシュより大きいものは作らない。リダイレクトに `Cache-Control` が付く | スタブ、LocalStack か moto |
| `/s3_uploads/presign` | 権限、拡張子、サイズ、SHA256 の形を確認する。URL はちょうど `/incoming/<UUID>` の CloudFront の署名付き URL で、公開鍵で検証する | スタブ |
| `/s3_uploads/complete` | チケットが正しく、期限内で、そのユーザーのもの。`ChecksumSHA256`(`FULL_OBJECT`)と `ContentLength` が申告と等しく、そうでなければオブジェクトを消す。同じ内容は共有する。マルウェアのスキャンでは、タグがなければ `202`、`THREATS_FOUND` やほかの状態では断って消す。REST API でも同じ | スタブ、LocalStack か moto |
| `download`、`download_all` | Redmine の権限の確認のあと、`response-content-disposition`(日本語の名前)と `response-content-type` 付きの署名付き URL にリダイレクトする。inline は PDF だけ。zip は 1 ファイルずつ `/tmp` に書き、`tmp/bulk/` に置き、同じ組み合わせなら使い回す | スタブ、LocalStack か moto |
| CSV のインポート | ファイルを `imports/` に置き、持っていない実行環境では取ってくる。マルウェアのスキャンでは、問題がないときだけ読む | スタブ、LocalStack か moto |
| 管理画面のタブ | 設定、読み書きの確認、配信の確認(CSP と `nosniff` のヘッダー、署名のない URL が断られること)、突き合わせのジョブ、マルウェアの記録。管理者だけ。「設定」でタブが開く | スタブ、LocalStack か moto |
| 置き換える Redmine のコード | 置き換えたりコピーしたりしたメソッドと `uploadBlob` の SHA256 が、Redmine 7.0.3 と等しい | — |
| ブラウザー(システムのテスト) | ヘッドレスの Chromium(Selenium、別のコンテナー)で確認する。CloudFront を通したアップロードで、進み具合のバーが 100 まで進み、フォームにトークンが入り、S3 にファイルがある。マルウェアのスキャンの結果がないあいだは `202` で、そのあとアップロードが終わる。リダイレクトをたどったダウンロードで、sandbox の CSP と `nosniff` 付きのファイルが返る。アップロードした画像のサムネイルが出る。CloudFront は、テストのサーバーの小さな Rack アプリケーションで置き換える。署名付き URL を公開鍵で確認し、テストの S3 に PUT と GET をし、ディストリビューションのレスポンスヘッダーを付ける(`test/system/fake_cloudfront.rb`) | LocalStack か moto |
| ブラウザーのスクリプト | SHA-256 を既知の値と Node.js の crypto で、ばらばらの大きさに分けて確認する。`complete` は `202` のあいだ送り直し、最後に諦める | Node.js |

- **AWS では確認していないこと:** LocalStack では、中身が `x-amz-checksum-sha256` と合わない PUT を S3 が断ることと、オブジェクト全体のチェックサムを返すことを確認します。moto では飛ばし、スタブで確認します。CloudFront(署名付き URL の受け付け、OAC、レスポンスヘッダーのポリシー)と GuardDuty は、手元では再現しません。これらは[確認すること](attachments.md#to-verify)と、[Serverless](https://redmine-kit.github.io/serverless/ja/testing.html#checks-after-deployment) のデプロイのあとの確認にあります。
- **Redmine 本体のテスト:** `bin/test core` は、プラグインを入れて無効にした状態で Redmine のテストを実行します。2026-11-10 にすべて(5,832 件)を実行したとき、7 件の失敗は Serverless に一覧がある gem によるもの(rails-dom-testing の `:match`)で、8 件のエラーは Redmine 自身のテストの順番によるものでした。`Redmine::PluginTest` がプラグインのディレクトリを戻さないので、`RoutingPluginsTest` のあとは、入れたプラグインのルートが消え、メニューの項目だけが残ります。この 8 件は、単独で実行すると通ります(2026-11-10)。
- **プラグインを有効にした Redmine の添付ファイルのテスト:** `bin/test core-s3` は、Redmine の添付ファイルのテスト(`test/unit/attachment_test.rb`、`test/unit/attachment_transaction_test.rb`、`test/functional/attachments_controller_test.rb`、`test/functional/attachments_visibility_test.rb`、`test/integration/attachments_test.rb`、`test/integration/api_test/attachments_test.rb`)を、プラグインを有効にして、LocalStack か moto で実行します。140 件が通ります(2026-11-10)。除いた 15 件は、Redmine がファイルそのものを返すこと(ダウンロード、サムネイル、一括のダウンロード、`X-Sendfile`)を前提にしていて、プラグインはそれをリダイレクトに置き換えます。または、前のテストが S3 に置いたサムネイルが使われるものです。[`test/core/s3_exclusions.txt`](../../test/core/s3_exclusions.txt) に、それぞれの理由があります。

<a id="to-verify"></a>

## 確認すること

まだ確認していないことは、[attachments.md](attachments.md#to-verify) にあります。
