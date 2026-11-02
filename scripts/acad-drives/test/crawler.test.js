// Checks the sync-side logic with Drive and Firestore stubbed: no network,
// no credentials. Run with `npm test`.
const assert = require('assert');
const { AcadDriveMaster } = require('../acad-drive-master.js');

function fakeDb(sources) {
  const writes = [];
  const db = {
    writes,
    collection: (c) => ({
      get: async () => ({ docs: Object.entries(sources).map(([id, d]) => ({ id, data: () => d })) }),
      doc: (id) => ({ set: async (data, opt) => writes.push({ c, id, data, opt }) }),
    }),
  };
  return db;
}

(async () => {
  const m = new AcadDriveMaster();
  m.db = fakeDb({
    'PYQ dump': { name: 'PYQ dump', driveLink: 'https://drive.google.com/file/d/abc/view', contributor: 'A', courseCode: 'CS F211', resourceType: 'pyq', submissionId: 'sub1' },
    off: { name: 'off', disabled: true },
  });
  await m.loadSources();
  assert.deepStrictEqual(Object.keys(m.credits), ['PYQ dump']);
  assert.strictEqual(m.credits['PYQ dump'].resourceType, 'pyq');

  // pickMatches mirrors the folder rules.
  const P = AcadDriveMaster.pickMatches;
  assert.deepStrictEqual(P([], [{ code: 'X', score: 0 }]), [{ code: 'X', score: 0 }]);
  assert.deepStrictEqual(P([{ code: 'Y', score: 0.2 }], [{ code: 'X', score: 0 }]), [{ code: 'X', score: 0 }]);
  assert.deepStrictEqual(P([{ code: 'Y', score: 0 }], [{ code: 'X', score: 0.3 }]), [{ code: 'Y', score: 0 }]);
  assert.deepStrictEqual(P([{ code: 'Y', score: 0 }], [{ code: 'X', score: 0 }]).map(x => x.code), ['X', 'Y']);
  assert.deepStrictEqual(P([{ code: 'Y', score: 0.1 }], []), [{ code: 'Y', score: 0.1 }]);

  // A single-file link with a pinned course is not "unclassified".
  m.drive = { files: { get: async () => ({ data: { id: 'abc', name: 'scan_004.pdf', mimeType: 'application/pdf', size: 1 } }) } };
  m.findCourseMatches = () => [];
  m.initDriveStats('PYQ dump');
  const log = console.log; const out = []; console.log = (...a) => out.push(a.join(' '));
  await m.processSingleDriveFile('abc', 'PYQ dump', 'A', true, [{ code: 'CS F211', score: 0 }]);
  console.log = log;
  assert.ok(out.some(l => l.includes('CS F211')), out.join('\n'));
  assert.strictEqual(m.driveStats['PYQ dump'].unclassified, 0);

  // Sync results land on the source doc, with a readable problem.
  m.driveStats['PYQ dump'].processed = 0;
  await m.recordSyncResult('PYQ dump', 'File not found: abc.');
  const mirrored = m.db.writes.pop();
  assert.strictEqual(mirrored.c, 'acad_drives_submissions');
  assert.strictEqual(mirrored.id, 'sub1');
  assert.match(mirrored.data.syncStatus.problem, /Anyone with the link/);
  let w = m.db.writes.pop();
  assert.strictEqual(w.c, 'acad_drives_sources');
  assert.strictEqual(w.id, 'PYQ dump');
  assert.match(w.data.lastSync.problem, /Anyone with the link/);
  assert.deepStrictEqual(w.opt, { merge: true });
  m.driveStats['PYQ dump'].processed = 0;
  await m.recordSyncResult('PYQ dump', null);
  assert.strictEqual(m.db.writes.pop().data.syncStatus.files, 0);
  assert.strictEqual(m.db.writes.pop().data.lastSync.problem, 'No files found at this link.');
  m.driveStats['PYQ dump'].processed = 4;
  await m.recordSyncResult('PYQ dump', null);
  assert.deepStrictEqual([m.db.writes.pop().data.syncStatus.files, m.db.writes.pop().data.lastSync.problem], [4, null]);

  // The drive's declared type reaches the file doc.
  m.courseData.codes.set('CS F211', { code: 'CS F211', name: 'DSA' });
  await m.createFirebaseEntry({ name: 'scan_004.pdf', path: 'scan_004.pdf', storagePath: 'k', firebaseUrl: 'u',
    courseCode: 'CS F211', courseCodes: ['CS F211'], driveName: 'PYQ dump', contributor: 'A', mimeType: 'application/pdf', size: 1, driveFileId: 'abc' });
  w = m.db.writes.pop();
  assert.strictEqual(w.c, 'acad_drives_files');
  assert.strictEqual(w.data.resource_type, 'pyq');
  console.log('crawler checks passed');
})().catch((e) => { console.error(e); process.exit(1); });
