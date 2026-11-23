import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { KitTestRequest } from '@redmine-kit/plugin/testing';
import { ApiError } from '@redmine-kit/plugin';
import { describe, expect, it } from 'vitest';
import { AwsS3Admin } from './AwsS3Admin';
import { admin, checks, off } from './fixtures';
import { renderKit } from './test/render';

// The S3 tab on the plugin's JSON as AwsS3AdminController answers it.
const ADMIN = 'GET /admin/aws/s3.json';

describe('AwsS3Admin', () => {
  it('shows the environment with each variable, the blocked files and the last consistency check', async () => {
    renderKit(<AwsS3Admin />, { responses: { [ADMIN]: admin } });
    expect(await screen.findByText('redmine-files')).toBeInTheDocument();
    expect(screen.getByText('REDMINE_S3_CLOUDFRONT_PRIVATE_KEY')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '鈴木 一郎' })).toHaveAttribute('href', '/users/3');
    expect(screen.getByText('12,345')).toBeInTheDocument();
    expect(screen.getByText('files/2026/11/241123_unused.png')).toBeInTheDocument();
  });

  it('S3 off: the warning, no tests, no consistency check, the settings', async () => {
    renderKit(<AwsS3Admin />, { responses: { [ADMIN]: off } });
    expect(await screen.findByText('REDMINE_S3_BUCKET が未設定のため、添付ファイルはローカルディスクに保存します。')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '読み書きテスト' })).toBeNull();
    expect(screen.queryByRole('button', { name: '整合性チェックを実行' })).toBeNull();
    expect(screen.getByRole('textbox', { name: 'ダウンロード URL の有効期限' })).toHaveValue('300');
  });

  it('runs the read/write test and shows each step; starts the consistency check', async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsS3Admin />, {
      requests,
      responses: { [ADMIN]: admin, 'POST /admin/aws/s3/read_write.json': checks, 'POST /admin/aws/s3/reconcile.json': { notice: '整合性チェックを開始しました。', errors: [] } },
    });
    await user.click(await screen.findByRole('button', { name: '読み書きテスト' }));
    expect(await screen.findByText('Aws::S3::Errors::NoSuchKey')).toBeInTheDocument();
    expect(screen.getAllByRole('img', { name: 'OK' })).toHaveLength(2);
    expect(screen.getByRole('img', { name: '失敗' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '整合性チェックを実行' }));
    expect(await screen.findByText('整合性チェックを開始しました。')).toBeInTheDocument();
    expect(requests.filter((r) => r.method === 'post').map((r) => r.path)).toEqual(['/admin/aws/s3/read_write.json', '/admin/aws/s3/reconcile.json']);
  });

  it("saves the settings, and shows Redmine's errors", async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsS3Admin />, {
      requests,
      responses: { [ADMIN]: admin, 'PATCH /admin/aws/s3.json': new ApiError(422, ['正の整数を入力してください: ダウンロード URL の有効期限']) },
    });
    const field = await screen.findByRole('textbox', { name: 'ダウンロード URL の有効期限' });
    await user.clear(field);
    await user.type(field, '0');
    await user.click(screen.getByRole('button', { name: /^保存/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent('正の整数を入力してください');
    expect(requests.find((r) => r.method === 'patch')?.body).toEqual({ settings: { ...admin.settings, download_url_expiry: '0' } });
  });

  it('is a skeleton while it loads, and the error state when it cannot be read', async () => {
    const { unmount } = renderKit(<AwsS3Admin />, { responses: { [ADMIN]: new Promise(() => {}) } });
    expect(screen.getByRole('status', { name: 'ロード中...' })).toBeInTheDocument();
    unmount();
    renderKit(<AwsS3Admin />, { responses: { [ADMIN]: new ApiError(500, []) } });
    expect(await screen.findByRole('button', { name: /再読み込み|再試行/ })).toBeInTheDocument();
  });
});
