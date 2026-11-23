// The module's tests (npm test): its components with @redmine-kit/plugin/testing's KitTestHost in jsdom, and its data
// as plain functions.
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  test: { environment: 'jsdom', setupFiles: ['src/test/setup.ts'], include: ['src/**/*.test.{ts,tsx}'] },
});
