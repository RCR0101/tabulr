/**
 * Security-rules tests, run against the real Firestore emulator.
 *
 * Each block names the hole it is pinning shut, so a future edit that reopens
 * one fails here with an explanation rather than a bare assertion.
 *
 *   npm --prefix test/rules test
 */
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, serverTimestamp,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const env = await initializeTestEnvironment({
  projectId: 'tabulr-rules-test',
  firestore: {
    rules: readFileSync(join(here, '..', '..', 'firestore.rules'), 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

/** A signed-in Google user. Mirrors the claims Firebase issues for Google sign-in. */
function user(email, extra = {}) {
  return env.authenticatedContext(email.split('@')[0], {
    email,
    email_verified: true,
    firebase: { sign_in_provider: 'google.com' },
    ...extra,
  }).firestore();
}

const HYD = 'f20220123@hyderabad.bits-pilani.ac.in';   // -> f20220123H
const DXB = 'f20220456@dubai.bits-pilani.ac.in';       // -> f20220456D
const OTHER = 'f20229999@hyderabad.bits-pilani.ac.in'; // -> f20229999H

let failures = 0;
async function test(name, fn) {
  try {
    await fn();
    console.log(`  ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`  FAIL ${name}\n       ${(e.message || e).split('\n')[0]}`);
  }
}
function group(name) {
  console.log(`\n${name}\n`);
}

/** Seed data bypassing rules. */
async function seed(fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

await env.clearFirestore();

// ───────────────────────────────────────────────────────────────────────────
group('userDocId(): non-BITS domains must not derive a real doc id');

await seed(async (db) => {
  await setDoc(doc(db, 'bug_reports/report-dxb'), {
    authorUid: 'f20220456D',
    authorEmail: DXB,
    status: 'pending',
    category: 'bug',
    subCategory: 'ui',
    description: 'private report body',
  });
  await setDoc(doc(db, 'bug_reports/report-dxb/messages/m1'), {
    authorUid: 'f20220456D',
    isAdmin: false,
    body: 'private thread message',
  });
});

await test('the Dubai author can read their own report', async () => {
  await assertSucceeds(getDoc(doc(user(DXB), 'bug_reports/report-dxb')));
});

await test('gmail account with a matching local part CANNOT read that report', async () => {
  // The attack: f20220456@gmail.com used to derive "f20220456D" because
  // userDocId() fell through to 'D' for every unrecognised domain.
  const attacker = user('f20220456@gmail.com');
  await assertFails(getDoc(doc(attacker, 'bug_reports/report-dxb')));
});

await test('gmail lookalike CANNOT read the private admin thread', async () => {
  const attacker = user('f20220456@gmail.com');
  await assertFails(getDoc(doc(attacker, 'bug_reports/report-dxb/messages/m1')));
});

await test('gmail lookalike CANNOT post into the thread', async () => {
  const attacker = user('f20220456@gmail.com');
  await assertFails(
    setDoc(doc(attacker, 'bug_reports/report-dxb/messages/m2'), {
      authorUid: 'f20220456D',
      isAdmin: false,
      body: 'injected',
      // serverTimestamp(), not new Date(): the rule requires
      // `createdAt == request.time`, so a client clock value fails on the
      // timestamp check before ever reaching isReporter() — which would make
      // this pass against vulnerable rules and prove nothing.
      createdAt: serverTimestamp(),
    }),
  );
});

await test('the real Dubai author CAN post into their own thread', async () => {
  // Control for the test above: same payload, right identity, must succeed.
  await assertSucceeds(
    setDoc(doc(user(DXB), 'bug_reports/report-dxb/messages/m3'), {
      authorUid: 'f20220456D',
      isAdmin: false,
      body: 'legitimate reply',
      createdAt: serverTimestamp(),
    }),
  );
});

await test('gmail lookalike CANNOT touch the report', async () => {
  const attacker = user('f20220456@gmail.com');
  await assertFails(
    updateDoc(doc(attacker, 'bug_reports/report-dxb'), { lastUserReplyAt: new Date() }),
  );
});

await test('a different BITS student cannot read the report either', async () => {
  await assertFails(getDoc(doc(user(HYD), 'bug_reports/report-dxb')));
});

// ───────────────────────────────────────────────────────────────────────────
group('shared_timetables: capability URLs must not be enumerable');

await seed(async (db) => {
  await setDoc(doc(db, 'shared_timetables/2f8a1c04-aaaa-4bbb-8ccc-ddddeeeeffff'), {
    name: 'My Sem', ownerName: 'Someone', ownerId: 'f20229999H',
    campus: 'hyderabad', sections: [],
  });
});

await test('a BITS user can fetch a share by its id (the real flow)', async () => {
  await assertSucceeds(
    getDoc(doc(user(HYD), 'shared_timetables/2f8a1c04-aaaa-4bbb-8ccc-ddddeeeeffff')),
  );
});

await test('a BITS user CANNOT list the collection and harvest every share', async () => {
  await assertFails(getDocs(collection(user(HYD), 'shared_timetables')));
});

await test('owner can create their own share', async () => {
  await assertSucceeds(
    setDoc(doc(user(HYD), 'shared_timetables/new-share-1'), { ownerId: 'f20220123H', name: 'x' }),
  );
});

await test('cannot create a share owned by someone else', async () => {
  await assertFails(
    setDoc(doc(user(HYD), 'shared_timetables/new-share-2'), { ownerId: 'f20229999H', name: 'x' }),
  );
});

await test("cannot delete someone else's share", async () => {
  await assertFails(
    deleteDoc(doc(user(HYD), 'shared_timetables/2f8a1c04-aaaa-4bbb-8ccc-ddddeeeeffff')),
  );
});

// ───────────────────────────────────────────────────────────────────────────
group('reputation: scores are readable by id, not enumerable');

await seed(async (db) => {
  await setDoc(doc(db, 'reputation/f20229999H'), { score: 42, events: [] });
});

await test('can read a single reputation doc', async () => {
  await assertSucceeds(getDoc(doc(user(HYD), 'reputation/f20229999H')));
});

await test('CANNOT list every user reputation', async () => {
  await assertFails(getDocs(collection(user(HYD), 'reputation')));
});

// ───────────────────────────────────────────────────────────────────────────
group('acad_drives_submissions: contributor emails are not public');

await seed(async (db) => {
  await setDoc(doc(db, 'acad_drives_submissions/s1'), {
    driveLink: 'https://drive.google.com/x', title: 't',
    contributorName: 'n', submittedBy: HYD, status: 'pending',
  });
});

await test('an anonymous visitor CANNOT list submissions', async () => {
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),
    'acad_drives_submissions')));
});

await test('a signed-in student CANNOT read submissions', async () => {
  await assertFails(getDoc(doc(user(HYD), 'acad_drives_submissions/s1')));
});

await test('a student can still submit one', async () => {
  await assertSucceeds(
    setDoc(doc(user(HYD), 'acad_drives_submissions/s2'), {
      driveLink: 'https://drive.google.com/y', title: 'notes',
      contributorName: 'me', submittedBy: HYD, status: 'pending',
    }),
  );
});

await test('cannot submit under a forged email', async () => {
  await assertFails(
    setDoc(doc(user(HYD), 'acad_drives_submissions/s3'), {
      driveLink: 'https://drive.google.com/z', title: 'notes',
      contributorName: 'me', submittedBy: OTHER, status: 'pending',
    }),
  );
});

// ───────────────────────────────────────────────────────────────────────────
group('isBitsEmail: unverified / non-Google identities are rejected');

await test('an unverified email is rejected', async () => {
  const unverified = env.authenticatedContext('f20220123', {
    email: HYD,
    email_verified: false,
    firebase: { sign_in_provider: 'password' },
  }).firestore();
  await assertFails(
    setDoc(doc(unverified, 'shared_timetables/forged'), { ownerId: 'f20220123H', name: 'x' }),
  );
});

await test('a password-provider identity is rejected even if verified', async () => {
  const pw = env.authenticatedContext('f20220123', {
    email: HYD,
    email_verified: true,
    firebase: { sign_in_provider: 'password' },
  }).firestore();
  await assertFails(
    setDoc(doc(pw, 'shared_timetables/forged2'), { ownerId: 'f20220123H', name: 'x' }),
  );
});

// ───────────────────────────────────────────────────────────────────────────
group('users/{id}: owner isolation still holds');

await seed(async (db) => {
  await setDoc(doc(db, 'users/f20229999H/cgpa_semesters/1-1'), { encryptedData: 'x' });
});

await test('owner reads their own CGPA', async () => {
  await assertSucceeds(getDoc(doc(user(OTHER), 'users/f20229999H/cgpa_semesters/1-1')));
});

await test("another student cannot read it", async () => {
  await assertFails(getDoc(doc(user(HYD), 'users/f20229999H/cgpa_semesters/1-1')));
});

await test('a gmail lookalike cannot reach a Dubai student\'s data', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/f20220456D/cgpa_semesters/1-1'), { encryptedData: 'y' });
  });
  await assertFails(
    getDoc(doc(user('f20220456@gmail.com'), 'users/f20220456D/cgpa_semesters/1-1')),
  );
});

// ───────────────────────────────────────────────────────────────────────────
group('public reads still work without the kill-switch lookup');

await seed(async (db) => {
  await setDoc(doc(db, 'campuses/hyderabad/timetable/CS_F111'), { sections: [] });
  await setDoc(doc(db, 'reference/prerequisites/courses/CS_F211'), { groups: [] });
  await setDoc(doc(db, 'minors/finance'), { name: 'Finance' });
});

await test('a guest reads the campus catalogue', async () => {
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, 'campuses/hyderabad/timetable/CS_F111')));
});

await test('a guest reads reference data', async () => {
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, 'reference/prerequisites/courses/CS_F211')));
});

await test('a guest reads minors', async () => {
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, 'minors/finance')));
});

await test('a non-admin still cannot write campus data', async () => {
  await assertFails(
    setDoc(doc(user(HYD), 'campuses/hyderabad/timetable/CS_F111'), { sections: [] }),
  );
});

// ───────────────────────────────────────────────────────────────────────────
group('professor directory is not anonymously scrapable');

await seed(async (db) => {
  await setDoc(doc(db, 'reference/professors/hyderabad-entries/p1'), {
    name: 'Prof X', chamber: 'D-201', schedule: [],
  });
});

await test('an anonymous visitor CANNOT list the professor directory', async () => {
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),
    'reference/professors/hyderabad-entries')));
});

await test('an anonymous visitor CANNOT read a professor doc', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),
    'reference/professors/hyderabad-entries/p1')));
});

await test('a signed-in user still sees the directory (the real flow)', async () => {
  await assertSucceeds(getDocs(collection(user(HYD),
    'reference/professors/hyderabad-entries')));
});

await test('a guest can read the reference/app_config DOCUMENT itself', async () => {
  // `match /reference/app_config/{sub=**}` has to match the document, not just
  // things under it — MaintenanceGate reads this path directly, so getting the
  // wildcard wrong takes down the "we're down" message.
  await seed(async (db) => {
    await setDoc(doc(db, 'reference/app_config'), { maintenance: false });
  });
  await assertSucceeds(
    getDoc(doc(env.unauthenticatedContext().firestore(), 'reference/app_config')));
});

await test('other reference data stays open for guests', async () => {
  // Guests build timetables without signing in, so prerequisites, branches and
  // app_config must not be caught by the professors rule.
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, 'reference/prerequisites/courses/CS_F211')));
});

// ───────────────────────────────────────────────────────────────────────────
group('cache freshness markers are readable by the clients that poll them');

// Every service that caches locally polls a metadata document to decide whether
// its cache is stale. LocalCacheService.readIfFresh swallows a failed read and
// reports "stale", so a marker the rules do not cover does not raise — it
// silently disables the cache and turns every load into a full collection scan.
// PrerequisitesRepository pointed at a top-level `metadata/prerequisites`,
// which no rule matches, and did exactly that.
for (const path of [
  'reference/prerequisites',            // PrerequisitesRepository
  'reference/branches/data/_metadata',  // BranchStructureService
  'admin_metadata/professors_hyderabad',// ProfessorService
  'admin_metadata/exam_seating',        // ExamSeatingService
  'campuses/hyderabad/metadata/current',// CoursesMaster / CourseDataService
]) {
  await test(`a guest can read ${path}`, async () => {
    await assertSucceeds(
      getDoc(doc(env.unauthenticatedContext().firestore(), path)));
  });
}

await test('a non-admin still cannot bump the prerequisites marker', async () => {
  await assertFails(
    setDoc(doc(user(HYD), 'reference/prerequisites'),
        { lastUpdated: 'x' }, { merge: true }));
});

// ───────────────────────────────────────────────────────────────────────────
group('admin_emails stays invisible');

await test('nobody can read the admin allowlist', async () => {
  await assertFails(getDoc(doc(user(HYD), 'admin_emails/someone@bits.ac.in')));
});

await env.cleanup();
console.log(failures === 0 ? '\nall passed\n' : `\n${failures} failed\n`);
process.exit(failures === 0 ? 0 : 1);
