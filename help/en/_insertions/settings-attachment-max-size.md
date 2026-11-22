---
topic: admin/settings
after: Attachment-max-size
---
#### Maximum attachment size with Amazon S3

When [Redmine Kit AWS S3](../aws-s3/attachments.md) stores attachments in S3, **Maximum attachment size** still limits uploads, and the field gets the note "With S3, keep the CloudFront Function (/tmp/*) limit the same. On Lambda, POST /uploads.json is limited to 1 MB": uploads through CloudFront are also limited by the CloudFront Function on `/tmp/*`, which must have the same value, and on AWS Lambda the REST API's `POST /uploads.json` takes at most 1 MB.
