// The complete step of assets/javascripts/s3_upload.js with a fake jQuery:
// it sends complete again while the server answers 202 (malware scan), runs
// the script of the 200 answer, and gives up after the last retry.
// Run: node test/javascripts/complete_test.mjs
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const src = readFileSync(new URL('../../assets/javascripts/s3_upload.js', import.meta.url), 'utf8');
globalThis.window = globalThis;
// The texts of the page's <meta> tag (Hooks#upload_messages).
const texts = { scanning: 'The malware scan of the file has not finished. Try again later.',
  failed: 'Upload failed', failedStatus: 'Upload failed ({status})', networkError: 'Network error' };
const metaTag = { getAttribute: () => JSON.stringify(texts) };
globalThis.document = {
  addEventListener: () => {},
  querySelector: (s) => (s.includes('redmine-s3-messages') ? metaTag : null)
};
let answers = [];
let calls = 0;
let evaluated = [];
const deferred = (answer) => ({
  done(fn) { if (answer.status < 400) { fn(answer.text, 'success', answer); } return this; },
  fail(fn) { if (answer.status >= 400) { fn(answer); } return this; }
});
globalThis.$ = {
  ajax: () => { calls++; return deferred(answers.shift()); },
  globalEval: (text) => evaluated.push(text)
};
new Function(src)();
const { complete, retryDelays } = globalThis.RedmineS3Upload;
retryDelays.fill(0);

answers = [{ status: 202, text: '{}' }, { status: 202, text: '{}' }, { status: 200, text: 'token()' }];
assert.equal(await complete('/s3_uploads/complete.js', 't', 0), 'token()');
assert.equal(calls, 3);
assert.deepEqual(evaluated, ['token()']);

calls = 0; evaluated = [];
answers = [{ status: 422, responseText: '{"errors":["The upload has expired. Add the file again."]}' }];
await assert.rejects(complete('/s3_uploads/complete.js', 't', 0),
  (e) => e === 'The upload has expired. Add the file again.');

calls = 0;
// The message of the server's 202 answer, in the user's language.
answers = Array.from({ length: retryDelays.length + 1 }, () => ({ status: 202, text: '{"message":"スキャン中"}' }));
await assert.rejects(complete('/s3_uploads/complete.js', 't', 0), (e) => e === 'スキャン中');
assert.equal(calls, retryDelays.length + 1);
assert.deepEqual(evaluated, []);

// The texts of the page when the server's answer has none.
calls = 0;
answers = Array.from({ length: retryDelays.length + 1 }, () => ({ status: 202, text: '{}' }));
await assert.rejects(complete('/s3_uploads/complete.js', 't', 0), (e) => e === texts.scanning);
const { failedText } = globalThis.RedmineS3Upload;
assert.equal(failedText({ status: 403 }), 'Upload failed (403)');
assert.equal(failedText({ status: 0 }), 'Upload failed (Network error)');
console.log('complete: ok');
