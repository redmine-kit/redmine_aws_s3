// assets/javascripts/s3_settings.js with a fake document: it adds the note
// of the <meta> tag as an em.info after "Maximum attachment size", and
// nothing on a settings tab without that field.
// Run: node test/javascripts/settings_note_test.mjs
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const src = readFileSync(new URL('../../assets/javascripts/s3_settings.js', import.meta.url), 'utf8');
const NOTE = 'With S3, keep the CloudFront Function (/tmp/*) limit the same.';

function page(fields) {
  const children = [];
  const paragraph = { appendChild: (child) => children.push(child) };
  let onLoad = null;
  globalThis.document = {
    addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') { onLoad = fn; } },
    querySelector: (selector) => (selector === 'meta[name="redmine-s3-max-size-note"]'
      ? { getAttribute: (name) => (name === 'content' ? NOTE : null) } : null),
    getElementById: (id) => (fields.includes(id) ? { parentNode: paragraph } : null),
    createElement: (tag) => ({ tagName: tag.toUpperCase() })
  };
  new Function(src)();
  onLoad();
  return children;
}

const added = page(['settings_attachment_max_size']);
assert.equal(added.length, 1);
assert.equal(added[0].tagName, 'EM');
assert.equal(added[0].className, 'info');
assert.equal(added[0].textContent, NOTE);

assert.deepEqual(page(['settings_bulk_download_max_size']), []);
console.log('settings note: ok');
