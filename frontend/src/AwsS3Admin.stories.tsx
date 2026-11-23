import { kitStory, userEvent, within, type Meta, type StoryObj } from '@redmine-kit/plugin/storybook';
import { AwsS3Admin } from './AwsS3Admin';
import { admin, checks, off } from './fixtures';

// Administration › AWS › S3 (the manifest's /admin/aws/s3, a tab of the page AWS), in the app's card with the page's title.
const meta = {
  title: 'Screens/AwsS3Admin',
  component: AwsS3Admin,
  ...kitStory({
    frame: 'card',
    bare: true,
    title: 'AWS',
    responses: {
      'GET /admin/aws/s3.json': admin,
      'POST /admin/aws/s3/read_write.json': checks,
      'POST /admin/aws/s3/reconcile.json': { notice: '整合性チェックを開始しました。', errors: [] },
    },
  }),
} satisfies Meta<typeof AwsS3Admin>;

export default meta;
type Story = StoryObj<typeof meta>;

/** S3 on: the environment, a blocked file, the last consistency check and the settings. */
export const Default: Story = {};

/** After the read/write test: one step failed. */
export const Tested: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /読み書きテスト|Read\/write test/ }));
  },
};

/** REDMINE_S3_BUCKET not set. */
export const Off: Story = kitStory({ responses: { 'GET /admin/aws/s3.json': off } });

export const Loading: Story = kitStory({ state: 'loading' });
export const Failed: Story = kitStory({ state: 'error' });
export const Forbidden: Story = kitStory({ state: 'forbidden' });
