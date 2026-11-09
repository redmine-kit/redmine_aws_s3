// The SHA-256 of assets/javascripts/s3_upload.js against known vectors and
// Node's crypto, fed in random pieces. Run: node test/javascripts/sha256_test.mjs
import { readFileSync } from 'node:fs';
import { createHash, randomBytes } from 'node:crypto';
const src = readFileSync(new URL('../../assets/javascripts/s3_upload.js', import.meta.url), 'utf8');
globalThis.window = globalThis; globalThis.btoa = (s) => Buffer.from(s, 'binary').toString('base64');
globalThis.document = { addEventListener: () => {}, querySelector: () => null };
new Function(src)();
const { Sha256, base64, hashBlob } = globalThis.RedmineS3Upload;
const ref = (b) => createHash('sha256').update(b).digest('base64');
let fail = 0;
const check = (name, got, want) => { if (got !== want) { fail++; console.log('FAIL', name, got, want); } };
for (const [s, hex] of [['', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'],
  ['abc', 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'],
  ['abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq', '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1']]) {
  check(JSON.stringify(s), base64(new Sha256().update(Buffer.from(s)).digest()), Buffer.from(hex, 'hex').toString('base64'));
}
for (let n = 0; n < 300; n++) {
  const data = randomBytes(n);
  const sha = new Sha256();
  for (let i = 0; i < n;) { const k = 1 + Math.floor(Math.random() * 70); sha.update(data.subarray(i, i + k)); i += k; }
  check('len' + n, base64(sha.digest()), ref(data));
}
const big = randomBytes(9 * 1024 * 1024 + 123);
const t = Date.now();
const got = await hashBlob(new Blob([big]), () => {});
check('blob', got, ref(big));
console.log('9MB in', Date.now() - t, 'ms; failures:', fail);
process.exit(fail ? 1 : 0);
