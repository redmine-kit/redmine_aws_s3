---
topic: user/attached-files
after: File-storage
---
### Storage in Amazon S3

With [Redmine Kit AWS S3](../aws-s3/attachments.md), attached files are stored in an Amazon S3 bucket instead of the `files` directory. The browser uploads each file straight to S3, and a download goes to a signed URL after Redmine has checked the user's permissions. When the malware scan is on, a file is attached only after the scan finds no threats; a file with threats is blocked, and the form says so.
