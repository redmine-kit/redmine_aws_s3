// The plugin's JSON (AwsS3AdminController): the paths the tab reads and writes, and the shapes of its answers.

export const s3Paths = {
  /** GET: the tab; PATCH { settings }: saves the settings */
  admin: '/admin/aws/s3.json',
  /** POST: the read/write check */
  readWrite: '/admin/aws/s3/read_write.json',
  /** POST: the delivery check */
  delivery: '/admin/aws/s3/delivery.json',
  /** POST: starts the consistency check */
  reconcile: '/admin/aws/s3/reconcile.json',
};

/** A row of values (aws_admin/values' rows), formatted by the server; `ok`: a check's result. */
export interface S3Row {
  name: string;
  value?: string | null;
  note?: string | null;
  ok?: boolean;
}

export interface S3Finding {
  time: string;
  result: string;
  filename: string;
  /** the user who added the file, or their login when there is no such user */
  user: { id: number; name: string } | null;
  login: string | null;
}

/** GET /admin/aws/s3.json (AwsS3AdminHelper#aws_s3_admin_json) */
export interface S3AdminJson {
  /** REDMINE_S3_BUCKET is set */
  enabled: boolean;
  bucket_variable: string;
  environment: S3Row[];
  /** the files the malware scan blocked, when the scan is on or there are findings; null otherwise */
  findings: S3Finding[] | null;
  /** the last consistency check, or null */
  reconciliation: { rows: S3Row[]; missing: string[]; unused: string[] } | null;
  settings: Record<string, string>;
}

export interface S3ActionJson {
  notice?: string | null;
  errors?: string[];
  results?: S3Row[];
}

/** The settings in the page's order, each with its unit. */
export const SETTINGS: { name: string; unit?: 'seconds' | 'MB' }[] = [
  { name: 'download_url_expiry', unit: 'seconds' },
  { name: 'upload_url_expiry', unit: 'seconds' },
  { name: 'cache_size_mb', unit: 'MB' },
];
