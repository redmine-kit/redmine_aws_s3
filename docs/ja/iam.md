# IAM の権限

プラグインを入れた Redmine を動かすプロセス(画面の要求、ジョブ、rake)には、どれもバケットへの同じ権限を渡します。ブラウザーはこの認証情報を使いません。アップロードとダウンロードは、CloudFront の秘密鍵で署名した URL で、CloudFront を通ります。

<a id="permissions"></a>

## 権限

| 操作 | 対象 | 理由 |
| --- | --- | --- |
| `s3:GetObject`<br>`s3:PutObject`<br>`s3:DeleteObject` | バケットの<br>`files/*`<br>`imports/*`<br>`tmp/*` | 添付ファイル、Markdown のプレビュー、サムネイルの保存と削除、登録のときのチェックサム付きの `HeadObject` と `tmp/incoming/` からのコピー、合わないアップロードの削除、CSV のインポート、一括のダウンロードの zip、読み書きの確認(`tmp/healthcheck/`) |
| `s3:GetObjectTagging` | バケットの<br>`tmp/incoming/*`<br>`imports/*` | マルウェアのスキャンを使うときに、GuardDuty の結果を読む([attachments.md](attachments.md#malware-scan)) |
| `s3:ListBucket` | バケット | ないオブジェクトへの `HeadObject` を、403 でなく 404 にする。前方一致でのサムネイルの削除、突き合わせ、接続の確認の `HeadBucket` |
| CloudFront の秘密鍵を読む | それを入れた秘密の値(Serverless では、[Redmine Serverless SSM](https://redmine-kit.github.io/redmine_serverless_ssm/ja/) を通した、`/<instance>/env/` への `ssm:GetParametersByPath`) | CloudFront の URL の署名 |

<a id="example-policy"></a>

## ポリシーの例

プラグインを入れた Redmine を動かす、すべてのプロセスのポリシーです。

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
        "arn:aws:s3:::<bucket>/imports/*",
        "arn:aws:s3:::<bucket>/tmp/*"
      ]
    },
    {
      "Sid": "ScanResults",
      "Effect": "Allow",
      "Action": "s3:GetObjectTagging",
      "Resource": ["arn:aws:s3:::<bucket>/tmp/incoming/*", "arn:aws:s3:::<bucket>/imports/*"]
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

<a id="resource-based-policies"></a>

## リソースベースのポリシー

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
        "arn:aws:s3:::<bucket>/tmp/thumbnails/*",
        "arn:aws:s3:::<bucket>/tmp/bulk/*"
      ],
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account>:distribution/<distribution ID>" } }
    },
    {
      "Sid": "CloudFrontUpload",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<bucket>/tmp/incoming/*",
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account>:distribution/<distribution ID>" } }
    }
  ]
}
```

マルウェアのスキャンを使うときに、問題がないとわかる前のアップロードとインポートのファイルの読み取りを拒むバケットポリシーです。2 つの条件がどちらも成り立つときだけ拒むので、GuardDuty のロールはスキャンのためにオブジェクトを読めます。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ScannedOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": ["arn:aws:s3:::<bucket>/tmp/incoming/*", "arn:aws:s3:::<bucket>/imports/*"],
      "Condition": {
        "StringNotEquals": {
          "s3:ExistingObjectTag/GuardDutyMalwareScanStatus": "NO_THREATS_FOUND",
          "aws:PrincipalArn": "arn:aws:iam::<account>:role/<GuardDuty Malware Protection role>"
        }
      }
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

<a id="not-checked-yet"></a>

## 未確認の事項

- OAC を使う CloudFront が、チェックサムのヘッダーを付けた `tmp/incoming/` への PUT を通すか。ほかは [attachments.md](attachments.md#to-verify) の項目です。
