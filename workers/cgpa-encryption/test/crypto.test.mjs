/**
 * Cross-user decryption tests for the CGPA encryption worker.
 *
 * The question this answers: if the worker holds one global ENCRYPTION_SECRET,
 * can student A send student B's ciphertext with A's own valid Firebase token
 * and get B's grades back? That would make the worker a decryption oracle and
 * reduce the at-rest encryption to "protects against people without a BITS
 * account", which Firestore rules already do.
 *
 * `src/index.js` is a Workers module with no named exports, so the helpers are
 * loaded by appending an export list to the source and importing it as a data:
 * URL module. That keeps the worker itself free of test-only exports and means
 * these tests always run against the real deployed code, not a copy.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert/strict';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, '..', 'src', 'index.js'), 'utf8');

const EXPORTS =
  '\nexport { deriveKey, encrypt, decrypt, deriveUserDocId, verifyFirebaseToken, validateBatch };\n';
const mod = await import(
  'data:text/javascript;base64,' +
    Buffer.from(source + EXPORTS, 'utf8').toString('base64')
);

const { deriveKey, encrypt, decrypt, deriveUserDocId, validateBatch } = mod;

const SECRET = 'test-encryption-secret-not-the-real-one';
const ALICE = 'f20220123H';
const BOB = 'f20220456H';
const PLAINTEXT = JSON.stringify({
  semester: '1-1',
  courses: [{ code: 'CS F111', grade: 'A', credits: 4 }],
});

let failures = 0;
async function test(name, fn) {
  try {
    await fn();
    console.log(`  ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`  FAIL ${name}\n       ${e.message}`);
  }
}

console.log('\ncgpa-encryption worker — key isolation\n');

await test('round-trips a payload for its own user', async () => {
  const key = await deriveKey(SECRET, ALICE);
  const ct = await encrypt(PLAINTEXT, key);
  assert.equal(await decrypt(ct, key), PLAINTEXT);
});

await test('derives a different key per user id', async () => {
  // Same secret, different userId -> different AES key. Exported as raw would
  // be ideal but the key is non-extractable, so compare ciphertext behaviour
  // instead: the isolation test below is the real assertion.
  const a = await deriveKey(SECRET, ALICE);
  const b = await deriveKey(SECRET, BOB);
  const ct = await encrypt(PLAINTEXT, a);
  await assert.rejects(() => decrypt(ct, b));
});

await test("student B cannot decrypt student A's ciphertext", async () => {
  const alice = await deriveKey(SECRET, ALICE);
  const bob = await deriveKey(SECRET, BOB);
  const stolen = await encrypt(PLAINTEXT, alice);

  // Bob presents his own valid token; the worker derives HIS key from it and
  // AES-GCM's auth tag rejects the mismatch. This is the oracle test.
  await assert.rejects(
    () => decrypt(stolen, bob),
    (e) => e instanceof Error,
    'cross-user decryption succeeded — worker IS an oracle',
  );
});

await test('ciphertext is non-deterministic (fresh IV per encrypt)', async () => {
  const key = await deriveKey(SECRET, ALICE);
  const a = await encrypt(PLAINTEXT, key);
  const b = await encrypt(PLAINTEXT, key);
  assert.notEqual(a, b, 'identical ciphertexts — IV is being reused');
  assert.equal(await decrypt(a, key), await decrypt(b, key));
});

await test('a flipped ciphertext byte is rejected, not silently mangled', async () => {
  const key = await deriveKey(SECRET, ALICE);
  const ct = await encrypt(PLAINTEXT, key);
  const raw = Buffer.from(ct, 'base64');
  raw[raw.length - 1] ^= 0x01; // corrupt inside the GCM tag
  await assert.rejects(() => decrypt(raw.toString('base64'), key));
});

await test('a swapped IV is rejected', async () => {
  const key = await deriveKey(SECRET, ALICE);
  const raw = Buffer.from(await encrypt(PLAINTEXT, key), 'base64');
  raw[0] ^= 0xff;
  await assert.rejects(() => decrypt(raw.toString('base64'), key));
});

console.log('\ncgpa-encryption worker — user id derivation\n');

await test('maps each campus domain to its suffix', () => {
  assert.equal(deriveUserDocId('f20220123@hyderabad.bits-pilani.ac.in'), 'f20220123H');
  assert.equal(deriveUserDocId('f20220123@pilani.bits-pilani.ac.in'), 'f20220123P');
  assert.equal(deriveUserDocId('f20220123@goa.bits-pilani.ac.in'), 'f20220123G');
  assert.equal(deriveUserDocId('f20220123@dubai.bits-pilani.ac.in'), 'f20220123D');
});

await test('rejects non-BITS domains instead of defaulting to Dubai', () => {
  // firestore.rules got this wrong: its userDocId() fell through to 'D' for any
  // unknown domain, so f20220123@gmail.com derived a real Dubai student's id.
  assert.equal(deriveUserDocId('f20220123@gmail.com'), null);
  assert.equal(deriveUserDocId('f20220123@bits-pilani.ac.in'), null);
  assert.equal(deriveUserDocId('nonsense'), null);
  assert.equal(deriveUserDocId(''), null);
  assert.equal(deriveUserDocId(null), null);
});

await test('is case-insensitive on the domain only', () => {
  assert.equal(deriveUserDocId('f20220123@HYDERABAD.bits-pilani.ac.in'), 'f20220123H');
  // Local part case is preserved — it is the Firestore doc id.
  assert.equal(deriveUserDocId('F20220123@hyderabad.bits-pilani.ac.in'), 'F20220123H');
});

console.log('\ncgpa-encryption worker — batch validation\n');

await test('accepts a normal batch', () => {
  assert.equal(validateBatch(['a', 'b', 'c']), null);
});

await test('rejects a non-array, empty, or non-string batch', () => {
  assert.match(validateBatch('not-an-array'), /must be an array/);
  assert.match(validateBatch([]), /must not be empty/);
  assert.match(validateBatch(['ok', 42]), /must all be strings/);
});

await test('caps the item count', () => {
  assert.equal(validateBatch(Array(16).fill('x')), null);
  assert.match(validateBatch(Array(17).fill('x')), /at most 16/);
});

await test('caps the aggregate size, not just each item', () => {
  // 16 items each under the per-item cap but 16MB in total.
  const big = 'x'.repeat(1_000_000);
  assert.match(validateBatch(Array(16).fill(big)), /Payload too large/);
});

await test('a batch decrypts to the same values as one-at-a-time', async () => {
  const key = await deriveKey(SECRET, ALICE);
  const inputs = ['{"a":1}', '{"b":2}', '{"c":3}'];
  const cts = await Promise.all(inputs.map((p) => encrypt(p, key)));
  const out = await Promise.all(cts.map((c) => decrypt(c, key)));
  assert.deepEqual(out, inputs);
});

await test("a batch of another user's blobs decrypts to nothing", async () => {
  const alice = await deriveKey(SECRET, ALICE);
  const bob = await deriveKey(SECRET, BOB);
  const stolen = await Promise.all(['{"a":1}', '{"b":2}'].map((p) => encrypt(p, alice)));
  // Mirrors the worker's per-item try/catch: every item fails, none leak.
  const results = await Promise.all(
    stolen.map(async (c) => {
      try {
        return { ok: true, result: await decrypt(c, bob) };
      } catch {
        return { ok: false };
      }
    }),
  );
  assert.deepEqual(results.map((r) => r.ok), [false, false]);
});

console.log(failures === 0 ? '\nall passed\n' : `\n${failures} failed\n`);
process.exit(failures === 0 ? 0 : 1);
