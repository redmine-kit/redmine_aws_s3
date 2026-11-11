// The submit button of the avatar form after a failed upload
// (assets/javascripts/s3_avatar_upload.js): rails-ujs disables it 13 ms
// after the submit event, so a refusal answered sooner must not leave it
// disabled. Run: node test/javascripts/avatar_enable_test.mjs
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const read = (name) => readFileSync(new URL(`../../assets/javascripts/${name}`, import.meta.url), 'utf8');
globalThis.window = globalThis;
globalThis.document = { addEventListener: () => {}, querySelector: () => null, querySelectorAll: () => [] };
globalThis.addEventListener = () => {};
globalThis.$ = { ajax: () => ({}) };
new Function(read('s3_upload.js'))();
new Function(read('s3_avatar_upload.js'))();
const { enable } = globalThis.RedmineS3AvatarUpload;

const button = { disabled: true };
const form = { querySelectorAll: () => [button] };
enable(form);
assert.equal(button.disabled, false);
// rails-ujs, 13 ms after the submit event.
setTimeout(() => { button.disabled = true; }, 13);
await new Promise((resolve) => { setTimeout(resolve, 100); });
assert.equal(button.disabled, false);
console.log('avatar enable: ok');
