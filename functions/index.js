const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

const REGION = "asia-south1";
const REP_COLLECTION = "reputation";
const ANN_COLLECTION = "announcements";

// ─── Shared helpers ───

const SCORE_FLOOR = -20;
const SUSPENSION_DAYS = 7;
const MAX_EVENTS = 50;

const VALID_EVENTS = {
  source_attached:          { points: 2 },
  post_removed_inaccuracy:  { points: -15 },
  post_disputed:            { points: -4 },
  correction_accepted:      { points: [-12, -8] },
  correct_flag:             { points: [14, 8] },
  post_community_verified:  { points: 10 },
  confirmed_verified_post:  { points: 1 },
  denied_incorrect_post:    { points: 2 },
  confirmed_incorrect_post: { points: -3 },
};

function isValidEvent(type, points) {
  const rule = VALID_EVENTS[type];
  if (!rule) return false;
  if (Array.isArray(rule.points)) return rule.points.includes(points);
  return rule.points === points;
}

function deriveUserDocId(email) {
  if (!email || !email.includes("@")) return null;
  const [username, domain] = email.split("@");
  const d = domain.toLowerCase();
  if (d === "hyderabad.bits-pilani.ac.in") return `${username}H`;
  if (d === "pilani.bits-pilani.ac.in") return `${username}P`;
  if (d === "goa.bits-pilani.ac.in") return `${username}G`;
  if (d === "dubai.bits-pilani.ac.in") return `${username}D`;
  return null;
}

function requireHydAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }
  const email = request.auth.token.email || "";
  if (!email.endsWith("@hyderabad.bits-pilani.ac.in")) {
    throw new HttpsError("permission-denied", "Hyderabad accounts only");
  }
  const docId = deriveUserDocId(email);
  if (!docId) {
    throw new HttpsError("permission-denied", "Unrecognized email");
  }
  return docId;
}

async function addRepEvent({ uid, type, points, description, announcementId }) {
  if (!isValidEvent(type, points)) return;

  const ref = db.collection(REP_COLLECTION).doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};

    const suspendedUntil = data.suspendedUntil
      ? data.suspendedUntil.toDate()
      : null;
    if (suspendedUntil && new Date() < suspendedUntil) return;

    let newScore = (data.score || 0) + points;
    let newSuspendedUntil = suspendedUntil;
    if (newScore <= SCORE_FLOOR) {
      newScore = 0;
      newSuspendedUntil = new Date(
        Date.now() + SUSPENSION_DAYS * 24 * 60 * 60 * 1000
      );
    }

    const event = {
      type,
      points,
      timestamp: Timestamp.now(),
      announcementId: announcementId || null,
      description,
    };
    const events = [event, ...(data.events || [])];
    if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;

    tx.set(ref, {
      score: newScore,
      lastActive: Timestamp.now(),
      suspendedUntil: newSuspendedUntil
        ? Timestamp.fromDate(newSuspendedUntil)
        : null,
      events,
    });
  });
}

async function getReputation(uid) {
  const doc = await db.collection(REP_COLLECTION).doc(uid).get();
  if (!doc.exists) return { score: 0, isSuspended: false, flagWeight: 1 };
  const data = doc.data();
  const score = data.score || 0;
  const suspendedUntil = data.suspendedUntil
    ? data.suspendedUntil.toDate()
    : null;
  const isSuspended = suspendedUntil && new Date() < suspendedUntil;

  let flagWeight = 1;
  if (score >= 100) flagWeight = 3;
  else if (score >= 50) flagWeight = 2;

  return { score, isSuspended, flagWeight };
}

function getDisputeQuorum(source) {
  if (!source || !source.type) return 3;
  const highTypes = ["officialLink", "emailScreenshot", "lmsLink"];
  const medTypes = ["photo", "crossReference"];
  if (highTypes.includes(source.type)) return 8;
  if (medTypes.includes(source.type)) return 6;
  if (source.type === "secondhand") return 4;
  return 3;
}

function computeVerificationState(cw, dw) {
  const total = cw + dw;
  if (total === 0) return "unverified";
  if (dw > 0 && dw >= cw * 2) return "likely_incorrect";
  if (dw > 0 && total > 0 && dw >= total * 0.25) return "contested";
  if (cw >= 3 && (total === 0 || dw < total * 0.25)) return "community_verified";
  return "partially_verified";
}

// ─── Reputation functions ───

const CLIENT_ALLOWED_EVENTS = new Set(["source_attached", "post_removed_inaccuracy"]);

exports.addReputationEvent = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }
  const callerDocId = deriveUserDocId(request.auth.token.email);
  if (!callerDocId) {
    throw new HttpsError("permission-denied", "Unrecognized email domain");
  }

  const { targetUid, type, points, description, announcementId } =
    request.data;
  if (!targetUid || !type || points == null || !description) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }
  if (!CLIENT_ALLOWED_EVENTS.has(type)) {
    throw new HttpsError("permission-denied", "Event type not allowed from client");
  }
  if (targetUid !== callerDocId) {
    throw new HttpsError("permission-denied", "Can only modify own reputation");
  }
  if (!isValidEvent(type, points)) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid event type/points: ${type}/${points}`
    );
  }

  await addRepEvent({ uid: targetUid, type, points, description, announcementId });
  return { success: true };
});

exports.touchReputationActivity = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }
  const callerDocId = deriveUserDocId(request.auth.token.email);
  if (!callerDocId) {
    throw new HttpsError("permission-denied", "Unrecognized email domain");
  }

  const { targetUid } = request.data;
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "Missing targetUid");
  }
  if (targetUid !== callerDocId) {
    throw new HttpsError("permission-denied", "Can only touch own activity");
  }

  await db
    .collection(REP_COLLECTION)
    .doc(targetUid)
    .set({ lastActive: FieldValue.serverTimestamp() }, { merge: true });
  return { success: true };
});

// ─── Announcement: Vote ───

exports.toggleVote = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  const callerDocId = requireHydAuth(request);

  const { announcementId, voteValue } = request.data;
  if (!announcementId || (voteValue !== 1 && voteValue !== -1)) {
    throw new HttpsError("invalid-argument", "Invalid announcementId or voteValue");
  }

  const annRef = db.collection(ANN_COLLECTION).doc(announcementId);
  const voteRef = annRef.collection("votes").doc(callerDocId);

  await db.runTransaction(async (tx) => {
    const [voteSnap, annSnap] = await Promise.all([
      tx.get(voteRef),
      tx.get(annRef),
    ]);
    if (!annSnap.exists) return;

    const existingVote = voteSnap.exists
      ? (voteSnap.data().vote ?? null)
      : null;

    let upDelta = 0;
    let downDelta = 0;

    if (existingVote === null) {
      if (voteValue === 1) upDelta = 1;
      else downDelta = 1;
      tx.set(voteRef, { vote: voteValue });
    } else if (existingVote === voteValue) {
      if (voteValue === 1) upDelta = -1;
      else downDelta = -1;
      tx.delete(voteRef);
    } else {
      if (voteValue === 1) {
        upDelta = 1;
        downDelta = -1;
      } else {
        upDelta = -1;
        downDelta = 1;
      }
      tx.set(voteRef, { vote: voteValue });
    }

    tx.update(annRef, {
      upvotes: FieldValue.increment(upDelta),
      downvotes: FieldValue.increment(downDelta),
    });
  });

  return { success: true };
});

// ─── Announcement: Flag ───

exports.submitFlag = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  const callerDocId = requireHydAuth(request);

  const { announcementId, reason, counterSourceUrl, confidence } = request.data;
  if (!announcementId || !reason) {
    throw new HttpsError("invalid-argument", "Missing announcementId or reason");
  }

  const rep = await getReputation(callerDocId);
  if (rep.isSuspended) {
    throw new HttpsError("permission-denied", "Account suspended");
  }

  const annRef = db.collection(ANN_COLLECTION).doc(announcementId);
  const flagRef = annRef.collection("flags").doc(callerDocId);

  let becameDisputed = false;

  await db.runTransaction(async (tx) => {
    const [existingFlag, annSnap] = await Promise.all([
      tx.get(flagRef),
      tx.get(annRef),
    ]);
    if (existingFlag.exists) return;
    if (!annSnap.exists) return;

    const annData = annSnap.data();
    const weight = rep.flagWeight;

    tx.set(flagRef, {
      reason,
      counterSourceUrl: counterSourceUrl || null,
      confidence: confidence || "fairly_sure",
      weight,
      timestamp: FieldValue.serverTimestamp(),
    });

    const currentFlagWeight = annData.totalFlagWeight || 0;
    const newFlagWeight = currentFlagWeight + weight;
    const quorum = getDisputeQuorum(annData.source);

    const updates = {
      totalFlagWeight: FieldValue.increment(weight),
    };

    if (
      !annData.topFlagReason ||
      weight > (currentFlagWeight / 2)
    ) {
      updates.topFlagReason = reason;
      if (counterSourceUrl) {
        updates.topFlagCounterSource = counterSourceUrl;
      }
    }

    if (
      newFlagWeight >= quorum &&
      (annData.disputeState || "undisputed") === "undisputed"
    ) {
      updates.disputeState = "disputed";
      becameDisputed = true;
    }

    tx.update(annRef, updates);
  });

  if (becameDisputed) {
    const annSnap = await annRef.get();
    const authorUid = annSnap.data()?.authorUid;
    if (authorUid) {
      await addRepEvent({
        uid: authorUid,
        type: "post_disputed",
        points: -4,
        description: "Post flagged as incorrect by community",
        announcementId,
      });
    }
  }

  await db
    .collection(REP_COLLECTION)
    .doc(callerDocId)
    .set({ lastActive: FieldValue.serverTimestamp() }, { merge: true });

  return { success: true };
});

// ─── Announcement: Verify ───

exports.submitVerification = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  const callerDocId = requireHydAuth(request);

  const { announcementId, type, note } = request.data;
  if (!announcementId || (type !== "confirm" && type !== "deny")) {
    throw new HttpsError("invalid-argument", "Invalid announcementId or type");
  }

  const rep = await getReputation(callerDocId);
  if (rep.isSuspended) {
    throw new HttpsError("permission-denied", "Account suspended");
  }

  const isConfirm = type === "confirm";
  const annRef = db.collection(ANN_COLLECTION).doc(announcementId);
  const verifRef = annRef.collection("verifications").doc(callerDocId);

  await db.runTransaction(async (tx) => {
    const [existing, annSnap] = await Promise.all([
      tx.get(verifRef),
      tx.get(annRef),
    ]);
    if (!annSnap.exists) return;

    const weight = rep.flagWeight;

    if (existing.exists) {
      const oldType = existing.data().type;
      const oldWeight = existing.data().weight || 1;
      const wasConfirm = oldType === "confirm";
      if (wasConfirm === isConfirm) return;

      tx.update(annRef, {
        confirmWeight: FieldValue.increment(isConfirm ? weight : -oldWeight),
        denyWeight: FieldValue.increment(isConfirm ? -oldWeight : weight),
        confirmCount: FieldValue.increment(isConfirm ? 1 : -1),
        denyCount: FieldValue.increment(isConfirm ? -1 : 1),
      });
    } else {
      const updates = {};
      if (isConfirm) {
        updates.confirmWeight = FieldValue.increment(weight);
        updates.confirmCount = FieldValue.increment(1);
      } else {
        updates.denyWeight = FieldValue.increment(weight);
        updates.denyCount = FieldValue.increment(1);
      }
      tx.update(annRef, updates);
    }

    tx.set(verifRef, {
      type,
      note: note || null,
      weight,
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  // Recompute verification state and handle reputation
  const annSnap = await annRef.get();
  if (annSnap.exists) {
    const annData = annSnap.data();
    const cw = annData.confirmWeight || 0;
    const dw = annData.denyWeight || 0;
    const oldState = annData.verificationState || "unverified";
    const newState = computeVerificationState(cw, dw);

    if (newState !== oldState) {
      await annRef.update({ verificationState: newState });
      const authorUid = annData.authorUid;

      if (newState === "community_verified" && oldState !== "community_verified" && authorUid) {
        await addRepEvent({
          uid: authorUid,
          type: "post_community_verified",
          points: 10,
          description: "Post reached community verified status",
          announcementId,
        });
        const verifs = await annRef.collection("verifications").get();
        for (const v of verifs.docs) {
          if (v.data().type === "confirm") {
            await addRepEvent({
              uid: v.id,
              type: "confirmed_verified_post",
              points: 1,
              description: "Confirmed a post that reached community verified",
              announcementId,
            });
          }
        }
      }

      if (newState === "likely_incorrect" && oldState !== "likely_incorrect") {
        const verifs = await annRef.collection("verifications").get();
        for (const v of verifs.docs) {
          if (v.data().type === "deny") {
            await addRepEvent({
              uid: v.id,
              type: "denied_incorrect_post",
              points: 2,
              description: "Denied a post later found likely incorrect",
              announcementId,
            });
          } else if (v.data().type === "confirm") {
            await addRepEvent({
              uid: v.id,
              type: "confirmed_incorrect_post",
              points: -3,
              description: "Confirmed a post later found likely incorrect",
              announcementId,
            });
          }
        }
      }
    }

    // Check if deny votes should trigger dispute
    if (!isConfirm) {
      const currentDw = annData.denyWeight || 0;
      const currentFlagWeight = annData.totalFlagWeight || 0;
      const quorum = getDisputeQuorum(annData.source);
      const denyContribution = Math.round(currentDw * 0.5);
      if (
        currentFlagWeight + denyContribution >= quorum &&
        (annData.disputeState || "undisputed") === "undisputed"
      ) {
        await annRef.update({ disputeState: "disputed" });
      }
    }
  }

  await db
    .collection(REP_COLLECTION)
    .doc(callerDocId)
    .set({ lastActive: FieldValue.serverTimestamp() }, { merge: true });

  return { success: true };
});

// ─── Announcement: Accept Correction ───

exports.acceptCorrection = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  const callerDocId = requireHydAuth(request);

  const { announcementId, correctionText, correctionSource } = request.data;
  if (!announcementId || !correctionText) {
    throw new HttpsError("invalid-argument", "Missing announcementId or correctionText");
  }

  const annRef = db.collection(ANN_COLLECTION).doc(announcementId);
  const annSnap = await annRef.get();
  if (!annSnap.exists) {
    throw new HttpsError("not-found", "Announcement not found");
  }

  const annData = annSnap.data();
  if (annData.authorUid !== callerDocId) {
    throw new HttpsError("permission-denied", "Only the author can accept corrections");
  }

  const conf = annData.confidence || "fairly_sure";
  const penalty = conf === "certain" ? -12 : -8;

  await annRef.update({
    disputeState: "correction_accepted",
    correctionText,
    correctionSource: correctionSource || null,
  });

  await addRepEvent({
    uid: callerDocId,
    type: "correction_accepted",
    points: penalty,
    description: "Accepted correction on own post",
    announcementId,
  });

  const flagsSnap = await annRef.collection("flags").get();
  if (flagsSnap.docs.length > 0) {
    const firstFlag = flagsSnap.docs[0];
    const flaggerUid = firstFlag.id;
    const hasCounterSource = !!firstFlag.data().counterSourceUrl;
    await addRepEvent({
      uid: flaggerUid,
      type: "correct_flag",
      points: hasCounterSource ? 14 : 8,
      description: hasCounterSource
        ? "First correct flag with counter-source"
        : "First correct flag on incorrect post",
      announcementId,
    });
  }

  return { success: true };
});

// ─── Admin functions (Node.js — checkAdmin, professors) ───
// uploadTimetable and uploadExamSeating are in functions-python/
const adminFunctions = require("./admin");
exports.checkAdminStatus = adminFunctions.checkAdminStatus;
exports.getAdmins = adminFunctions.getAdmins;
exports.rebuildProfessorSchedules = adminFunctions.rebuildProfessorSchedules;
exports.archiveTimetables = adminFunctions.archiveTimetables;
