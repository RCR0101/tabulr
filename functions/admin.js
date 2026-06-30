const { onCall, HttpsError } = require("firebase-functions/v2/https");
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

exports.getAdmins = onCall({ region: REGION, enforceAppCheck: false }, async () => {
  const snap = await db.collection("admin_emails").get();

  const admins = [];
  for (const doc of snap.docs) {
    const email = doc.id;
    const data = doc.data() || {};
    let name = data.name || null;
    let photoUrl = null;
    try {
      const user = await admin.auth().getUserByEmail(email);
      name = user.displayName || data.name || email.split("@")[0];
      photoUrl = user.photoURL || null;
    } catch (e) {
      // No Auth user yet for this email — fall back to stored name / local-part.
      name = data.name || email.split("@")[0];
    }
    if (name) admins.push({ name, photoUrl });
  }

  admins.sort((a, b) => a.name.localeCompare(b.name));
  return { admins };
});

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

    const { profsJsonBase64, campusCode } = request.data || {};
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

    const profsDoc = await db.doc(profsMetaKey).get();
    if (!profsDoc.exists || !profsDoc.data().profs) {
      throw new HttpsError(
        "failed-precondition",
        "No professors data found for " + campus + ". Upload profs.json first."
      );
    }
    const professorData = profsDoc.data();

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

    const professorsRef = db.collection(`reference/professors/${campus}-entries`);
    const existingSnapshot = await professorsRef.get();
    const deletePromises = [];
    existingSnapshot.forEach((doc) => deletePromises.push(doc.ref.delete()));
    if (deletePromises.length > 0) await Promise.all(deletePromises);

    const uploadPromises = [];
    let matchedCount = 0;
    let unmatchedCount = 0;

    professorData.profs.forEach((prof) => {
      if (!prof.name || !prof.chamber) return;

      const profNameNormalized = prof.name.trim().toUpperCase();
      const schedule = mergedScheduleMap[profNameNormalized] || [];

      if (schedule.length > 0) matchedCount++;
      else unmatchedCount++;

      const docRef = professorsRef.doc();
      uploadPromises.push(
        docRef.set({
          id: docRef.id,
          name: prof.name.trim(),
          chamber: prof.chamber.trim(),
          nameSearch: prof.name.trim().toLowerCase(),
          chamberSearch: prof.chamber.trim().toLowerCase(),
          schedule,
          createdAt: new Date(),
          updatedAt: new Date(),
        })
      );
    });

    await Promise.all(uploadPromises);

    await db.doc(`admin_metadata/professors_${campus}`).set({
      totalProfessors: uploadPromises.length,
      professorsWithSchedule: matchedCount,
      professorsWithoutSchedule: unmatchedCount,
      lastUpdated: new Date(),
      version: "2.1.0",
      uploadedBy: "admin_dashboard",
    });

    return {
      success: true,
      professorsUpdated: uploadPromises.length,
      withSchedule: matchedCount,
      withoutSchedule: unmatchedCount,
    };
  }
);

// ─── Archive timetables for a semester ───

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

    console.log(`[archiveTimetables] done: ${usersProcessed} users, ${totalTimetablesArchived} timetables archived, ${usersSkipped} skipped`);

    return {
      success: true,
      usersProcessed,
      usersSkipped,
      totalTimetablesArchived,
    };
  }
);
