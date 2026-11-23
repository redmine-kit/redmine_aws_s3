import type { S3AdminJson } from './api';

// The stories' and tests' data: the plugin's JSON as AwsS3AdminController answers it (the server's strings in Japanese).

export const admin: S3AdminJson = {
  enabled: true,
  bucket_variable: 'REDMINE_S3_BUCKET',
  environment: [
    { name: 'バケット', value: 'redmine-files', note: 'REDMINE_S3_BUCKET' },
    { name: 'リージョン', value: 'ap-northeast-1', note: 'REDMINE_S3_REGION' },
    { name: 'CloudFront ドメイン', value: 'files.example.com', note: 'REDMINE_S3_CLOUDFRONT_DOMAIN' },
    { name: 'CloudFront キーペア ID', value: 'K2JCJMDEHXQW5F', note: 'REDMINE_S3_CLOUDFRONT_KEY_PAIR_ID' },
    { name: 'CloudFront 秘密鍵', value: '設定済み', note: 'REDMINE_S3_CLOUDFRONT_PRIVATE_KEY' },
    { name: 'GuardDuty マルウェアスキャン', value: '有効', note: 'REDMINE_S3_MALWARE_SCAN' },
    { name: 'ローカルキャッシュ', value: '/tmp/files', note: 'attachments_storage_path' },
  ],
  findings: [{ time: '2026/11/23 15:10', result: '脅威を検出', filename: 'invoice.exe', user: { id: 3, name: '鈴木 一郎' }, login: null }],
  reconciliation: {
    rows: [
      { name: '最終実行', value: '2026/11/24 03:00' },
      { name: '添付ファイル数', value: '12,345' },
      { name: 'S3 オブジェクト数', value: '12,346', note: 'files/' },
      { name: 'S3 にないファイル', value: '0' },
      { name: '未使用のオブジェクト', value: '1' },
    ],
    missing: [],
    unused: ['files/2026/11/241123_unused.png'],
  },
  settings: { download_url_expiry: '300', upload_url_expiry: '900', cache_size_mb: '256' },
};

// REDMINE_S3_BUCKET not set: the environment and the settings only
export const off: S3AdminJson = { ...admin, enabled: false, findings: null, reconciliation: null, environment: admin.environment.map((row) => (row.note === 'attachments_storage_path' ? row : { ...row, value: row.note === 'REDMINE_S3_CLOUDFRONT_PRIVATE_KEY' ? '未設定' : row.note === 'REDMINE_S3_MALWARE_SCAN' ? '無効' : '-' })) };

export const checks = {
  results: [
    { name: 'PutObject', ok: true, value: '' },
    { name: 'GetObject', ok: false, value: 'Aws::S3::Errors::NoSuchKey' },
    { name: 'DeleteObject', ok: true, value: '' },
  ],
};
