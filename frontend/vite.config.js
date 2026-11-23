// Builds src/index.ts into the plugin's module, ../assets/javascripts/kit/s3.js (redmine_kit_ui's docs/plugins-kit.md,
// "The module"), with @redmine-kit/plugin's preset: one ES module, Vite's library mode, with React, its JSX runtime and
// the app's packages (@redmine-kit/ui, @redmine-kit/plugin) left as imports (the shell's import map gives the app's own).
// Not minified, without hashes, so that the committed file is readable, reviewable and the same on every build. With it,
// the module's stylesheet, ../assets/stylesheets/kit/s3.css ("The stylesheet"): the Tailwind CSS utilities the source
// uses. `npm run build`, then commit all three.
import react from '@vitejs/plugin-react';
import { defineKitModule } from '@redmine-kit/plugin/vite';

export default defineKitModule({ name: 's3', title: 'Redmine Kit AWS S3', plugins: [react()] });
