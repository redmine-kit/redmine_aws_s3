#### Amazon S3 での添付ファイルサイズの上限

[Redmine Kit AWS S3](../aws-s3/attachments.md) が添付ファイルを S3 に保存するときも、「添付ファイルサイズの上限」でアップロードを制限します。フィールドには「S3 では CloudFront Function (/tmp/*) の上限も同じ値にしてください。Lambda では POST /uploads.json は 1 MB まで」と表示します。CloudFront を通すアップロードは `/tmp/*` の CloudFront Function でも制限するので、同じ値にする必要があります。AWS Lambda では、REST API の `POST /uploads.json` は 1 MB までです。
