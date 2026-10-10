// Builds a timetable's iCalendar document. The one generator for both the
// .ics download (exportIcs) and the live webcal feed (calendarFeed), so the
// two can never disagree about which days have class.
//
// Pure: callers load the data. Dates are plain calendar dates ("2026-08-15");
// all wall times are Asia/Kolkata, which every campus uses (no DST).

const DAY = { "DayOfWeek.M": 1, "DayOfWeek.T": 2, "DayOfWeek.W": 3, "DayOfWeek.Th": 4, "DayOfWeek.F": 5, "DayOfWeek.S": 6 };
const BYDAY = { 1: "MO", 2: "TU", 3: "WE", 4: "TH", 5: "FR", 6: "SA" };
const HOUR_START = { 1: 8, 2: 9, 3: 10, 4: 11, 5: 12, 6: 13, 7: 14, 8: 15, 9: 16, 10: 17, 11: 18, 12: 19 };
const EXAM_START = {
  pilani: { FN: [8, 0], AN: [15, 0], MS1: [9, 30], MS2: [11, 30], MS3: [14, 0], MS4: [16, 0] },
  goa: { FN: [10, 0], AN: [14, 0], MS1: [9, 30], MS2: [11, 30], MS3: [14, 0], MS4: [16, 0] },
  hyderabad: { FN: [9, 30], AN: [14, 0], MS1: [9, 30], MS2: [11, 30], MS3: [14, 0], MS4: [16, 0] },
};
const TYPE_LABEL = { "SectionType.L": "Lecture", "SectionType.P": "Practical", "SectionType.T": "Tutorial" };

// Rows that mean "no classes that day" even when not marked as a holiday.
const NO_CLASS_RE = /class\s*work\s+suspended|classes?\s+suspended|no\s+class|recess|vacation/i;
const CLASSES_BEGIN_RE = /class\s*work\s+begins|classes\s+begin/i;
const CLASSES_END_RE = /last\s+(?:day|date)\s+(?:of|for)\s+class(?:es|work)/i;

// ── dates ───────────────────────────────────────────────────────────────

const ymd = (s) => (s ? String(s).slice(0, 10) : "");
const toDate = (s) => { const [y, m, d] = ymd(s).split("-").map(Number); return new Date(Date.UTC(y, m - 1, d)); };
const iso = (d) => d.toISOString().slice(0, 10);
const addDays = (d, n) => new Date(d.getTime() + n * 86400000);
const compact = (s) => ymd(s).replace(/-/g, "");
const two = (n) => String(n).padStart(2, "0");
const local = (date, h, m) => `${compact(date)}T${two(h)}${two(m)}00`;
function addMinutes(date, h, m, mins) {
  const t = h * 60 + m + mins;
  return local(date, Math.floor(t / 60), t % 60);
}
// IST wall time → UTC instant, for RRULE UNTIL (must be UTC with a TZID start).
function istToUtc(date, h, m, s) {
  const d = new Date(toDate(date).getTime() + ((h * 60 + m) * 60 + s) * 1000 - 330 * 60000);
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** Every date with no classes: holidays, "classwork suspended" spans, recess. */
function noClassDates(academicEvents, breakPeriods = []) {
  const off = new Set();
  const span = (from, to) => {
    for (let d = toDate(from); d <= toDate(to || from); d = addDays(d, 1)) off.add(iso(d));
  };
  for (const ev of academicEvents) {
    const label = ev.label || "";
    if (ev.category === "holiday" || /\(H\)/.test(label) || NO_CLASS_RE.test(label)) span(ev.date, ev.endDate);
  }
  for (const b of breakPeriods) if (b.start && b.end) span(b.start, b.end);
  return off;
}

/** First and last day of classes: the academic calendar's own rows, else the admin's semester dates. */
function classWindow(academicEvents, semesterDates = {}) {
  const find = (re) => academicEvents.find((e) => re.test(e.label || ""));
  const begin = find(CLASSES_BEGIN_RE);
  const end = find(CLASSES_END_RE);
  return {
    start: ymd(begin ? begin.date : semesterDates.semesterStart),
    end: ymd(end ? end.endDate || end.date : semesterDates.semesterEnd),
  };
}

// ── text ────────────────────────────────────────────────────────────────

const esc = (s) => String(s).replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/,/g, "\\,").replace(/;/g, "\\;");
function fold(line) {
  if (line.length <= 75) return line;
  let out = line.slice(0, 75);
  for (let i = 75; i < line.length; i += 74) out += "\r\n " + line.slice(i, i + 74);
  return out;
}
function runs(hours) {
  const out = [];
  for (const h of [...hours].sort((a, b) => a - b)) {
    if (out.length && h === out[out.length - 1].at(-1) + 1) out[out.length - 1].push(h);
    else out.push([h]);
  }
  return out;
}

const DEFAULT_OPTIONS = {
  showCourseCode: true, showCourseTitle: true, showSectionId: true,
  showInstructor: true, showRoom: true, showExamDates: true,
};

/**
 * @param {object} p
 * @param {Array} p.selections      saved SelectedSection JSON
 * @param {object} p.courses        code → {title, midSemExam?, endSemExam?}
 * @param {string} p.campus
 * @param {Array} [p.academicEvents]  [{date, endDate?, label, category}]
 * @param {object} [p.semesterDates]  {semesterStart, semesterEnd, midsemStart, …}
 * @param {object} [p.seats]          code → {roomNo, examDate} once seating is out
 * @param {object} [p.options]        the export dialog's switches
 * @param {string} [p.timetableId]    UID namespace, so re-imports update in place
 * @param {string} [p.calendarName]
 * @param {Date}   [p.now]
 */
function buildIcs(p) {
  const o = { ...DEFAULT_OPTIONS, ...(p.options || {}) };
  const events = p.academicEvents || [];
  const sd = p.semesterDates || {};
  const window = classWindow(events, sd);
  const off = noClassDates(events, [
    { start: sd.midsemStart, end: sd.midsemEnd },
    { start: sd.endsemStart, end: sd.endsemEnd },
  ]);
  const stamp = (p.now || new Date()).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const ns = String(p.timetableId || "tt").replace(/\s/g, "");
  const uid = (s) => `tabulr-${ns}-${s}@tabulr.app`.replace(/\s/g, "");
  const summary = (code, title) => {
    const parts = [];
    if (o.showCourseCode) parts.push(code);
    if (o.showCourseTitle && title) parts.push(title);
    return parts.length ? parts.join(" — ") : code;
  };

  const lines = [
    "BEGIN:VCALENDAR", "PRODID:-//Tabulr//EN", "VERSION:2.0", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    `X-WR-CALNAME:${esc(`Tabulr${p.calendarName ? ` — ${p.calendarName}` : ""}`)}`,
    "X-WR-TIMEZONE:Asia/Kolkata",
    // Calendar apps re-poll a subscription at most this often.
    "REFRESH-INTERVAL;VALUE=DURATION:PT6H", "X-PUBLISHED-TTL:PT6H",
    "BEGIN:VTIMEZONE", "TZID:Asia/Kolkata", "BEGIN:STANDARD", "DTSTART:19700101T000000",
    "TZOFFSETFROM:+0530", "TZOFFSETTO:+0530", "TZNAME:IST", "END:STANDARD", "END:VTIMEZONE",
  ];

  // Classes: one weekly series per (section, day, run of consecutive hours),
  // from the first class day to the last, minus every no-class date.
  // No known term dates (no calendar rows, no admin dates): no class events,
  // rather than a series with no end.
  const hasWindow = /^\d{4}-\d{2}-\d{2}$/.test(window.start) && /^\d{4}-\d{2}-\d{2}$/.test(window.end);
  const until = hasWindow ? istToUtc(window.end, 23, 59, 59) : null;
  for (const sel of hasWindow ? p.selections || [] : []) {
    const s = sel.section || {};
    const title = p.courses[sel.courseCode]?.title || "";
    for (const entry of s.schedule || []) {
      for (const dayName of entry.days || []) {
        const wd = DAY[dayName];
        if (!wd) continue;
        let first = toDate(window.start);
        while (first.getUTCDay() !== wd) first = addDays(first, 1);
        for (const run of runs(entry.hours || [])) {
          const h = HOUR_START[run[0]];
          if (h === undefined) continue;
          const dates = [];
          for (let d = first; d <= toDate(window.end); d = addDays(d, 7)) dates.push(iso(d));
          const kept = dates.filter((d) => !off.has(d));
          if (kept.length === 0) continue;
          const skipped = dates.filter((d) => off.has(d) && d > kept[0]);
          const desc = [
            o.showSectionId && `${TYPE_LABEL[s.type] || "Class"} · Section ${sel.sectionId}`,
            o.showInstructor && s.instructor && `Instructor: ${s.instructor}`,
            o.showRoom && s.room && `Room: ${s.room}`,
          ].filter(Boolean);
          lines.push(
            "BEGIN:VEVENT",
            `UID:${uid(`${sel.courseCode}-${sel.sectionId}-${dayName.split(".")[1]}-${run[0]}`)}`,
            `DTSTAMP:${stamp}`,
            // Starts on the first day that actually has class, so a holiday on
            // the opening weekday is not the series' anchor.
            `DTSTART;TZID=Asia/Kolkata:${local(kept[0], h, 0)}`,
            `DTEND;TZID=Asia/Kolkata:${addMinutes(kept[0], h, 0, (run.length - 1) * 60 + 50)}`,
            `SUMMARY:${esc(summary(sel.courseCode, title))}`,
            ...(desc.length ? [`DESCRIPTION:${esc(desc.join("\n"))}`] : []),
            ...(o.showRoom && s.room ? [`LOCATION:${esc(s.room)}`] : []),
            `RRULE:FREQ=WEEKLY;UNTIL=${until};BYDAY=${BYDAY[wd]}`,
            ...(skipped.length ? [`EXDATE;TZID=Asia/Kolkata:${skipped.map((d) => local(d, h, 0)).join(",")}`] : []),
            "BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${esc(`${sel.courseCode} starts in 10 minutes`)}`,
            "TRIGGER:-PT10M", "END:VALARM", "END:VEVENT",
          );
        }
      }
    }
  }

  // Exams, once per course. The room arrives with seating, mid-semester; the
  // feed picks it up on its next refresh.
  const seen = new Set();
  for (const sel of o.showExamDates ? p.selections || [] : []) {
    if (seen.has(sel.courseCode)) continue;
    seen.add(sel.courseCode);
    const c = p.courses[sel.courseCode] || {};
    const seat = p.seats?.[sel.courseCode];
    for (const [exam, kind, tag, mins] of [
      [c.midSemExam, "Mid-Sem Exam", "midsem", 90],
      [c.endSemExam, "Comprehensive Exam", "endsem", 180],
    ]) {
      if (!exam) continue;
      const slot = String(exam.timeSlot || "").replace("TimeSlot.", "");
      const start = (EXAM_START[p.campus] || EXAM_START.pilani)[slot];
      if (!start) continue;
      const room = seat && ymd(seat.examDate) === ymd(exam.date) ? seat.roomNo : null;
      const desc = [
        o.showCourseTitle && c.title,
        room ? `Room: ${room}` : "Seat/room is announced mid-semester.",
      ].filter(Boolean);
      lines.push(
        "BEGIN:VEVENT",
        `UID:${uid(`${sel.courseCode}-${tag}`)}`,
        `DTSTAMP:${stamp}`,
        `DTSTART;TZID=Asia/Kolkata:${local(exam.date, start[0], start[1])}`,
        `DTEND;TZID=Asia/Kolkata:${addMinutes(exam.date, start[0], start[1], mins)}`,
        `SUMMARY:${esc(o.showCourseCode ? `${sel.courseCode} — ${kind}` : kind)}`,
        `DESCRIPTION:${esc(desc.join("\n"))}`,
        ...(room ? [`LOCATION:${esc(room)}`] : []),
        "BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${esc(`${kind} tomorrow — ${sel.courseCode}`)}`,
        "TRIGGER:-P1D", "END:VALARM",
        "BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${esc(`${kind} in 90 minutes — ${sel.courseCode}`)}`,
        "TRIGGER:-PT1H30M", "END:VALARM", "END:VEVENT",
      );
    }
  }

  // Academic-calendar reminders: deadlines and exam windows, all-day.
  // Holidays show up as the missing classes instead.
  events.forEach((ev, i) => {
    if (!ev.label || !["deadline", "exam"].includes(ev.category)) return;
    const deadline = ev.category === "deadline";
    lines.push(
      "BEGIN:VEVENT",
      `UID:${uid(`cal-${compact(ev.date)}-${i}`)}`,
      `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${compact(ev.date)}`,
      `DTEND;VALUE=DATE:${compact(iso(addDays(toDate(ev.endDate || ev.date), 1)))}`,
      `SUMMARY:${esc(ev.label)}`,
      `DESCRIPTION:${esc("BITS academic calendar")}`,
      "TRANSP:TRANSPARENT",
      "BEGIN:VALARM", "ACTION:DISPLAY",
      `DESCRIPTION:${esc(`${ev.label} — ${deadline ? "in 3 days" : "tomorrow"}`)}`,
      `TRIGGER:${deadline ? "-P3D" : "-P1D"}`, "END:VALARM", "END:VEVENT",
    );
  });

  lines.push("END:VCALENDAR");
  return lines.map(fold).join("\r\n") + "\r\n";
}

// The seating sheet writes combined exams as "CS F407-CS U407" or
// "ECE-EEE F211"; this returns each course code inside (mirrors
// examCourseCodes in lib/utils/course_code.dart).
function examCourseCodes(code) {
  const parts = code.toUpperCase().split(/[-/]/)
    .map((x) => x.match(/^\s*([A-Z]+(?=\s|$))?\s*([A-Z]?\d{3}[A-Z]?)?\s*$/));
  if (parts.some((m) => !m)) return [code.trim()];
  return parts.map((m, i) => {
    const prefix = m[1] || parts.slice(i + 1).concat(parts.slice(0, i).reverse()).map((x) => x[1]).find(Boolean);
    const num = m[2] || parts.slice(i + 1).map((x) => x[2]).find(Boolean) || parts.slice(0, i).reverse().map((x) => x[2]).find(Boolean);
    return prefix && num ? `${prefix} ${num}` : code.trim();
  });
}

/** The room for [studentId] in a seating doc's `rooms`, by lexicographic ID range. */
function roomFor(rooms, studentId) {
  const id = String(studentId || "").toUpperCase().trim();
  for (const r of rooms || []) {
    const from = String(r.idFrom || "").toUpperCase().trim();
    const to = String(r.idTo || "").toUpperCase().trim();
    if (!from || !to || (id >= from && id <= to)) return r.roomNo;
  }
  return null;
}

module.exports = { buildIcs, noClassDates, classWindow, examCourseCodes, roomFor };
