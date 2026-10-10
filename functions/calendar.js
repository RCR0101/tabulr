// Calendar export and the live webcal feed. Both build through ics.js; this
// file only loads the data.
//
//   exportIcs (callable)  the .ics download, from the timetable the app sends.
//   calendarFeed (HTTP)   tabulr.net/cal/<token>.ics. Calendar apps re-poll it,
//                         so it re-reads the saved timetable, picks up section
//                         changes, the academic calendar and, once seating is
//                         published, the student's exam room.

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { buildIcs, examCourseCodes, roomFor } = require("./ics");
const { deriveUserDocId } = require("./identity");

const db = admin.firestore();
const REGION = "asia-south1";
const CAMPUSES = ["hyderabad", "pilani", "goa"];

const docIdFor = (code) => String(code).split("/")[0].trim().replace(/\s+/g, "_");

// Campus-wide data, shared by every feed on this instance for a few minutes:
// calendar apps poll, and these documents change a handful of times a term.
const cache = new Map();
async function cached(key, load) {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < 10 * 60 * 1000) return hit.value;
  const value = await load();
  cache.set(key, { at: Date.now(), value });
  return value;
}

const titles = (campus) => cached(`titles:${campus}`, async () => {
  const doc = await db.doc(`campuses/${campus}/catalog/courses_master`).get();
  const map = {};
  try {
    for (const e of JSON.parse(doc.data()?.entriesJson || "[]")) map[e.course_code] = e.title;
  } catch (_) { /* a broken bundle costs titles, not the calendar */ }
  return map;
});
const academicEvents = (campus) => cached(`cal:${campus}`, async () =>
  (await db.doc(`campuses/${campus}/academicCalendar/current`).get()).data()?.events || []);
const appConfig = () => cached("config", async () =>
  (await db.doc("reference/app_config").get()).data() || {});
const semesterDates = async () => (await appConfig()).semester_dates || {};
const seating = (campus) => cached(`seat:${campus}`, async () => {
  // course code → {rooms, examDate}; combined exams are listed under each code.
  const out = {};
  for (const d of (await db.collection(`campuses/${campus}/exam_seating`).get()).docs) {
    const data = d.data();
    for (const code of examCourseCodes(d.id.replace(/_/g, " "))) {
      out[code] = { rooms: data.rooms || [], examDate: parseSeatingDate(data.exam_date) };
    }
  }
  return out;
});

// The sheet prints "09 October 26 - 09:30 AM".
function parseSeatingDate(raw) {
  const m = String(raw || "").match(/(\d{1,2})\s+([A-Za-z]+)\s+(\d{2,4})/);
  if (!m) return null;
  const month = new Date(`${m[2]} 1, 2000`).getMonth();
  if (Number.isNaN(month)) return null;
  const year = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
  return `${year}-${String(month + 1).padStart(2, "0")}-${m[1].padStart(2, "0")}`;
}

async function courseDocs(campus, codes) {
  if (codes.length === 0) return {};
  const refs = codes.map((c) => db.doc(`campuses/${campus}/timetable/${docIdFor(c)}`));
  const snaps = await db.getAll(...refs);
  const out = {};
  snaps.forEach((s, i) => { if (s.exists) out[codes[i]] = s.data(); });
  return out;
}

/** Everything buildIcs needs besides the selections. */
async function context(campus, selections, studentId) {
  const codes = [...new Set(selections.map((s) => s.courseCode))];
  const [docs, names, events, sem, seats] = await Promise.all([
    courseDocs(campus, codes), titles(campus), academicEvents(campus), semesterDates(),
    studentId ? seating(campus) : Promise.resolve({}),
  ]);
  const courses = {};
  const mySeats = {};
  for (const code of codes) {
    const d = docs[code] || {};
    courses[code] = {
      title: names[code] || "",
      midSemExam: d.mid_sem_exam || d.midSemExam || null,
      endSemExam: d.end_sem_exam || d.endSemExam || null,
      sections: d.sections || [],
    };
    const s = seats[code];
    const room = s && roomFor(s.rooms, studentId);
    if (room && s.examDate) mySeats[code] = { roomNo: room, examDate: s.examDate };
  }
  return { courses, academicEvents: events, semesterDates: sem, seats: mySeats };
}

// A section the timetable division has since moved (room, instructor, time)
// shows as it is now; one that vanished keeps the saved copy.
const liveSections = (selections, courses) => selections.map((sel) => {
  const now = courses[sel.courseCode]?.sections.find((s) => s.sectionId === sel.sectionId);
  return now ? { ...sel, section: now } : sel;
});

async function studentIdOf(userDocId) {
  if (!userDocId) return null;
  const d = await db.doc(`users/${userDocId}/exam_seating_prefs/data`).get();
  return d.data()?.student_id || null;
}

function checkSelections(selections) {
  if (!Array.isArray(selections) || selections.length > 60 || JSON.stringify(selections).length > 200000) {
    throw new HttpsError("invalid-argument", "selections must be a list of at most 60 sections");
  }
  for (const s of selections) {
    if (typeof s?.courseCode !== "string" || typeof s?.sectionId !== "string" || typeof s?.section !== "object") {
      throw new HttpsError("invalid-argument", "malformed section");
    }
  }
}

exports.exportIcs = onCall({ region: REGION, enforceAppCheck: false }, async (request) => {
  const { selections, campus, options, timetableId, calendarName } = request.data || {};
  if (!CAMPUSES.includes(campus)) throw new HttpsError("invalid-argument", "Invalid campus");
  checkSelections(selections);
  const uid = deriveUserDocId(request.auth?.token?.email);
  const ctx = await context(campus, selections, await studentIdOf(uid));
  return {
    ics: buildIcs({
      selections, campus, ...ctx,
      options: typeof options === "object" ? options : {},
      timetableId: String(timetableId || "").slice(0, 100),
      calendarName: String(calendarName || "").slice(0, 100),
    }),
  };
});

exports.calendarFeed = onRequest({ region: REGION, memory: "256MiB" }, async (req, res) => {
  // /cal/<token>.ics through the Hosting rewrite, or ?t=<token> directly.
  const token = (req.query.t || req.path.split("/").pop() || "").replace(/\.ics$/, "");
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(token)) return res.status(404).send("Not found");

  res.set("Content-Type", "text/calendar; charset=utf-8");
  // An admin can switch every link off. Read fresh, not from the cache, so it
  // takes effect at once; an empty calendar (not an error) is what makes
  // calendar apps drop the events they already hold.
  if ((await db.doc("reference/app_config").get()).data()?.calendar_feeds_off === true) {
    res.set("Cache-Control", "public, max-age=300, s-maxage=300");
    return res.send(buildIcs({ selections: [], courses: {}, campus: "hyderabad", calendarName: "turned off" }));
  }

  const feed = (await db.doc(`calendar_feeds/${token}`).get()).data();
  if (!feed) return res.status(404).send("This calendar link was turned off.");
  // The app saves {userId, timetableData: <Timetable JSON>, lastUpdated}.
  const raw = (await db.doc(`users/${feed.owner}/timetables/${feed.timetableId}`).get()).data();
  const tt = raw?.timetableData || raw;
  if (!tt) return res.status(404).send("This timetable no longer exists.");

  const campus = CAMPUSES.includes(tt.campus) ? tt.campus : "hyderabad";
  // A past term's timetable is never reconciled against this term's sections
  // (same rule as the app): its classes simply leave the calendar.
  const current = (await appConfig()).current_term;
  const pastTerm = Boolean(current && tt.term && tt.term !== current);
  const saved = pastTerm ? [] : tt.selectedSections || [];
  const ctx = await context(campus, saved, await studentIdOf(feed.owner));
  const ics = buildIcs({
    selections: liveSections(saved, ctx.courses), campus, ...ctx,
    ...(pastTerm ? { academicEvents: [] } : {}),
    options: feed.options || {}, timetableId: feed.timetableId, calendarName: tt.name,
  });

  // The URL is secret per timetable, so the CDN may hold it briefly.
  res.set("Cache-Control", "public, max-age=900, s-maxage=900");
  res.send(ics);
});

exports._test = { parseSeatingDate, liveSections, docIdFor, context };
