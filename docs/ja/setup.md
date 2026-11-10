# 導入

Redmine Serverless S3 を使う Redmine に要るもの(インストール、設定、バケット、CloudFront のディストリビューション、IAM の権限、ネットワーク)です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは開発の初期の段階です。下のコードは作ってあり、moto でテストしています。本物の CloudFront のディストリビューションが要る部分は、[未確認の事項](#to-verify)にあります。

<a id="requirements"></a>

## 動作環境

- Redmine 7.0 以降。
- AWS の認証情報で S3 に届くプロセス(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。Redmine にアクセスキーは置きません。
- Redmine を CloudFront のディストリビューションで配っていること。ブラウザーは、ファイルのアップロードとダウンロードも、これを通して行い、S3 のドメインには触れません([attachments.md](attachments.md#upload))。

<a id="installation"></a>

## インストール

1. プラグインを `plugins/redmine_serverless_s3` に置きます。gem をインストールするか([gem](#gem))、リポジトリをクローンします([gem を使わないとき](#without-the-gem))。
2. `bundle install` を実行します。Redmine の `Gemfile` がプラグインの `Gemfile` を読み込み、プラグインが、オブジェクト全体のチェックサム(`ChecksumType`)を持つ 1.178 以降の `aws-sdk-s3` と、1.x の `aws-sdk-cloudfront` を追加します。
3. migration は要りません。
4. プラグインの JavaScript `s3_upload.js` を配るために、アセットを作ります(Redmine のいつものアセットの手順でもかまいません)。

   ```sh
   bin/rails assets:precompile
   ```

5. 環境変数を設定します(下記)。`REDMINE_S3_BUCKET` がなければ、プラグインは動かず、Redmine は標準のとおりディスクに添付ファイルを置きます。

<a id="gem"></a>

### gem

バージョンのタグごとに、プラグインを gem として GitHub Packages(`https://rubygems.pkg.github.com/redmine-kit`)に公開します。いまのバージョンは 0.1.3 です。GitHub Packages からインストールするには、公開のパッケージでも、`read:packages` の権限を持つ GitHub のトークンが要ります。gem は、プラグインを動かすためのファイルを持ちます。Redmine は `plugins/` のプラグインだけを読み込むので、インストールした gem をそこにリンクします。

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

<a id="without-the-gem"></a>

### gem を使わないとき

リポジトリを `plugins/redmine_serverless_s3` にクローンし、gem をインストールします。

```sh
git clone https://github.com/redmine-kit/redmine_serverless_s3.git plugins/redmine_serverless_s3
bundle install
```

<a id="configuration"></a>

## 設定

| キー | 説明 | パラメーター |
| --- | --- | --- |
| `REDMINE_S3_BUCKET` | 添付ファイルのバケット。これでプラグインが有効になる。なければ、Redmine は標準のとおりに動く | 必須 |
| `REDMINE_S3_REGION` | バケットのリージョン | 省略可。既定は `AWS_REGION`、次に `AWS_DEFAULT_REGION` |
| `REDMINE_CLOUDFRONT_DOMAIN` | Redmine のディストリビューションのドメイン。`/files/`、`/tmp/thumbnails/`、`/tmp/bulk/`、`/tmp/incoming/` の下の署名付き URL に使う | 必須。例: `redmine.example.com` |
| `REDMINE_CLOUDFRONT_KEY_PAIR_ID` | ディストリビューションの信頼されたキーグループの公開鍵の ID | 必須 |
| `REDMINE_CLOUDFRONT_PRIVATE_KEY` | CloudFront の URL に署名する PEM の秘密鍵。ファイルやログには書かず、管理画面にも出さない | 必須。秘密の値。Serverless では SSM の SecureString `/<instance>/env/REDMINE_CLOUDFRONT_PRIVATE_KEY` |
| `REDMINE_S3_MALWARE_SCAN` | アップロードとインポートのファイルを使う前に、GuardDuty Malware Protection for S3 の結果を待つ([attachments.md](attachments.md#malware-scan)) | 省略可。`true` で有効。ほかの値やないときは無効 |

| 項目 | 説明 | 変える場所 |
| --- | --- | --- |
| ダウンロード URL の有効期限、アップロード URL の有効期限 | 既定は、ダウンロードとサムネイルが 300 秒、アップロードが 900 秒([attachments.md](attachments.md#upload)) | プラグインの設定([管理画面](admin.md#attachments-in-s3)) |
| ローカルキャッシュサイズの上限 | 既定は 256 MB([attachments.md](attachments.md#the-tmp-cache)) | プラグインの設定(管理画面) |
| `attachments_storage_path` | 手元のキャッシュのディレクトリ。Lambda では `/tmp` の下(例: `/tmp/redmine/files`) | `config/configuration.yml` |
| 添付ファイルの最大の大きさ | これまでどおり変えられる。`/tmp/*` の CloudFront Functions は、アップロードに同じ上限を使う必要がある([admin.md](admin.md#maximum-attachment-size)) | Redmine の設定 |

Serverless では、[Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/ja/) が、`/<instance>/env/` の下のパラメーターを環境変数に読み込みます。S3 のクライアントは、SDK の標準の方法で認証情報を探します。Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロールです。プラグインが自分でアクセスキーを読むことはありません。

管理画面の整合性チェックは、Active Job の `ServerlessS3ReconcileJob` として動きます。実行してよいジョブのクラスを一覧で決めるキュー([Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/ja/) など)を通すときは、このクラスを一覧に追加します。

<a id="aws-resources"></a>

## AWS リソース

<a id="the-bucket"></a>

### バケット

バケットは 1 つで、キーは [attachments.md](attachments.md#bucket-layout) のとおりです。

| 項目 | 設定 |
| --- | --- |
| バージョニング | 有効。古いバージョンは 30 日で消す |
| ライフサイクル | `tmp/incoming/`、`tmp/bulk/`、`tmp/healthcheck/` は 1 日、`imports/` は 7 日、古いバージョンは 30 日で消す。サムネイル(`tmp/thumbnails/`)は消さない |
| 暗号化 | SSE-S3(S3 の既定) |
| 公開 | S3 のパブリックアクセスのブロックを有効にする。TLS でない要求は、バケットポリシーで拒む(`aws:SecureTransport` が `false`) |
| CORS | なし。ブラウザーは Redmine のドメインだけを使う |
| バケットポリシー | TLS でない要求を拒む。Redmine の CloudFront のディストリビューションに、オリジンアクセスコントロール(OAC)を通して、`files/`、`tmp/thumbnails/`、`tmp/bulk/` の読み取りと、`tmp/incoming/` への書き込みを許す。マルウェアスキャンを使うときは、問題がないとわかる前の `tmp/incoming/` と `imports/` の読み取りを拒む |
| マルウェアスキャン(使うときだけ) | バケットに GuardDuty Malware Protection for S3 のプランを付け、対象を `tmp/incoming/` と `imports/` にし、スキャンしたオブジェクトへのタグ付けを有効にする。`REDMINE_S3_MALWARE_SCAN=true` にする([attachments.md](attachments.md#malware-scan)) |

バケットに届くのは、OAC を通した CloudFront と、Redmine を動かすプロセスのロールだけです。ブラウザーに S3 の署名付き URL は渡しません。

<a id="the-cloudfront-distribution"></a>

### CloudFront のディストリビューション

プラグインは、Redmine 自身のディストリビューションを使い、2 つめのディストリビューションは要りません。次のものを追加します。

| 項目 | 設定 |
| --- | --- |
| オリジン | 添付ファイルのバケット。要求に署名するオリジンアクセスコントロール(OAC)を付ける |
| ビヘイビア `/files/*` | 添付ファイル。GET と HEAD。署名付き URL を必須にする(下の信頼されたキーグループ)。マネージドのキャッシュポリシーの CachingDisabled(クエリーを S3 に渡さない)、オリジンリクエストポリシーはなし、マネージドのレスポンスヘッダーポリシーの SecurityHeadersPolicy (`X-Content-Type-Options: nosniff` を付ける)。ビューワーレスポンスの CloudFront Functions が、`Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox` を付け、クエリーの `response-content-disposition` と `response-content-type` から `Content-Disposition` と `Content-Type` を設定する([attachments.md](attachments.md#download)) |
| ビヘイビア `/tmp/*` | サムネイル(`/tmp/thumbnails/`)と zip(`/tmp/bulk/`)を GET で、アップロード(`/tmp/incoming/`)を PUT で受ける。すべてのメソッド、HTTPS だけ。署名付き URL を必須にする。ポリシーとビューワーレスポンスの関数は `/files/*` と同じ。ビューワーリクエストの CloudFront Functions が、`/tmp/incoming/` への PUT で `Content-Length` がアップロードの上限を超えるものを拒否する ([attachments.md](attachments.md#upload)) |
| 信頼されたキーグループ | Redmine が URL の署名に使う秘密鍵の、公開鍵 |
| ほかのビヘイビア | 今までどおり Redmine。本文のハッシュを入れる関数は、これらだけに付ける |

これらのビヘイビアが Redmine の画面を隠すことはありません。Redmine には、`/files`、`/tmp` で始まるルートがないためです(2026-11-09 に Redmine 7.0.3 で確認。[attachments.md](attachments.md#download))。

sandbox の CSP は外さないでください。添付ファイルは Redmine のオリジンから返るので、そこでスクリプトを動かさないようにしているのは、このポリシーです。ディストリビューションを変えるたびに、`/files/` の下の応答にこのポリシーが付いていることを確認します。

キーペアの秘密鍵は一度だけ作り、秘密の値として保存します。CloudFront には公開鍵だけを入れます。Serverless は、デプロイのときにキーペアを作ります。

<a id="iam-permissions"></a>

## IAM 権限

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
node test/javascripts/complete_test.mjs # アップロードの JavaScript の完了処理
```

<a id="how-aws-is-tested"></a>

### AWS とのテストの方法

ユニットと機能のテストでは、SDK の `stub_responses` で S3 を置き換えます。統合のテストは同じテストを、CI では組織のトークンで LocalStack に対して、フォークからの pull request やトークンのない手元の実行では moto に対して動かします。moto 5.2.5 は、`HeadObject` で `ChecksumSHA256` を返しません (2026-11-09 に確認)。そこで moto では、その `HeadObject` の結果を保存されたバイト列から計算し、S3 のチェックサムの 2 つのテストはスキップします。署名付き URL は、テストで作った鍵のペアの公開鍵で検証します。

<a id="replaced-code-coverage-and-ci"></a>

### 置き換えたコード、カバレッジ、CI

置き換えたりコピーしたりした Redmine のメソッドと、`attachments.js` の `uploadBlob` の SHA256 を、Redmine 7.0.3 のものと比べるテストがあります([attachments.md](attachments.md#replaced-code))。`bin/test` は、SimpleCov(Redmine の `COVERAGE`)でプラグインの `app/` と `lib/` のカバレッジを測り、`coverage/coverage.xml`(Cobertura)と HTML のレポートを書きます。GitHub Actions は、push と pull request のたびに `bin/lint`、SHA-256 のテスト、`bin/test` を実行し、カバレッジを OIDC で [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_s3) に送ります。

<a id="what-the-tests-check"></a>

### テストで確認する内容

置き換えるコードにはすべてテストがあり、AWS への呼び出しはすべてこのリポジトリでテストします。S3 が返しうる答えごとに `stub_responses` で、実際の要求は LocalStack か moto に対して確認します(PutObject、`ChecksumMode` 付きの HeadObject、CopyObject、DeleteObjects、ListObjectsV2、GuardDuty が付けるはずのタグでの GetObjectTagging、テストが付ける PutObjectTagging)。

| 対象 | 確認すること | 使うもの |
| --- | --- | --- |
| `files_to_final_location` | Redmine を通るアップロード(REST API、フォーム)を、SHA256 のチェックサム付きで `files/<年>/<月>/` に置き、digest は SHA256 のまま。PutObject が失敗したら保存しない。マルウェアスキャンを使うときは `tmp/incoming/` を通し、脅威は検証のエラーにする | スタブ、LocalStack か moto |
| `readable?`<br>`diskfile` | ローカルにファイルがあればそれを使い、なければ `HeadObject`。`diskfile` は一時ファイルと名前の変更でオブジェクトを取る。新しいレコードでは何も取らない | スタブ、LocalStack か moto |
| `delete_from_disk!`<br>`reuse_existing_file_if_possible` | オブジェクトとサムネイルを消す。ほかの添付ファイルが使うファイルは消さない。同じ内容(digest とサイズ)は共有し、新しいオブジェクトを消す | スタブ、LocalStack か moto |
| `thumbnail`<br>`thumbnailable?` | S3 のサムネイルがあれば使い、なければキャッシュのファイルから ImageMagick で作って `tmp/thumbnails/` に置く。キャッシュより大きいものは作らない。リダイレクトに `Cache-Control` が付く | スタブ、LocalStack か moto |
| `/s3_uploads/presign` | 権限、拡張子、サイズを確認する。URL はちょうど `/tmp/incoming/<UUID>` の CloudFront の署名付き URL で、公開鍵で検証する | スタブ |
| `/s3_uploads/complete` | チケットが正しく、期限内で、そのユーザーのもの。アップロードを `ChecksumAlgorithm` に `SHA256` を指定して `files/` にコピーして削除し、コピーの `ChecksumSHA256` (`FULL_OBJECT`) をダイジェストにする。コピーの `ContentLength` が申告と一致しなければ、コピーを削除する。同じ内容は共有し、余分なコピーを削除する。マルウェアスキャンでは、タグがなければ `202`、`THREATS_FOUND` やほかのスキャン結果ではファイルをブロックして消す。REST API でも同じ | スタブ、LocalStack か moto |
| `download`<br>`download_all` | Redmine の権限の確認のあと、`response-content-disposition`(日本語の名前)と `response-content-type` 付きの署名付き URL にリダイレクトする。inline は PDF だけ。zip は 1 ファイルずつ `/tmp` に書き、`tmp/bulk/` に置き、同じ組み合わせなら使い回す | スタブ、LocalStack か moto |
| CSV のインポート | ファイルを `imports/` に置き、持っていない実行環境では取ってくる。マルウェアスキャンでは、問題がないときだけ読む | スタブ、LocalStack か moto |
| 管理画面のタブ | 設定、読み書きテスト、配信テスト(CSP と `nosniff` のヘッダー、署名のない URL が拒否されること)、整合性チェックのジョブ、マルウェアスキャンでブロックしたファイル。管理者だけ。「設定」でタブが開く | スタブ、LocalStack か moto |
| 置き換える Redmine のコード | 置き換えたりコピーしたりしたメソッドと `uploadBlob` の SHA256 が、Redmine 7.0.3 と等しい | — |
| ブラウザー(システムのテスト) | ヘッドレスの Chromium(Selenium、別のコンテナー)で確認する。CloudFront を通したアップロードで、進み具合のバーが 100 まで進み、フォームにトークンが入り、S3 にファイルがある。マルウェアスキャンの結果がないあいだは `202` で、そのあとアップロードが終わる。リダイレクトをたどったダウンロードで、sandbox の CSP と `nosniff` 付きのファイルが返る。アップロードした画像のサムネイルが出る。CloudFront は、テストのサーバーの小さな Rack アプリケーションで置き換える。署名付き URL を公開鍵で確認し、テストの S3 に PUT と GET をし、ディストリビューションのレスポンスヘッダーを付ける(`test/system/fake_cloudfront.rb`) | LocalStack か moto |
| ブラウザーのスクリプト | SHA-256 を既知の値と Node.js の crypto で、ばらばらの大きさに分けて確認する。`complete` は `202` のあいだ送り直し、最後に諦める | Node.js |

<a id="not-checked-against-aws"></a>

### AWS では確認していないこと

LocalStack では、`ChecksumAlgorithm` に `SHA256` を指定したコピーに、単一の PUT からでもマルチパートアップロードからでも、オブジェクト全体の SHA256 が付くことを確認します。moto ではこの 2 つをスキップし、スタブで確認します。CloudFront(署名付き URL の受け付け、OAC、関数)と GuardDuty は、手元では再現しません。これらは、[未確認の事項](attachments.md#to-verify)と、[Serverless](https://redmine-kit.github.io/serverless/ja/testing.html#checks-after-deployment) のデプロイのあとの確認にあります。

<a id="redmines-own-tests"></a>

### Redmine 本体のテスト

`bin/test core` は、プラグインを入れて無効にした状態で、Redmine のテストを実行します。2026-11-10 にすべて(5,832 件)を実行したとき、7 件の失敗は、Serverless に一覧がある gem によるもの(rails-dom-testing の `:match`)でした。8 件のエラーは、Redmine 自身のテストの順番によるものです。`Redmine::PluginTest` がプラグインのディレクトリを戻さないので、`RoutingPluginsTest` のあとは、入れたプラグインのルートが消え、メニューの項目だけが残ります。この 8 件は、単独で実行すると通ります(2026-11-10)。

`bin/test core-s3` は、Redmine の添付ファイルのテスト(`test/unit/attachment_test.rb`、`test/unit/attachment_transaction_test.rb`、`test/functional/attachments_controller_test.rb`、`test/functional/attachments_visibility_test.rb`、`test/integration/attachments_test.rb`、`test/integration/api_test/attachments_test.rb`)を、プラグインを有効にして、LocalStack か moto で実行します。140 件が通ります(2026-11-10)。除いた 15 件は、Redmine がファイルそのものを返すこと(ダウンロード、サムネイル、一括のダウンロード、`X-Sendfile`)を前提にしたものか、前のテストが S3 に置いたサムネイルが使われるものです。プラグインは、ファイルを返す部分をリダイレクトに置き換えます。[`test/core/s3_exclusions.txt`](../../test/core/s3_exclusions.txt) に、それぞれの理由があります。

<a id="to-verify"></a>

## 未確認の事項

まだ確認していないことは、[attachments.md](attachments.md#to-verify) にあります。
