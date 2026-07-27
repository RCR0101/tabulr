/**
 * Emits crawlable HTML pages into the built web app.
 *
 *   flutter build web
 *   node scripts/generate-static-pages.js          # writes into build/web
 *   node scripts/generate-static-pages.js --sample /tmp/preview   # no Firestore
 *   firebase deploy --only hosting
 *
 * Runs automatically in .github/workflows/deploy-{preview,production}.yml,
 * between the build and the deploy. A manual run is only needed to preview.
 * No dependencies and no credentials: it reads the public Firestore REST API
 * with the web API key, exactly as a signed-out visitor does.
 *
 * Why this exists: CanvasKit paints the entire UI into a <canvas>, so a crawler
 * that executes the app finds no text at all. Meta tags describe the home page
 * and nothing else. Serving separate HTML is the only way any of the catalogue
 * gets indexed — every other "Flutter SEO" technique is decoration on an empty
 * DOM.
 *
 * Firebase Hosting matches static files before it applies rewrites, so these
 * land in front of the `** -> /index.html` catch-all in firebase.json without
 * touching it. A student clicking through from a search result gets the page,
 * then the "Open in Tabulr" link into the app itself.
 *
 * Pages are deliberately thin on purpose-built content and carry only what
 * stays true: what the course is, its units, and its prerequisites. Section
 * tables (instructor, room, timings) were cut — nobody searches for a room
 * number, all of it changes every semester, and a page Google has indexed
 * would go on answering with last semester's lecturer. Exam dates survive as
 * one line each because "MATH F211 compre date" is a query people run.
 *
 * ponytail: only courses with something real to say get a page — offered this
 * semester, or with prerequisites recorded. A few thousand pages reading
 * "CS F211, 4 units" and nothing else is thin content, which costs ranking
 * rather than earning it.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ORIGIN = 'https://tabulr.net';
const CAMPUSES = { hyderabad: 'BITS Hyderabad', pilani: 'BITS Pilani', goa: 'BITS Goa' };

const plural = (n, word) => (n === 1 ? word : `${word}s`);

const esc = (s) =>
  String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** `CS F211` -> `cs-f211`. Lowercase and hyphenated because it is a URL. */
const slugify = (code) => code.trim().toLowerCase().replace(/\s+/g, '-');

/** `TimeSlot.FN` -> `FN`. */
const slotName = (raw) => String(raw ?? '').split('.').pop();

const formatDate = (iso) => {
  const d = new Date(String(iso).split('T')[0]);
  return Number.isNaN(d.getTime())
    ? null
    : d.toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
};

// ── Firestore, over the public REST API ──────────────────────────────────────
//
// No Admin SDK and no service account, because none of this data is private:
// firestore.rules grants `allow read: if true` on `campuses/{campus}/**` and
// `reference/prerequisites/**`, which is how the app itself reads them before
// anyone signs in.
//
// The Admin SDK would have needed a service account, and — because it bypasses
// security rules entirely and is authorised by Cloud IAM instead — a
// roles/datastore.viewer grant to read data that is already world-readable.
// Going through the REST API keeps the same rules the app plays by, needs no
// secret in CI, and cannot write anything even if this script has a bug.

const PROJECT = 'timetable-maker-3c8e0';
const REST = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

/**
 * The web API key, lifted out of lib/firebase_options.dart.
 *
 * That file is gitignored and written from a secret by the deploy workflow, so
 * reading it is how this script gets the key without introducing a second copy
 * or a new secret — in CI it is already on disk by the time this runs, and
 * locally every developer has it. Firebase web API keys are public identifiers
 * rather than credentials (this one ships in every client bundle); the
 * indirection is only to respect that this repo keeps the file out of git.
 */
function apiKey() {
  const optionsPath = path.join(__dirname, '..', 'lib', 'firebase_options.dart');
  const match = /static const FirebaseOptions web = FirebaseOptions\(\s*apiKey: '([^']+)'/
    .exec(fs.readFileSync(optionsPath, 'utf8'));
  if (!match) throw new Error(`Could not read the web apiKey from ${optionsPath}`);
  return match[1];
}

/** Firestore's typed JSON (`{stringValue: "x"}`) back into plain values. */
function decode(value) {
  if ('nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return decodeFields(value.mapValue.fields);
  // timestampValue, stringValue, referenceValue and the rest are all strings
  // here, and every consumer below treats them as such.
  return Object.values(value)[0];
}

const decodeFields = (fields = {}) =>
  Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decode(v)]));

async function getJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText} for ${url.replace(/key=[^&]+/, 'key=…')}`);
  }
  return response.json();
}

/** One document, or null when it does not exist. */
async function getDoc(key, docPath) {
  const response = await fetch(`${REST}/${docPath}?key=${key}`);
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${response.status} reading ${docPath}`);
  return decodeFields((await response.json()).fields);
}

/**
 * Every document in a collection, following pageToken to the end.
 *
 * 300 is the server's ceiling per page; the timetable collections run to ~2.8k
 * documents each, so this really does page.
 */
async function listDocs(key, collectionPath) {
  const docs = [];
  let pageToken = '';
  do {
    const url = `${REST}/${collectionPath}?key=${key}&pageSize=300${pageToken ? `&pageToken=${pageToken}` : ''}`;
    const body = await getJson(url);
    for (const doc of body.documents ?? []) {
      docs.push({ id: doc.name.split('/').pop(), ...decodeFields(doc.fields) });
    }
    pageToken = body.nextPageToken ?? '';
  } while (pageToken);
  return docs;
}

/**
 * Titles and credits for one campus.
 *
 * Prefers the pre-bundled single document the app reads (1 read instead of
 * ~2.8k), falling back to the per-document collection exactly as
 * CoursesMasterService does — the bundle is an optimisation, never a
 * requirement.
 */
async function fetchCatalogue(key, campusId) {
  const bundle = await getDoc(key, `campuses/${campusId}/catalog/courses_master`);
  const entries = bundle?.entriesJson
    ? JSON.parse(bundle.entriesJson)
    : await listDocs(key, `campuses/${campusId}/courses_master`);
  return new Map(entries.map((e) => [e.course_code, e]));
}

/** This semester's offerings for one campus: section counts and exam dates. */
async function fetchOfferings(key, campusId) {
  const docs = await listDocs(key, `campuses/${campusId}/timetable`);
  return docs.map((doc) => ({ ...doc, courseCode: doc.id.replace(/_/g, ' ') }));
}

async function fetchPrerequisites(key) {
  const docs = await listDocs(key, 'reference/prerequisites/courses');
  return new Map(
    docs.filter((d) => (d.groups?.length ?? 0) > 0).map((d) => [d.course_code, d.groups]),
  );
}

// ── Page assembly ────────────────────────────────────────────────────────────

/**
 * Merges every campus's view of one course into what a page needs.
 *
 * Keyed by course code rather than by (code, campus): `CS F211` is one course
 * that three campuses happen to offer, and three near-identical pages competing
 * for the same query is worse for all three than one page that answers it.
 */
function collate({ catalogues, offerings, prereqs }) {
  const courses = new Map();
  const ensure = (code) => {
    if (!courses.has(code)) {
      courses.set(code, { code, title: '', credits: 0, type: '', campuses: [] });
    }
    return courses.get(code);
  };

  for (const catalogue of Object.values(catalogues)) {
    for (const entry of catalogue.values()) {
      const course = ensure(entry.course_code);
      // First campus to name it wins; they agree in practice, and an empty
      // title from one campus must not erase a good one from another.
      course.title ||= entry.title ?? '';
      course.credits ||= Number(entry.credits) || 0;
      course.type ||= entry.type ?? '';
    }
  }

  for (const [campusId, list] of Object.entries(offerings)) {
    for (const offering of list) {
      const course = ensure(offering.courseCode);
      // Only the count survives. Instructors, rooms and per-section schedules
      // were the bulk of these pages and the worst part of them: nobody
      // searches for a room number, and every one of those fields changes each
      // semester, so an indexed page would keep answering with last semester's
      // lecturer. The app has all of it, live and correct.
      course.campuses.push({
        id: campusId,
        name: CAMPUSES[campusId],
        sectionCount: (offering.sections ?? []).length,
        midSem: offering.mid_sem_exam ?? offering.midSemExam ?? null,
        endSem: offering.end_sem_exam ?? offering.endSemExam ?? null,
      });
    }
  }

  return courses;
}

const examText = (exam) => {
  if (!exam) return null;
  const date = formatDate(exam.date);
  if (!date) return null;
  const slot = slotName(exam.timeSlot);
  return slot ? `${date} (${slot})` : date;
};

/**
 * [cssHref] is relative only for `--sample`, which is opened over file:// where
 * an absolute path resolves against the filesystem root and the page renders
 * with no styling at all. Served from the site, absolute is correct.
 */
function page({ title, description, canonical, body, cssHref = '/static-pages.css' }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${esc(canonical)}">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="stylesheet" href="${esc(cssHref)}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Tabulr">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(canonical)}">
<meta property="og:image" content="${ORIGIN}/og-image.png">
<meta name="twitter:card" content="summary_large_image">
</head>
<body>
<header><a class="brand" href="/">Tabulr</a><a class="cta" href="/timetables">Open in Tabulr</a></header>
<main>
${body}
</main>
<footer>
<p><a href="/courses/">All courses</a> · <a href="/exam-seating">Exam seating</a> · <a href="/cgpa">CGPA calculator</a> · <a href="/minors">Minors</a> · <a href="/faq">Academic FAQ</a></p>
<p class="fine">Tabulr is a free, open-source student project. Course data comes from the official BITS course booklet and may change; always confirm against ERP.</p>
</footer>
</body>
</html>
`;
}

function coursePage(course, cssHref) {
  const offered = course.campuses.filter((c) => c.sectionCount > 0);
  const campusNames = offered.map((c) => c.name);
  const heading = `${course.code}${course.title ? ` ${course.title}` : ''}`;

  const description = [
    `${course.code}${course.title ? ` (${course.title})` : ''} at BITS Pilani`,
    course.credits ? `${course.credits} units` : null,
    campusNames.length ? `offered at ${campusNames.join(', ')}` : null,
  ].filter(Boolean).join(' · ');

  const facts = [
    course.credits ? `<dt>Units</dt><dd>${esc(course.credits)}</dd>` : '',
    course.type ? `<dt>Type</dt><dd>${esc(course.type)}</dd>` : '',
    campusNames.length ? `<dt>Offered at</dt><dd>${esc(campusNames.join(', '))}</dd>` : '',
  ].join('');

  // One line per campus. Exam dates earn their place — "MATH F211 compre date"
  // is a query people actually run — but they are also the only thing on this
  // page that goes stale, hence the caveat under them.
  const thisSemester = offered.length
    ? `<section><h2>This semester</h2>
<ul class="semester">
${offered.map((campus) => {
    const exams = [
      examText(campus.midSem) ? `Midsem ${examText(campus.midSem)}` : null,
      examText(campus.endSem) ? `Compre ${examText(campus.endSem)}` : null,
    ].filter(Boolean);
    return `<li><strong>${esc(campus.name)}</strong> <span class="tag">${campus.sectionCount} ${plural(campus.sectionCount, 'section')}</span>${exams.length ? `<br><span class="exams">${esc(exams.join(' · '))}</span>` : ''}</li>`;
  }).join('\n')}
</ul>
<p class="fine">Section timings, instructors and rooms change through the semester — <a href="/timetables">open Tabulr</a> for the live list.</p>
</section>`
    : '';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Course',
    name: heading,
    courseCode: course.code,
    description,
    url: `${ORIGIN}/courses/${slugify(course.code)}/`,
    provider: { '@type': 'CollegeOrUniversity', name: 'Birla Institute of Technology and Science, Pilani' },
  };

  return page({
    title: `${heading} — BITS Pilani | Tabulr`,
    description,
    canonical: `${ORIGIN}/courses/${slugify(course.code)}/`,
    cssHref,
    body: `<script type="application/ld+json">${JSON.stringify(jsonLd)}</script>
<h1>${esc(heading)}</h1>
${facts ? `<dl class="facts">${facts}</dl>` : ''}
${thisSemester}
<section class="cta-block">
<h2>Plan ${esc(course.code)} into your timetable</h2>
<p>Tabulr builds a clash-free timetable around every section of ${esc(course.code)} and exports the whole semester to your calendar.</p>
<p><a class="cta" href="/timetables">Open Tabulr</a></p>
</section>`,
  });
}

function indexPage(courses, cssHref) {
  const byDept = new Map();
  for (const course of courses) {
    const dept = course.code.split(' ')[0];
    if (!byDept.has(dept)) byDept.set(dept, []);
    byDept.get(dept).push(course);
  }

  const body = [...byDept.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([dept, list]) => `<section><h2 id="${esc(dept.toLowerCase())}">${esc(dept)}</h2>
<ul class="courses">
${list.sort((a, b) => a.code.localeCompare(b.code))
      .map((c) => `<li><a href="/courses/${slugify(c.code)}/"><strong>${esc(c.code)}</strong> ${esc(c.title)}</a></li>`)
      .join('\n')}
</ul></section>`)
    .join('\n');

  return page({
    title: 'All BITS Pilani courses — units, prerequisites and exam dates | Tabulr',
    description: `Every course in the BITS course booklet: ${courses.length} ${plural(courses.length, 'course')} across Pilani, Goa and Hyderabad, with units, prerequisites and exam dates.`,
    canonical: `${ORIGIN}/courses/`,
    cssHref,
    body: `<h1>BITS Pilani course catalogue</h1>
<p>${courses.length} ${plural(courses.length, 'course')} with units, prerequisites and exam dates, across the Pilani, Goa and Hyderabad campuses.</p>
${body}`,
  });
}

function landingPage({ title, description, heading, body, canonical, ctaHref, ctaLabel, cssHref }) {
  return page({
    title,
    description,
    canonical,
    cssHref,
    body: `<h1>${esc(heading)}</h1>
<p class="lead">${esc(description)}</p>
${body}
<section class="cta-block">
<h2>${esc(ctaLabel)}</h2>
<p><a class="cta" href="${esc(ctaHref)}">Open Tabulr</a></p>
</section>`,
  });
}

const STYLESHEET = `:root{color-scheme:light dark;--bg:#fff;--fg:#1c2128;--muted:#57606a;--line:#d0d7de;--accent:#1B4DE4;--card:#f6f8fa}
@media(prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#8b949e;--line:#30363d;--accent:#58A6FF;--card:#161b22}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif}
header{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:16px 24px;border-bottom:1px solid var(--line)}
.brand{font-weight:700;font-size:20px;color:var(--fg);text-decoration:none}
.cta{display:inline-block;background:var(--accent);color:#fff;padding:8px 16px;border-radius:8px;text-decoration:none;font-weight:600}
main{max-width:860px;margin:0 auto;padding:32px 24px}
h1{font-size:1.9rem;line-height:1.25;margin:0 0 8px}
h2{font-size:1.2rem;margin:32px 0 12px;padding-top:16px;border-top:1px solid var(--line)}
a{color:var(--accent)}
dl.facts{display:grid;grid-template-columns:auto 1fr;gap:4px 16px;margin:16px 0;padding:16px;background:var(--card);border-radius:8px}
dl.facts dt{color:var(--muted)}
dl.facts dd{margin:0}
ul.prereqs{list-style:none;padding:0}
ul.prereqs li,ul.semester li{padding:10px 12px;background:var(--card);border-radius:8px;margin-bottom:8px}
ul.semester{list-style:none;padding:0}
.exams{color:var(--muted);font-size:14px}
.tag{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em;margin-left:8px}
ul.courses{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:4px}
ul.courses a{text-decoration:none;display:block;padding:6px 8px;border-radius:6px}
ul.courses a:hover{background:var(--card)}
.cta-block{background:var(--card);padding:20px;border-radius:12px;margin-top:32px;border-top:0}
.cta-block h2{border-top:0;padding-top:0;margin-top:0}
footer{max-width:860px;margin:0 auto;padding:24px;border-top:1px solid var(--line);color:var(--muted);font-size:14px}
.fine{font-size:13px}
img{max-width:100%}
`;

/**
 * Landing pages must NOT be named after an app route.
 *
 * Hosting matches a real file before the `** -> /index.html` rewrite, so a
 * directory called `timetables/` takes `/timetables` away from the app: the
 * tab becomes unreachable by URL and the CTA below redirects to itself. Hence
 * `timetable-maker` for the page and `/timetables` for the link out of it.
 *
 * Signed-in-only screens have no page here — `/electives` and `/prerequisites`
 * among them. Both would be strong landing pages, and their Firestore data is
 * world-readable, but the app currently shows a crawler (and a first-time
 * visitor) the sign-in wall, and an indexed URL nobody can open is worse than
 * no URL. Opening those two to guests is the change that would earn them a
 * place here.
 */
const LANDING_PAGES = [
  {
    path: 'timetable-maker',
    title: 'Timetable maker for BITS Pilani | Tabulr',
    description: 'Build clash-free timetables from the official course booklet, compare schedules and export your semester.',
    heading: 'Timetable builder',
    body: '<p>Tabulr helps you assemble a semester timetable from live course offerings, then compare and save the result without clashes.</p><ul><li>Pick courses from the current catalogue</li><li>Compare multiple timetable options</li><li>Export to your calendar</li></ul>',
    canonical: `${ORIGIN}/timetable-maker/`,
    ctaHref: '/timetables',
    ctaLabel: 'Start building a timetable',
  },
  {
    path: 'cgpa-calculator',
    title: 'CGPA calculator for BITS Pilani | Tabulr',
    description: 'Calculate, plan and project your CGPA with semester-by-semester grade tracking.',
    heading: 'CGPA calculator',
    body: '<p>Use Tabulr to track your semester grades, project future CGPA outcomes and import marks from a performance sheet when you have one.</p><ul><li>Calculate CGPA and SGPA</li><li>Project future grades</li><li>Import past results from PDF</li></ul>',
    canonical: `${ORIGIN}/cgpa-calculator/`,
    ctaHref: '/cgpa',
    ctaLabel: 'Open the CGPA calculator',
  },
  {
    path: 'exam-seating-lookup',
    title: 'Exam seating lookup for BITS Pilani | Tabulr',
    description: 'Find your exam seat and room by student ID, or import courses from a timetable.',
    heading: 'Exam seating',
    body: '<p>Tabulr looks up official exam seating details, helps you import the right courses and keeps the room and seat lookup in one place.</p><ul><li>Search by ID number</li><li>Import courses from a timetable</li><li>See exam room and seating details</li></ul>',
    canonical: `${ORIGIN}/exam-seating-lookup/`,
    ctaHref: '/exam-seating',
    ctaLabel: 'Look up exam seating',
  },
  {
    path: 'minor-programmes',
    title: 'BITS Pilani minor programmes | Tabulr',
    description: 'Browse minor programmes and track progress toward each one.',
    heading: 'Minor programmes',
    body: '<p>Browse the available minors, search by course code and keep an eye on progress when you have a CGPA record loaded.</p><ul><li>Search minors and course codes</li><li>Track cleared courses</li><li>See how far along you are</li></ul>',
    canonical: `${ORIGIN}/minor-programmes/`,
    ctaHref: '/minors',
    ctaLabel: 'Browse minors',
  },
  {
    path: 'academic-faq',
    title: 'BITS academic FAQ | Tabulr',
    description: 'Straight answers on grades, attendance, registration and other academic rules.',
    heading: 'Academic FAQ',
    body: '<p>Tabulr keeps the most commonly searched academic rules in one searchable place, with answers distilled from the regulations and bulletin.</p><ul><li>Search by keyword</li><li>Filter by topic</li><li>Read concise answers fast</li></ul>',
    canonical: `${ORIGIN}/academic-faq/`,
    ctaHref: '/faq',
    ctaLabel: 'Read the academic FAQ',
  },
];

/**
 * Only URLs that serve their own HTML. Every in-app route returns the same
 * index.html, so listing `/timetables`, `/cgpa` and friends would offer the
 * crawler five copies of one shell — the landing pages are what they were
 * meant to point at.
 */
const PUBLIC_ROUTES = ['/', ...LANDING_PAGES.map((l) => `/${l.path}/`), '/courses/'];

const sitemap = (courses) => `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${PUBLIC_ROUTES.map((p) => `  <url><loc>${ORIGIN}${p}</loc><priority>${p === '/' ? '1.0' : '0.8'}</priority></url>`).join('\n')}
${courses.map((c) => `  <url><loc>${ORIGIN}/courses/${slugify(c.code)}/</loc><priority>0.5</priority></url>`).join('\n')}
</urlset>
`;

// ── Entry point ──────────────────────────────────────────────────────────────

/**
 * Renders the templates against a fixture, with no Firestore and no build
 * directory: `node generate-static-pages.js --sample /tmp/preview`.
 *
 * The point is to be able to look at a page before pushing a few thousand of
 * them to a live domain. It also fails loudly if a template stops producing
 * the things a crawler needs — a title, a canonical link and some readable
 * text — which is the one thing about this script that silently not working
 * would be invisible.
 */
function writeSample(outDir) {
  const course = {
    code: 'CS F211',
    title: 'Data Structures and Algorithms',
    credits: 4,
    type: 'Normal',
    groups: [
      { options: [{ course_code: 'CS F111', type: 'pre' }] },
      { options: [{ course_code: 'MATH F113', type: 'pre' }, { course_code: 'MATH F213', type: 'pre' }] },
    ],
    campuses: [
      {
        id: 'hyderabad',
        name: CAMPUSES.hyderabad,
        midSem: { date: '2026-03-05T00:00:00.000', timeSlot: 'TimeSlot.FN' },
        endSem: { date: '2026-05-11T00:00:00.000', timeSlot: 'TimeSlot.AN' },
        sectionCount: 3,
      },
      // Offered without a scheduled compre, and with a single section — both
      // shapes the campus line has to render without a dangling separator.
      { id: 'goa', name: CAMPUSES.goa, midSem: null, endSem: null, sectionCount: 1 },
    ],
  };

  fs.mkdirSync(path.join(outDir, 'courses', slugify(course.code)), { recursive: true });
  fs.writeFileSync(path.join(outDir, 'static-pages.css'), STYLESHEET);
  const html = coursePage(course, '../../static-pages.css');
  fs.writeFileSync(path.join(outDir, 'courses', slugify(course.code), 'index.html'), html);
  fs.writeFileSync(path.join(outDir, 'courses', 'index.html'), indexPage([course], '../static-pages.css'));
  fs.writeFileSync(path.join(outDir, 'sitemap.xml'), sitemap([course]));

  for (const needle of [
    '<title>CS F211 Data Structures and Algorithms — BITS Pilani | Tabulr</title>',
    '3 sections',
    `<link rel="canonical" href="${ORIGIN}/courses/cs-f211/">`,
    '<h1>CS F211 Data Structures and Algorithms</h1>',
    'Midsem 5 March 2026 (FN) · Compre 11 May 2026 (AN)',
    '<strong>BITS Goa</strong> <span class="tag">1 section</span>', // singular, no exam line
    '"@type":"Course"',
  ]) {
    if (!html.includes(needle)) throw new Error(`sample page is missing: ${needle}`);
  }
  if (/Prerequisites for CS F211/.test(html)) throw new Error('sample page still renders prerequisites');
  // The whole point of the shrink: no per-section table survives. Matches
  // markup only — the page still says the word "instructors" in the sentence
  // explaining why they are not listed here.
  if (/<table[\s>]/.test(html)) throw new Error('sample page still renders a section table');
  // A landing page named after an app route steals that route: Hosting serves
  // the directory and never reaches the SPA rewrite. This shipped once, taking
  // out five tabs at the same time, and is invisible until someone opens the
  // deployed URL — so read the slugs back out of the app and refuse to build.
  const destinations = fs.readFileSync(
    path.join(__dirname, '..', 'lib', 'widgets', 'app_destinations.dart'), 'utf8');
  const tabSlugs = new Set([...destinations.matchAll(/slug: '([^']+)'/g)].map((m) => m[1]));
  for (const landing of LANDING_PAGES) {
    if (tabSlugs.has(landing.path)) {
      throw new Error(
        `landing page "${landing.path}" collides with the app tab /${landing.path} — ` +
        'rename the page (its ctaHref is what should point at the app)');
    }
    const dir = path.join(outDir, landing.path);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'index.html'),
      landingPage({ ...landing, cssHref: '../static-pages.css' }));
  }

  console.log(`sample ok — open ${path.join(outDir, 'courses', slugify(course.code), 'index.html')}`);
}

async function main() {
  const args = process.argv.slice(2);
  const outIndex = args.indexOf('--out');
  const sampleIndex = args.indexOf('--sample');
  const outDir = sampleIndex >= 0
    ? args[sampleIndex + 1] ?? path.join(__dirname, 'sample-pages')
    : outIndex >= 0 ? args[outIndex + 1] : path.join(__dirname, '..', 'build', 'web');

  if (sampleIndex >= 0) {
    fs.mkdirSync(outDir, { recursive: true });
    return writeSample(outDir);
  }

  if (!fs.existsSync(outDir)) {
    throw new Error(`${outDir} does not exist — run \`flutter build web\` first, or pass --out <dir>.`);
  }

  const key = apiKey();
  const catalogues = {};
  const offerings = {};
  for (const campusId of Object.keys(CAMPUSES)) {
    catalogues[campusId] = await fetchCatalogue(key, campusId);
    offerings[campusId] = await fetchOfferings(key, campusId);
    console.log(`${campusId}: ${catalogues[campusId].size} catalogue entries, ${offerings[campusId].length} offered`);
  }
  const prereqs = await fetchPrerequisites(key);
  console.log(`prerequisites: ${prereqs.size} courses`);

  const collated = collate({ catalogues, offerings, prereqs });
  const worthAPage = [...collated.values()].filter(
    (c) => c.campuses.some((x) => x.sectionCount > 0),
  );
  console.log(`\n${collated.size} distinct courses, ${worthAPage.length} with enough content to publish`);

  fs.writeFileSync(path.join(outDir, 'static-pages.css'), STYLESHEET);
  const coursesDir = path.join(outDir, 'courses');
  fs.mkdirSync(coursesDir, { recursive: true });
  fs.writeFileSync(path.join(coursesDir, 'index.html'), indexPage(worthAPage));

  for (const landing of LANDING_PAGES) {
    const dir = path.join(outDir, landing.path);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, 'index.html'),
      landingPage({
        ...landing,
        cssHref: '../static-pages.css',
      }),
    );
  }

  for (const course of worthAPage) {
    const dir = path.join(coursesDir, slugify(course.code));
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'index.html'), coursePage(course));
  }

  fs.writeFileSync(path.join(outDir, 'sitemap.xml'), sitemap(worthAPage));
  console.log(`Wrote ${worthAPage.length + 1} pages + sitemap.xml into ${outDir}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
