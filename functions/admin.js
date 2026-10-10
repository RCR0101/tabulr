const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const REGION = "asia-south1";

// ─── Admin verification (email-based) ───
//
// Source of truth: the `admin_emails` collection, keyed by lowercased email.
// Add an admin by creating `admin_emails/<their-email>` in the console.
// A custom `admin` claim is mirrored from it (see checkAdminStatus) so Storage
// rules — which cannot read Firestore — can gate the PDF upload path.

async function isAdminEmail(email) {
  if (!email) return false;
  const doc = await db.collection("admin_emails").doc(email.toLowerCase()).get();
  return doc.exists;
}

// Firestore caps a WriteBatch at 500 operations. Batches commit in sequence so
// a large rebuild can't stampede the write path.
const BATCH_LIMIT = 500;

async function commitInBatches(db, items, add) {
  for (let i = 0; i < items.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const item of items.slice(i, i + BATCH_LIMIT)) add(batch, item);
    await batch.commit();
  }
}

async function requireAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }
  if (!(await isAdminEmail(request.auth.token.email))) {
    throw new HttpsError("permission-denied", "Not an admin");
  }
  return request.auth.uid;
}

// ─── Check admin status (and sync the custom claim) ───

exports.checkAdminStatus = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  if (!request.auth) {
    return { isAdmin: false, claimRefreshed: false };
  }
  const { uid, token } = request.auth;
  const isAdmin = await isAdminEmail(token.email);
  const hadClaim = token.admin === true;
  // Mirror membership into a custom claim so Storage rules can see it. The
  // client force-refreshes its ID token when this changes.
  if (hadClaim !== isAdmin) {
    await admin.auth().setCustomUserClaims(uid, { admin: isAdmin });
  }
  return { isAdmin, claimRefreshed: hadClaim !== isAdmin };
});

// ─── List admins (for the public Credits screen) ───
//
// Reads the email-keyed `admin_emails` collection and resolves each admin's
// display name/photo via Firebase Auth. Only names/photos are returned (no
// emails) since the Credits screen is visible to everyone.

// This is deliberately callable without auth (the Credits screen is public), so
// it is bounded three ways: maxInstances caps what a flood can cost, a warm
// instance serves repeats from memory, and the Auth lookups are batched into a
// single call instead of one round trip per admin.

const GET_ADMINS_TTL_MS = 30 * 60 * 1000; // admin list changes ~never
let getAdminsCache = null; // { at: number, admins: Array }

exports.getAdmins = onCall(
  { region: REGION, enforceAppCheck: false, maxInstances: 3 },
  async () => {
    if (getAdminsCache && Date.now() - getAdminsCache.at < GET_ADMINS_TTL_MS) {
      return { admins: getAdminsCache.admins };
    }

    const snap = await db.collection("admin_emails").get();
    const entries = snap.docs.map((doc) => ({
      email: doc.id,
      stored: doc.data() || {},
    }));

    // Resolve display names/photos in one batched Auth call (100 max per call)
    // rather than a serial getUserByEmail per admin.
    const byEmail = new Map();
    for (let i = 0; i < entries.length; i += 100) {
      const chunk = entries.slice(i, i + 100);
      try {
        const res = await admin
          .auth()
          .getUsers(chunk.map((e) => ({ email: e.email })));
        for (const user of res.users) {
          if (user.email) byEmail.set(user.email.toLowerCase(), user);
        }
      } catch (e) {
        // Fall through to stored names for this chunk.
      }
    }

    const admins = [];
    for (const { email, stored } of entries) {
      const user = byEmail.get(email.toLowerCase());
      // No Auth user yet for this email — fall back to stored name / local-part.
      const name =
        (user && user.displayName) || stored.name || email.split("@")[0];
      const photoUrl = (user && user.photoURL) || null;
      if (name) admins.push({ name, photoUrl });
    }

    admins.sort((a, b) => a.name.localeCompare(b.name));
    getAdminsCache = { at: Date.now(), admins };
    return { admins };
  }
);

// ─── Professor fuzzy matching (ported from build_professor_schedules.js) ───

function levenshteinDistance(a, b) {
  const matrix = [];
  for (let i = 0; i <= b.length; i++) matrix[i] = [i];
  for (let j = 0; j <= a.length; j++) matrix[0][j] = j;
  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }
  return matrix[b.length][a.length];
}

function similarityScore(a, b) {
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1;
  return 1 - levenshteinDistance(a, b) / maxLen;
}

function normalizeName(name) {
  return name
    .toUpperCase()
    .trim()
    .replace(/\s+/g, " ")
    .replace(/\bDR\.?\s*/gi, "")
    .replace(/\bPROF\.?\s*/gi, "")
    .replace(/\bMR\.?\s*/gi, "")
    .replace(/\bMS\.?\s*/gi, "")
    .replace(/\bMRS\.?\s*/gi, "")
    .trim();
}

function extractNameParts(name) {
  const normalized = normalizeName(name);
  const parts = normalized.split(" ").filter((p) => p.length > 0);
  const initials = [];
  const mainParts = [];
  for (const part of parts) {
    if (part.length === 1 || (part.length === 2 && part.endsWith("."))) {
      initials.push(part.replace(".", ""));
    } else {
      mainParts.push(part);
    }
  }
  return { initials, mainParts };
}

function checkInitialsCompatible(parts1, parts2) {
  if (parts1.initials.length === 0 || parts2.initials.length === 0) return true;
  for (const i1 of parts1.initials) {
    for (const i2 of parts2.initials) {
      if (i1 === i2) return true;
    }
    for (const mp2 of parts2.mainParts) {
      if (mp2.startsWith(i1)) return true;
    }
  }
  for (const i2 of parts2.initials) {
    for (const mp1 of parts1.mainParts) {
      if (mp1.startsWith(i2)) return true;
    }
  }
  return false;
}

function fuzzyNameMatch(name1, name2) {
  const n1 = normalizeName(name1);
  const n2 = normalizeName(name2);

  if (n1 === n2) return { match: true, score: 1.0, reason: "exact" };

  const directSimilarity = similarityScore(n1, n2);
  if (directSimilarity >= 0.85) {
    return { match: true, score: directSimilarity, reason: "high_similarity" };
  }

  const parts1 = extractNameParts(name1);
  const parts2 = extractNameParts(name2);

  if (parts1.mainParts.length > 0 && parts2.mainParts.length > 0) {
    const minParts = Math.min(parts1.mainParts.length, parts2.mainParts.length);
    const maxParts = Math.max(parts1.mainParts.length, parts2.mainParts.length);

    let matchedParts = 0;
    const usedParts2 = new Set();

    for (const mp1 of parts1.mainParts) {
      for (const mp2 of parts2.mainParts) {
        if (!usedParts2.has(mp2) && similarityScore(mp1, mp2) >= 0.85) {
          matchedParts++;
          usedParts2.add(mp2);
          break;
        }
      }
    }

    const matchRatio = matchedParts / maxParts;

    if (minParts === 1 && maxParts === 1) {
      if (matchedParts === 1) {
        if (checkInitialsCompatible(parts1, parts2)) {
          return { match: true, score: 0.9, reason: "single_main_part_match" };
        }
      }
    } else if (matchedParts >= minParts && matchRatio >= 0.5) {
      if (checkInitialsCompatible(parts1, parts2)) {
        const score = 0.85 * (matchedParts / maxParts);
        return {
          match: true,
          score: Math.max(0.7, score),
          reason: "main_parts_match_with_initials",
        };
      }
    }
  }

  if (
    parts1.initials.length === 1 &&
    parts1.mainParts.length === 1 &&
    parts2.mainParts.length >= 2 &&
    parts2.initials.length === 0
  ) {
    const init = parts1.initials[0];
    const mainPart = parts1.mainParts[0];
    for (const mp of parts2.mainParts) {
      if (mp.startsWith(init) && mp !== mainPart) {
        const remainingParts2 = parts2.mainParts.filter((p) => p !== mp);
        for (const rp2 of remainingParts2) {
          if (similarityScore(mainPart, rp2) >= 0.85) {
            return { match: true, score: 0.8, reason: "initial_expansion_match" };
          }
        }
      }
    }
  }

  if (
    parts2.initials.length === 1 &&
    parts2.mainParts.length === 1 &&
    parts1.mainParts.length >= 2 &&
    parts1.initials.length === 0
  ) {
    const init = parts2.initials[0];
    const mainPart = parts2.mainParts[0];
    for (const mp of parts1.mainParts) {
      if (mp.startsWith(init) && mp !== mainPart) {
        const remainingParts1 = parts1.mainParts.filter((p) => p !== mp);
        for (const rp1 of remainingParts1) {
          if (similarityScore(mainPart, rp1) >= 0.85) {
            return { match: true, score: 0.8, reason: "initial_expansion_match_reverse" };
          }
        }
      }
    }
  }

  return { match: false, score: directSimilarity, reason: "no_match" };
}

const FUZZY_MATCH_THRESHOLD = 0.7;

// What a rebuilt professor doc keeps. A name, chamber, email or contact
// already on the doc beats the roster's, which only fills gaps: students know
// professors by the names they already see, not the faculty site's spelling.
function professorFields(prof, prev = {}) {
  const known = (v) => typeof v === "string" && v.trim() !== "" && v.trim() !== "Unavailable";
  const chamber = (known(prev.chamber) ? prev.chamber : known(prof.chamber) ? prof.chamber : "Unavailable").trim();
  const email = prev.email || prof.email;
  const contact = prev.contact || prof.phone;
  const name = String(prev.name || prof.name).trim();
  return {
    name,
    chamber,
    nameSearch: name.toLowerCase(),
    chamberSearch: chamber.toLowerCase(),
    ...(email ? { email } : {}),
    ...(contact ? { contact } : {}),
  };
}

// Pairs each roster entry with the professor doc it already has, so a rebuild
// updates that doc instead of adding a twin. The faculty site and the
// timetable spell names differently ("A. K. Jayesh" / "A K Jayesh",
// "Vuppuluri Amol" / "Amol Vuppuluri"), so: exact name, then email, then the
// same fuzzy match used for timetable names. Each doc is claimed at most once.
// Returns an array parallel to `profs`: the matched existing entry or null.
function matchExisting(profs, existing) {
  const unclaimed = new Set(existing);
  const claim = (e) => { unclaimed.delete(e); return e; };
  const key = (n) => String(n || "").trim().toUpperCase();
  const result = profs.map(() => null);
  const passes = [
    (p) => [...unclaimed].find((e) => key(e.name) === key(p.name)),
    (p) => p.email && [...unclaimed].find((e) => e.email && e.email.toLowerCase() === p.email.toLowerCase()),
    (p) => {
      const pool = [...unclaimed];
      const best = findBestMatch(key(p.name), pool.map((e) => key(e.name)));
      const hit = best.match ? pool.find((e) => key(e.name) === best.match) : null;
      // Two different addresses are two different people, however close the names.
      if (hit && hit.email && p.email && hit.email.toLowerCase() !== p.email.toLowerCase()) return null;
      return hit;
    },
  ];
  for (const pass of passes) {
    profs.forEach((p, i) => {
      if (result[i] || !p.name) return;
      const hit = pass(p);
      if (hit) result[i] = claim(hit);
    });
  }
  return result;
}

function findBestMatch(courseProfName, profsJsonNames) {
  let bestMatch = null;
  let bestScore = 0;
  let bestReason = "no_match";

  for (const profName of profsJsonNames) {
    const result = fuzzyNameMatch(profName, courseProfName);
    if (result.match && result.score > bestScore) {
      bestMatch = profName;
      bestScore = result.score;
      bestReason = result.reason;
    }
  }

  if (bestScore >= FUZZY_MATCH_THRESHOLD) {
    return { match: bestMatch, score: bestScore, reason: bestReason };
  }
  return { match: null, score: bestScore, reason: "below_threshold" };
}

function normalizeInstructorNames(instructor) {
  if (!instructor || instructor.toString().trim() === "") return [];
  return instructor
    .toString()
    .split(/[,\/]/)
    .map((name) => name.trim().toUpperCase())
    .filter((name) => name !== "");
}

// ─── Rebuild Professor Schedules ───

exports.rebuildProfessorSchedules = onCall(
  { region: REGION, enforceAppCheck: false, timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    await requireAdmin(request);

    const { profsJsonBase64, campusCode, usePending } = request.data || {};
    const campus = campusCode || "hyderabad";
    const validCampuses = ["hyderabad", "pilani", "goa"];
    if (!validCampuses.includes(campus)) {
      throw new HttpsError("invalid-argument", "Invalid campus: " + campus);
    }

    const profsMetaKey = `admin_metadata/professors_data_${campus}`;

    if (profsJsonBase64) {
      const profsBuffer = Buffer.from(profsJsonBase64, "base64");
      const profsData = JSON.parse(profsBuffer.toString("utf8"));
      if (!profsData.profs || !Array.isArray(profsData.profs)) {
        throw new HttpsError(
          "invalid-argument",
          'Invalid profs.json format — expected { "profs": [...] }'
        );
      }
      await db.doc(profsMetaKey).set({ profs: profsData.profs });
    }

    // The weekly roster check (check_faculty_roster) leaves the directory's
    // roster here when it finds new faculty; applying its notice promotes it.
    if (usePending) {
      const pendingRef = db.doc(`admin_metadata/professors_pending_${campus}`);
      const pending = (await pendingRef.get()).data();
      if (!pending || !Array.isArray(pending.profs)) {
        throw new HttpsError("failed-precondition", "No pending roster for " + campus);
      }
      await db.doc(profsMetaKey).set({ profs: pending.profs });
      await pendingRef.delete();
    }

    return rebuildSchedules(campus);
  }
);

// Rebuilds every professor's teaching schedule from the campus timetable as it
// is now. Run by the admin callable and, automatically, whenever the timetable
// changes (onTimetableChanged), so schedules never lag a new booklet.
// `roster` stands in for the stored profs.json; `dryRun` returns the planned
// writes without committing anything (used to review a rebuild against prod).
async function rebuildSchedules(campus, { roster = null, dryRun = false } = {}) {
    const professorsRef = db.collection(`reference/professors/${campus}-entries`);
    const existingSnap = await professorsRef.get();
    const existing = existingSnap.docs.map((d) => ({ ...d.data(), _ref: d.ref }));

    // Without an uploaded roster the professor docs themselves are the roster,
    // so schedules still follow the timetable on a campus nobody has set up.
    const profsDoc = await db.doc(`admin_metadata/professors_data_${campus}`).get();
    const uploaded = profsDoc.exists && Array.isArray(profsDoc.data().profs) ? profsDoc.data().profs : null;
    const professorData = {
      // A copy: the leftovers appended below must not leak into the caller's roster.
      profs: [...(roster || uploaded || existing.map((e) => ({ name: e.name, chamber: e.chamber, email: e.email, phone: e.contact })))],
    };
    if (professorData.profs.length === 0) {
      throw new HttpsError("failed-precondition",
        "No professors for " + campus + " yet. Upload profs.json (functions-python/faculty.py makes one).");
    }

    // Pair the roster with the docs on file, then add everyone on file the
    // roster missed (added by hand, or gone from the faculty site) as their
    // own entry, so their timings are recomputed too instead of left stale.
    const matched = matchExisting(professorData.profs, existing);
    const claimed = new Set(matched.filter(Boolean));
    for (const e of existing) {
      if (claimed.has(e) || !e.name) continue;
      professorData.profs.push({ name: e.name, chamber: e.chamber, email: e.email, phone: e.contact });
      matched.push(e);
    }

    const coursesSnapshot = await db
      .collection(`campuses/${campus}/timetable`)
      .get();

    const professorScheduleMap = {};
    coursesSnapshot.forEach((doc) => {
      const course = doc.data();
      const courseCode = doc.id.replace(/_/g, " ");

      if (!course.sections || !Array.isArray(course.sections)) return;

      course.sections.forEach((section) => {
        const instructorNames = normalizeInstructorNames(section.instructor);
        const room = section.room || "";
        const sectionId = section.sectionId || "";
        const schedule = section.schedule || [];

        instructorNames.forEach((profName) => {
          if (!professorScheduleMap[profName]) {
            professorScheduleMap[profName] = [];
          }
          schedule.forEach((scheduleEntry) => {
            professorScheduleMap[profName].push({
              course_code: courseCode,
              section_id: sectionId,
              room,
              days: scheduleEntry.days || [],
              hours: scheduleEntry.hours || [],
            });
          });
        });
      });
    });

    const profsJsonNames = professorData.profs
      .filter((p) => p.name)
      .map((p) => p.name.trim().toUpperCase());

    const courseToJsonNameMap = {};
    for (const courseProfName of Object.keys(professorScheduleMap)) {
      if (profsJsonNames.includes(courseProfName)) {
        courseToJsonNameMap[courseProfName] = courseProfName;
        continue;
      }
      const bestMatch = findBestMatch(courseProfName, profsJsonNames);
      if (bestMatch.match) {
        courseToJsonNameMap[courseProfName] = bestMatch.match;
      }
    }

    const mergedScheduleMap = {};
    for (const [courseProfName, schedule] of Object.entries(professorScheduleMap)) {
      const jsonName = courseToJsonNameMap[courseProfName];
      if (jsonName) {
        if (!mergedScheduleMap[jsonName]) mergedScheduleMap[jsonName] = [];
        mergedScheduleMap[jsonName].push(...schedule);
      }
    }

    // Updated in place, never wiped. Chambers, emails and contacts edited in
    // Admin → Professor Chambers live only on these docs, and the roster may
    // come from the faculty site, which publishes no chambers at all — so an
    // existing real chamber wins and the roster only fills gaps. Professors
    // added by hand (not in the roster) are left as they are.
    // Spelling-only matches carry a chamber across to a differently written
    // name, so the admin sees each one ("Ali Dar" may not be "Adil Dar").
    const respelled = professorData.profs
      .map((p, i) => matched[i] && String(matched[i].name).trim().toUpperCase() !== String(p.name).trim().toUpperCase()
        ? `${matched[i].name} → ${p.name.trim()}` : null)
      .filter(Boolean);

    const writes = [];
    let matchedCount = 0;
    let unmatchedCount = 0;
    const now = new Date();
    professorData.profs.forEach((prof, i) => {
      if (!prof.name) return;

      const profNameNormalized = prof.name.trim().toUpperCase();
      const schedule = mergedScheduleMap[profNameNormalized] || [];
      const prev = matched[i] || {};
      const docRef = matched[i]?._ref || professorsRef.doc();

      if (schedule.length > 0) matchedCount++;
      else unmatchedCount++;

      const fields = { id: docRef.id, ...professorFields(prof, prev), schedule };
      // Runs on every timetable edit: only touch docs that actually changed.
      if (matched[i] && sameProfessor(prev, fields)) return;
      writes.push({
        ref: docRef,
        data: { ...fields, createdAt: prev.createdAt || now, updatedAt: now },
      });
    });

    if (dryRun) {
      return { writes, existing, matched, respelled, withSchedule: matchedCount, withoutSchedule: unmatchedCount };
    }

    await commitInBatches(db, writes, (batch, w) => batch.set(w.ref, w.data));

    // Students' caches refresh when this moves, so leave it alone when nothing did.
    if (writes.length > 0 || !(await db.doc(`admin_metadata/professors_${campus}`).get()).exists) {
      await db.doc(`admin_metadata/professors_${campus}`).set({
        totalProfessors: professorData.profs.length,
        professorsWithSchedule: matchedCount,
        professorsWithoutSchedule: unmatchedCount,
        lastUpdated: new Date(),
        version: "2.1.0",
      });
    }

    return {
      success: true,
      professorsUpdated: writes.length,
      withSchedule: matchedCount,
      withoutSchedule: unmatchedCount,
      respelled,
    };
}

function sameProfessor(prev, next) {
  // Key-sorted: Firestore does not hand map keys back in the order written.
  const canon = (v) => Array.isArray(v) ? `[${v.map(canon).join(",")}]`
    : v && typeof v === "object" ? `{${Object.keys(v).sort().map((k) => `${k}:${canon(v[k])}`).join(",")}}`
    : JSON.stringify(v ?? null);
  const pick = (o) => canon([o.name, o.chamber, o.email || null, o.contact || null, o.schedule || []]);
  return pick(prev) === pick(next);
}

// The timetable changed (a booklet upload, or an admin editing a section after
// an LMS "Timetable changes" notice): bring professor schedules along with it.
// `version` moves on every such write; other metadata fields do not matter here.
exports.onTimetableChanged = onDocumentWritten(
  { document: "campuses/{campus}/metadata/current", region: REGION, timeoutSeconds: 540, memory: "512MiB" },
  async (event) => {
    const campus = event.params.campus;
    const before = event.data?.before?.data()?.version;
    const after = event.data?.after?.data()?.version;
    if (!["hyderabad", "pilani", "goa"].includes(campus) || !after || before === after) return;
    try {
      const r = await rebuildSchedules(campus);
      console.log(`[professors] ${campus}: ${r.professorsUpdated} updated, ${r.withSchedule} with a schedule`);
    } catch (e) {
      console.warn(`[professors] ${campus}: rebuild skipped: ${e.message}`);
    }
  }
);

// ─── Archive timetables for a semester ───

// The term that follows the one being archived. BITS runs two terms per academic
// year, so sem 1 rolls into sem 2 of the same year and sem 2 into sem 1 of the
// next. Written to reference/app_config as the new current term, which is what
// lets a client tell a stale timetable from a live one.
function nextTerm(academicYear, semester) {
  if (semester === 1) return `${academicYear}_sem2`;
  const [start, end] = academicYear.split("-").map(Number);
  return `${start + 1}-${end + 1}_sem1`;
}

exports.archiveTimetables = onCall(
  { region: REGION, timeoutSeconds: 540, memory: "512MiB", enforceAppCheck: false },
  async (request) => {
    await requireAdmin(request);

    const { academicYear, semester } = request.data;

    if (!academicYear || !/^\d{4}-\d{4}$/.test(academicYear)) {
      throw new HttpsError("invalid-argument", "academicYear must be in YYYY-YYYY format");
    }
    if (semester !== 1 && semester !== 2) {
      throw new HttpsError("invalid-argument", "semester must be 1 or 2");
    }

    const archiveKey = `${academicYear}_sem${semester}`;
    console.log(`[archiveTimetables] archiving ${archiveKey}`);

    const userRefs = await db.collection("users").listDocuments();
    console.log(`[archiveTimetables] found ${userRefs.length} user refs`);

    let usersProcessed = 0;
    let usersSkipped = 0;
    let totalTimetablesArchived = 0;

    const BATCH_SIZE = 20;
    for (let i = 0; i < userRefs.length; i += BATCH_SIZE) {
      const batch = userRefs.slice(i, i + BATCH_SIZE);

      const results = await Promise.all(
        batch.map(async (userRef) => {
          const ttSnap = await userRef.collection("timetables").get();
          if (ttSnap.empty) return { uid: userRef.id, skipped: true };

          const timetables = ttSnap.docs
            .map((doc) => doc.data().timetableData)
            .filter(Boolean);

          if (timetables.length === 0) return { uid: userRef.id, skipped: true };

          return { uid: userRef.id, skipped: false, timetables };
        })
      );

      for (const result of results) {
        if (result.skipped) {
          usersSkipped++;
          continue;
        }

        await db
          .collection("users")
          .doc(result.uid)
          .collection("archivedTimetables")
          .doc(archiveKey)
          .set({
            academicYear,
            semester,
            archivedAt: FieldValue.serverTimestamp(),
            timetables: result.timetables,
          });

        usersProcessed++;
        totalTimetablesArchived += result.timetables.length;
      }

      if ((i + BATCH_SIZE) % 100 === 0) {
        console.log(`[archiveTimetables] progress: ${i + BATCH_SIZE}/${userRefs.length}`);
      }
    }

    // Open the new term only after the archive copies are safely written — if
    // this ran first and archiving then failed, every client would immediately
    // hide timetables whose archived copy did not exist yet.
    const newTerm = nextTerm(academicYear, semester);
    await db.doc("reference/app_config").set(
      { current_term: newTerm, current_term_set_at: FieldValue.serverTimestamp() },
      { merge: true }
    );

    console.log(`[archiveTimetables] done: ${usersProcessed} users, ${totalTimetablesArchived} timetables archived, ${usersSkipped} skipped; current term is now ${newTerm}`);

    return {
      success: true,
      usersProcessed,
      usersSkipped,
      totalTimetablesArchived,
      currentTerm: newTerm,
    };
  }
);

exports._test = { professorFields, matchExisting, sameProfessor, rebuildSchedules };
