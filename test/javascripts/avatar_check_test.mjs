// The check step of assets/javascripts/s3_avatar_upload.js with a fake
// jQuery: it asks again while the server answers 202 (malware scan), resolves
// on 200, rejects with the server's error, and gives up after the last retry.
// Run: node test/javascripts/avatar_check_test.mjs
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const read = (name) => readFileSync(new URL(`../../assets/javascripts/${name}`, import.meta.url), 'utf8');
globalThis.window = globalThis;
// The texts of the page's <meta> tag (Hooks#upload_messages).
const texts = { scanning: 'The malware scan of the file has not finished. Try again later.',
  failed: 'Upload failed', failedStatus: 'Upload failed ({status})', networkError: 'Network error' };
const metaTag = { getAttribute: () => JSON.stringify(texts) };
globalThis.document = {
  addEventListener: () => {},
  querySelector: (s) => (s.includes('redmine-s3-messages') ? metaTag : null),
  querySelectorAll: () => []
};
globalThis.addEventListener = () => {};
let answers = [];
let calls = 0;
const deferred = (answer) => ({
  done(fn) { if (answer.status < 400) { fn(JSON.parse(answer.responseText), 'success', answer); } return this; },
  fail(fn) { if (answer.status >= 400) { fn(answer); } return this; }
});
globalThis.$ = { ajax: () => { calls++; return deferred(answers.shift()); } };
new Function(read('s3_upload.js'))();
new Function(read('s3_avatar_upload.js'))();
const { check, retryDelays } = globalThis.RedmineS3AvatarUpload;
retryDelays.fill(0);

const scanning = () => ({ status: 202, responseText: '{"status":"scanning"}' });
answers = [scanning(), scanning(), { status: 200, responseText: '{"status":"ok"}' }];
await check('/s3_uploads/avatar/check', 't', 0);
assert.equal(calls, 3);

calls = 0;
answers = [{ status: 422, responseText: '{"errors":["The upload has expired. Add the file again."]}' }];
await assert.rejects(check('/s3_uploads/avatar/check', 't', 0),
  (e) => e === 'The upload has expired. Add the file again.');

calls = 0;
answers = Array.from({ length: retryDelays.length + 1 }, scanning);
await assert.rejects(check('/s3_uploads/avatar/check', 't', 0), (e) => e === texts.scanning);
assert.equal(calls, retryDelays.length + 1);
console.log('avatar check: ok');
