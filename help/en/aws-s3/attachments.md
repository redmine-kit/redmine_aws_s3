# Attachments in Amazon S3

Redmine Kit AWS S3 stores Redmine's attachments in an Amazon S3 bucket when the environment variable `REDMINE_S3_BUCKET` is set; without it, attachments stay on the local disk. Browsers upload files through Redmine's CloudFront distribution straight to S3, and download them through signed URLs on the same domain, after Redmine has checked the user's permissions as usual. Users add and open attachments as before.

## Uploading files

The attach files form works as in Redmine, with its progress bar. When the GuardDuty malware scan is on (`REDMINE_S3_MALWARE_SCAN`), Redmine registers a file only after the scan finds no threats:

- While the scan has not finished, the form waits and asks again; after a while it shows "The malware scan of the file has not finished. Try again later."
- A file with threats is deleted and blocked: "The malware scan found threats, so the file was blocked."
- A file the scan could not finish is blocked too: "The malware scan did not complete, so the file was blocked (…)."

## The S3 tab

**Administration** › **AWS** › **S3** shows how the plugin is set up. Only administrators can open it. AWS is called only when one of its links is clicked; each of them is written to Redmine's log.

- **Environment variables**: **Bucket**, **Region**, **CloudFront domain**, **CloudFront key pair ID**, **CloudFront private key** (only **Set** or **Not set**), **GuardDuty malware scan** and **Local cache**, each with the variable it comes from.
- **Connection tests**: **Read/write test** puts, reads and deletes a test object in the bucket; **Delivery test** fetches a test object through CloudFront with a signed URL and checks that the unsigned URL is denied. A failed call shows only the class of the error.
- **Files blocked by malware scan**: the last 20 blocked files, with **Time**, **Scan result**, the file name and the **User**.
- **Consistency check**: **Run consistency check** compares the attachments in the database with the objects in the bucket, in a background job, and shows **Attachments**, **S3 objects**, **Files missing in S3** and **Unused objects**.
- **Settings**: **Download URL expiry** and **Upload URL expiry** (seconds) and **Cache size limit** (MB), positive whole numbers. **Save** saves them.

Without the bucket, the tab shows a warning, the environment variables and the settings only. **Configure** of Redmine Kit AWS S3 in **Administration** › **Plugins** opens this tab.
