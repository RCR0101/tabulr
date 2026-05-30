const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const SCORE_FLOOR = -20;
const SUSPENSION_DAYS = 7;
const MAX_EVENTS = 50;
const COLLECTION = "reputation";

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

exports.addReputationEvent = onCall(
  { region: "asia-south1" },
  async (request) => {
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

    if (!isValidEvent(type, points)) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid event type/points: ${type}/${points}`
      );
    }

    const ref = db.collection(COLLECTION).doc(targetUid);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() : {};

      const suspendedUntil = data.suspendedUntil
        ? data.suspendedUntil.toDate()
        : null;
      if (suspendedUntil && new Date() < suspendedUntil) return;

      const currentScore = data.score || 0;
      let newScore = currentScore + points;

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
        timestamp: admin.firestore.Timestamp.now(),
        announcementId: announcementId || null,
        description,
      };

      const events = [event, ...(data.events || [])];
      if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;

      tx.set(ref, {
        score: newScore,
        lastActive: admin.firestore.Timestamp.now(),
        suspendedUntil: newSuspendedUntil
          ? admin.firestore.Timestamp.fromDate(newSuspendedUntil)
          : null,
        events,
      });
    });

    return { success: true };
  }
);

exports.touchReputationActivity = onCall(
  { region: "asia-south1" },
  async (request) => {
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

    await db
      .collection(COLLECTION)
      .doc(targetUid)
      .set(
        { lastActive: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );

    return { success: true };
  }
);
