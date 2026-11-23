import type { ReactNode } from 'react';
import { render } from '@testing-library/react';
import { KitTestHost, type KitTestHostProps } from '@redmine-kit/plugin/testing';
import { ConfirmProvider } from '@redmine-kit/ui'; // check-ui-ok: a test; the app mounts the confirmations' provider (confirmAction) around a plugin's components
import { resolve } from 'node:path';
import { kitCatalog } from '@redmine-kit/plugin/locales';

// A component of the module in a test, with the app's part (KitTestHost): the strings as Redmine loads them (Redmine
// 7.0.3's and redmine_kit_ui's, then the plugin's config/locales), the same as its Storybook's; the permissions given.

// with redmine_kit_aws's, which this plugin requires (its strings are in Redmine's I18n with the plugin's: the checks'
// states, label_aws_ok and label_aws_failed)
const AWS = (language: string) => kitCatalog(language, { root: resolve(process.cwd(), '../../redmine_kit_aws') });
export const JA = { ...AWS('ja'), ...kitCatalog('ja') };
export const EN = { ...AWS('en'), ...kitCatalog('en') };

export function renderKit(ui: ReactNode, { lang = 'ja', ...props }: Omit<KitTestHostProps, 'children'> & { lang?: 'ja' | 'en' } = {}) {
  const t = lang === 'ja' ? JA : EN;
  return render(
    <KitTestHost strings={lang} t={t} {...props}>
      <ConfirmProvider />
      {ui}
    </KitTestHost>,
  );
}
