import { useState } from 'react';
import {
  AttrGrid,
  AttrGridSkeleton,
  Button,
  CardBody,
  CardSection,
  DataTable,
  EmptyState,
  FormActions,
  FormRow,
  Icon,
  Input,
  ListRow,
  Notice,
  RequestErrorState,
  SectionHeading,
  SkeletonRegion,
  useFormDirty,
  type DataTableColumn,
  type DataTableRowBase,
} from '@redmine-kit/ui';
import { AppLink, useApiErrorTexts, useKitMutation, useKitQuery, useT } from '@redmine-kit/plugin';
import { SETTINGS, s3Paths, type S3ActionJson, type S3AdminJson, type S3Finding, type S3Row } from './api';

// Administration › AWS › S3 (/admin/aws/s3: the manifest's layout: admin screen with menu_item aws, its tab
// label_aws_s3_admin at position 50), as Redmine's page shows it (app/views/aws_s3_admin/show.html.erb); AWS is called
// only when a button is pressed:
// - without REDMINE_S3_BUCKET, the warning that attachments stay on the local disk (and only 環境変数 and 設定);
// - 環境変数: each value with its variable (the private key as 設定済み / 未設定, never its value);
// - 接続テスト: 読み書きテスト and 配信テスト (POST), then each step's result;
// - マルウェアスキャンでブロックしたファイル, when the scan is on or files were blocked;
// - 整合性チェック: 整合性チェックを実行 (POST, the job), the last check's values and its keys;
// - 設定: the plugin's settings, saved with 保存 (PATCH, the page's form; Redmine's errors above the tab).
// Every value comes formatted by the server (Redmine's helpers); the actions are the page's, behind require_admin.

/** Redmine's .tabular labels (175px), as the classic page's values line up. */
const LABEL_WIDTH = 175;

interface FindingRow extends DataTableRowBase {
  finding: S3Finding;
}

/** Values as label and value pairs, each note muted under its value (AttrGrid's note: the classic page's em.info). */
function Values({ rows }: { rows: S3Row[] }) {
  return (
    <div className="px-gutter">
      <AttrGrid
        columns={1}
        labelWidth={LABEL_WIDTH}
        items={rows.map((row) => ({ label: row.name, value: row.value ?? '', note: row.note }))}
      />
    </div>
  );
}

export function AwsS3Admin() {
  const t = useT();
  const query = useKitQuery<S3AdminJson>(s3Paths.admin);
  const action = useKitMutation<S3ActionJson>();
  const errorTexts = useApiErrorTexts();
  const [result, setResult] = useState<S3ActionJson | null>(null);
  const run = (path: string) => {
    setResult(null);
    action.mutate({ method: 'post', path, body: {} }, { onSuccess: (data) => setResult(data ?? null) });
  };
  if (query.isError)
    return (
      <CardBody>
        <RequestErrorState error={query.error} onRetry={() => void query.refetch()} retrying={query.isFetching} />
      </CardBody>
    );
  const data = query.data;
  const errors = errorTexts(action.error);
  const findingColumns: DataTableColumn<FindingRow>[] = [
    { key: 'time', label: t('label_aws_s3_time'), type: 'text', value: (r) => r.finding.time },
    { key: 'result', label: t('label_aws_s3_scan_result'), type: 'text', value: (r) => r.finding.result },
    { key: 'filename', label: t('field_filename'), type: 'text', value: (r) => r.finding.filename },
    {
      key: 'user',
      label: t('label_user'),
      type: 'text',
      value: (r) => r.finding.user?.name ?? r.finding.login ?? '',
      cell: (r) => (r.finding.user ? <AppLink href={`/users/${r.finding.user.id}`}>{r.finding.user.name}</AppLink> : (r.finding.login ?? '')),
    },
  ];
  if (!data)
    return (
      <CardBody>
        <CardSection line={false} heading={t('label_aws_s3_environment')}>
          <SkeletonRegion label={t('label_loading')} className="px-gutter">
            <AttrGridSkeleton
              columns={1}
              labelWidth={LABEL_WIDTH}
              items={['bucket', 'region', 'domain', 'key_pair_id', 'private_key', 'malware_scan', 'storage_path'].map((name) => ({ label: t(`field_aws_s3_${name}`), note: true }))}
            />
          </SkeletonRegion>
        </CardSection>
      </CardBody>
    );
  return (
    <CardBody>
      {!data.enabled && <Notice tone="warning" text={t('text_aws_s3_off', { name: data.bucket_variable })} wrap />}
      {result?.notice && <Notice tone="neutral" text={result.notice} />}
      {errors.length > 0 && <Notice tone="danger" role="alert" text={errors.join('\n')} wrap />}
      <CardSection line={false} heading={t('label_aws_s3_environment')}>
        <Values rows={data.environment} />
      </CardSection>
      {data.enabled && (
        <>
          <CardSection
            heading={t('label_aws_s3_checks')}
          >
            {/* the page's links under the heading (a heading with two actions would squeeze its title at a phone's width) */}
            <div className="mb-3 flex flex-wrap items-center gap-2 px-gutter">
              <Button size={28} disabled={action.isPending} onClick={() => run(s3Paths.readWrite)}>
                {t('button_aws_s3_read_write')}
              </Button>
              <Button size={28} disabled={action.isPending} onClick={() => run(s3Paths.delivery)}>
                {t('button_aws_s3_delivery')}
              </Button>
            </div>
            {result?.results?.map((row, i, rows) => (
              // a step as the AWS page's Status tab shows a check (ListRow): its name, what it found under it, its state
              <ListRow
                key={`${row.name}-${i}`}
                title={row.name}
                sub={row.value || undefined}
                divider={i < rows.length - 1}
                cols={[
                  {
                    content: (
                      <span className={row.ok ? 'flex text-accent' : 'flex text-warning'} role="img" aria-label={row.ok ? t('label_aws_ok') : t('label_aws_failed')}>
                        <Icon name={row.ok ? 'check' : 'warning'} size={16} />
                      </span>
                    ),
                  },
                ]}
              />
            ))}
          </CardSection>
          {data.findings && (
            <CardSection heading={t('label_aws_s3_malware_findings')}>
              {data.findings.length === 0 ? (
                <EmptyState />
              ) : (
                <DataTable<FindingRow>
                  label={t('label_aws_s3_malware_findings')}
                  columns={findingColumns}
                  rows={data.findings.map((finding, i) => ({ id: String(i), finding }))}
                />
              )}
            </CardSection>
          )}
          <CardSection
            heading={t('label_aws_s3_reconciliation')}
            actions={
              <Button size={28} disabled={action.isPending} onClick={() => run(s3Paths.reconcile)}>
                {t('button_aws_s3_reconcile')}
              </Button>
            }
          >
            {!data.reconciliation ? (
              <EmptyState />
            ) : (
              <div className="flex flex-col gap-3">
                <Values rows={data.reconciliation.rows} />
                {(['missing', 'unused'] as const).map((kind) =>
                  data.reconciliation![kind].length > 0 ? (
                    <div key={kind}>
                      <SectionHeading heading={t(`field_aws_s3_${kind}`)} level={3} inset={24} count={data.reconciliation![kind].length} />
                      {data.reconciliation![kind].map((key) => (
                        <ListRow key={key} title={key} mono size={32} />
                      ))}
                    </div>
                  ) : null,
                )}
              </div>
            )}
          </CardSection>
        </>
      )}
      <CardSection heading={t('label_settings')}>
        <SettingsForm key={JSON.stringify(data.settings)} settings={data.settings} />
      </CardSection>
    </CardBody>
  );
}

/** 設定: the plugin's settings as the page's form has them, with their units; 保存 saves them (PATCH { settings }). */
function SettingsForm({ settings }: { settings: Record<string, string> }) {
  const t = useT();
  const save = useKitMutation<S3ActionJson>(s3Paths.admin, 'patch');
  const errorTexts = useApiErrorTexts();
  const [values, setValues] = useState(settings);
  const form = useFormDirty(values);
  const errors = errorTexts(save.error);
  return (
    <>
      {save.isSuccess && !form.dirty && <Notice tone="neutral" role="status" text={t('notice_successful_update')} />}
      {errors.length > 0 && <Notice tone="danger" role="alert" text={errors.join('\n')} wrap />}
      <div className="box-content flex max-w-215 flex-col gap-4 px-6">
        {SETTINGS.map(({ name, unit }) => (
          <FormRow key={name} label={t(`field_aws_s3_${name}`)}>
            <span className="flex items-center gap-2">
              <Input
                aria-label={t(`field_aws_s3_${name}`)}
                inputMode="numeric"
                value={values[name] ?? ''}
                onChange={(e) => setValues({ ...values, [name]: e.target.value })}
                className="w-24"
              />
              {unit && <span>{unit === 'seconds' ? t('label_aws_s3_seconds') : 'MB'}</span>}
            </span>
          </FormRow>
        ))}
      </div>
      {/* edge: the tab's body has no gutter (its sections bring their own), so the row brings its own */}
      <FormActions edge>
        <Button data-form-cancel variant="ghost" disabled={!form.dirty || save.isPending} onClick={() => setValues(form.saved)}>
          {t('button_cancel')}
        </Button>
        <Button submit="primary" variant="primary" disabled={!form.dirty || save.isPending} onClick={() => save.mutate({ settings: values }, { onSuccess: () => form.markSaved() })}>
          {t('button_save')}
        </Button>
      </FormActions>
    </>
  );
}
