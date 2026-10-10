const { test } = require("node:test");
const assert = require("node:assert/strict");
const { buildIcs, noClassDates, classWindow, examCourseCodes, roomFor } = require("../ics.js");

// Real rows from the Hyderabad 2026-27 first-semester booklet.
const HYD = [
  { date: "2026-08-03", label: "Class work begins", category: "milestone" },
  { date: "2026-08-15", label: "Independence Day (H)", category: "holiday" },
  { date: "2026-08-17", label: "Last day for substitution of courses", category: "deadline" },
  { date: "2026-10-02", label: "Gandhi Jayanti (H)", category: "holiday" },
  { date: "2026-10-05", endDate: "2026-10-10", label: "Mid sem Exam (Classwork Suspendedl)", category: "exam" },
  { date: "2026-10-23", endDate: "2026-10-25", label: "ATMOS - 2026 (Class work Suspended)", category: "milestone" },
  { date: "2026-11-27", label: "Last day of classes", category: "deadline" },
];
const SEM = { semesterStart: "2026-08-03", semesterEnd: "2026-12-18" };

const section = (sectionId, type, schedule, room = "F102") =>
  ({ sectionId, type: `SectionType.${type}`, instructor: "Jane Doe", room, schedule });
const sel = (courseCode, s) => ({ courseCode, sectionId: s.sectionId, section: s });

const CS = sel("CS F211", section("L1", "L", [{ days: ["DayOfWeek.M", "DayOfWeek.F"], hours: [2, 3] }]));
const COURSES = {
  "CS F211": {
    title: "Data Structures & Algorithms",
    midSemExam: { date: "2026-10-07T00:00:00.000", timeSlot: "TimeSlot.MS2" },
    endSemExam: { date: "2026-12-03T00:00:00.000", timeSlot: "TimeSlot.FN" },
  },
};
const build = (extra = {}) => buildIcs({
  selections: [CS], courses: COURSES, campus: "hyderabad", academicEvents: HYD,
  semesterDates: SEM, timetableId: "tt7", now: new Date("2026-10-03T00:00:00Z"), ...extra,
});
const vevents = (ics) => ics.split("BEGIN:VEVENT").slice(1);
const field = (ev, name) => (ev.match(new RegExp(`^${name}[;:](.*)$`, "m")) || [])[1];
const unfold = (ics) => ics.replace(/\r\n /g, "");

test("well-formed calendar with an Asia/Kolkata VTIMEZONE", () => {
  const ics = build();
  assert.ok(ics.startsWith("BEGIN:VCALENDAR\r\n"));
  assert.ok(ics.endsWith("END:VCALENDAR\r\n"));
  assert.match(ics, /TZID:Asia\/Kolkata/);
  assert.equal((ics.match(/BEGIN:VEVENT/g) || []).length, (ics.match(/END:VEVENT/g) || []).length);
});

test("classes run from the first class day to the last day of classes", () => {
  const monday = vevents(build()).find((e) => e.includes("BYDAY=MO"));
  // Aug 3 is a Monday and the first day of classwork.
  assert.equal(field(monday, "DTSTART"), "TZID=Asia/Kolkata:20260803T090000");
  // Nov 27 23:59:59 IST is 18:29:59 UTC.
  assert.match(monday, /UNTIL=20261127T182959Z/);
});

test("consecutive hours merge into one block with a 10-minute alarm", () => {
  const monday = vevents(build()).find((e) => e.includes("BYDAY=MO"));
  assert.equal(field(monday, "DTEND"), "TZID=Asia/Kolkata:20260803T105000");
  assert.match(monday, /TRIGGER:-PT10M/);
  assert.equal(vevents(build()).filter((e) => e.includes("RRULE")).length, 2); // Mon + Fri
});

test("no class on holidays, classwork-suspended spans, or exam weeks", () => {
  const ics = unfold(build());
  const friday = vevents(ics).find((e) => e.includes("BYDAY=FR"));
  const ex = field(friday, "EXDATE");
  assert.ok(ex.includes("20261002T090000"), "Gandhi Jayanti (Fri)");
  assert.ok(ex.includes("20261009T090000"), "mid-sem week (Fri Oct 9)");
  assert.ok(ex.includes("20261023T090000"), "ATMOS, class work suspended (Fri)");
  assert.ok(!ex.includes("20261016T090000"), "an ordinary Friday keeps its class");
  const monday = vevents(ics).find((e) => e.includes("BYDAY=MO"));
  assert.ok(field(monday, "EXDATE").includes("20261005T090000"), "mid-sem Monday");
});

test("a holiday on the opening weekday moves the series start, not an EXDATE", () => {
  // Saturday class: Aug 8 is the first Saturday; make it a holiday.
  const sat = sel("CS F211", section("T1", "T", [{ days: ["DayOfWeek.S"], hours: [1] }]));
  const ics = build({ selections: [sat], academicEvents: [...HYD, { date: "2026-08-08", label: "Some Fest (H)", category: "holiday" }] });
  const ev = vevents(ics).find((e) => e.includes("BYDAY=SA"));
  // Aug 8 is the fest and Aug 15 Independence Day: the first real class is Aug 22.
  assert.equal(field(ev, "DTSTART"), "TZID=Asia/Kolkata:20260822T080000");
});

test("without calendar rows, the admin semester dates and breaks still apply", () => {
  const ics = unfold(buildIcs({
    selections: [CS], courses: COURSES, campus: "hyderabad", academicEvents: [],
    semesterDates: { ...SEM, midsemStart: "2026-10-05", midsemEnd: "2026-10-10" },
  }));
  const monday = vevents(ics).find((e) => e.includes("BYDAY=MO"));
  assert.match(monday, /UNTIL=20261218T182959Z/);
  assert.ok(field(monday, "EXDATE").includes("20261005T090000"));
});

test("UIDs are stable across exports", () => {
  const uids = (ics) => vevents(ics).map((e) => field(e, "UID"));
  assert.deepEqual(uids(build()), uids(build({ now: new Date() })));
});

test("exams: campus slot times, two alarms, room only once seating is out", () => {
  let ics = unfold(build());
  const mid = vevents(ics).find((e) => e.includes("Mid-Sem Exam"));
  assert.equal(field(mid, "DTSTART"), "TZID=Asia/Kolkata:20261007T113000");
  assert.equal(field(mid, "DTEND"), "TZID=Asia/Kolkata:20261007T130000");
  assert.match(mid, /TRIGGER:-P1D/);
  assert.match(mid, /TRIGGER:-PT1H30M/);
  assert.match(mid, /announced mid-semester/);
  assert.equal(field(mid, "LOCATION"), undefined);

  ics = build({ seats: { "CS F211": { roomNo: "F105", examDate: "2026-10-07" } } });
  const seated = vevents(ics).find((e) => e.includes("Mid-Sem Exam"));
  assert.equal(field(seated, "LOCATION"), "F105");
  // The seating sheet is for the mid-sem; the compre stays unassigned.
  assert.equal(field(vevents(ics).find((e) => e.includes("Comprehensive Exam")), "LOCATION"), undefined);

  const goa = build({ campus: "goa" });
  assert.equal(field(vevents(goa).find((e) => e.includes("Comprehensive Exam")), "DTSTART"), "TZID=Asia/Kolkata:20261203T100000");
});

test("deadlines and exam windows become all-day reminders; holidays do not", () => {
  const evs = vevents(build());
  const sub = evs.find((e) => e.includes("substitution"));
  assert.equal(field(sub, "DTSTART"), "VALUE=DATE:20260817");
  assert.match(sub, /TRIGGER:-P3D/);
  const midsem = evs.find((e) => e.includes("SUMMARY:Mid sem Exam"));
  assert.equal(field(midsem, "DTEND"), "VALUE=DATE:20261011"); // inclusive end + 1
  assert.ok(!evs.some((e) => e.includes("SUMMARY:Independence Day")));
});

test("export options control which fields appear; SUMMARY never empty", () => {
  let ev = vevents(build({ options: { showInstructor: false, showRoom: false } }))[0];
  assert.ok(!ev.includes("Jane Doe"));
  assert.equal(field(ev, "LOCATION"), undefined);
  ev = vevents(build({ options: { showCourseCode: false, showCourseTitle: false } }))[0];
  assert.equal(field(ev, "SUMMARY"), "CS F211");
  assert.ok(!build({ options: { showExamDates: false } }).includes("Mid-Sem Exam"));
});

test("RFC 5545: escaping and 75-octet folding", () => {
  const ics = build({ courses: { "CS F211": { title: "A, B; C\\D\nE ".repeat(8) } } });
  assert.ok(ics.split("\r\n").every((l) => l.length <= 75));
  const summary = field(unfold(ics), "SUMMARY");
  assert.ok(summary.includes("A\\, B\\; C\\\\D\\nE"));
});

test("noClassDates and classWindow read the real booklet rows", () => {
  const off = noClassDates(HYD);
  for (const d of ["2026-08-15", "2026-10-05", "2026-10-10", "2026-10-24"]) assert.ok(off.has(d), d);
  assert.ok(!off.has("2026-08-17"), "a deadline is not a day off");
  assert.deepEqual(classWindow(HYD, SEM), { start: "2026-08-03", end: "2026-11-27" });
});

test("seating helpers: combined exam codes and ID ranges", () => {
  assert.deepEqual(examCourseCodes("CS F407-CS U407"), ["CS F407", "CS U407"]);
  assert.deepEqual(examCourseCodes("ECE-EEE F211"), ["ECE F211", "EEE F211"]);
  assert.deepEqual(examCourseCodes("MATH F424-U424"), ["MATH F424", "MATH U424"]);
  const rooms = [{ roomNo: "F102", idFrom: "2022A7PS0001H", idTo: "2022A7PS0100H" },
                 { roomNo: "F103", idFrom: "2022A7PS0101H", idTo: "2022A7PS0200H" }];
  assert.equal(roomFor(rooms, "2022a7ps0150h"), "F103");
  assert.equal(roomFor(rooms, "2023A7PS0001H"), null);
  assert.equal(roomFor([{ roomNo: "Main Hall" }], "anyone"), "Main Hall");
});

test("no term dates at all: no class events, and no crash", () => {
  const ics = buildIcs({ selections: [CS], courses: COURSES, campus: "hyderabad" });
  assert.ok(!ics.includes("RRULE"));
  assert.ok(ics.includes("Mid-Sem Exam"), "exams have their own dates");
  assert.ok(buildIcs({ selections: [], courses: {}, campus: "hyderabad", calendarName: "turned off" }).endsWith("END:VCALENDAR\r\n"));
});
