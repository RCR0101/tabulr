const { test } = require("node:test");
const assert = require("node:assert/strict");

// admin.js initialises firebase-admin at load time; swap in the stub.
const Module = require("node:module");
const originalResolve = Module._resolveFilename;
const STUB = require.resolve("./helpers/stub-firebase-admin.js");
Module._resolveFilename = function (request, ...args) {
  if (request === "firebase-admin") return STUB;
  return originalResolve.call(this, request, ...args);
};
const { professorFields, matchExisting, sameProfessor } = require("../admin.js")._test;
Module._resolveFilename = originalResolve;

test("an admin-edited chamber survives a roster without one", () => {
  const out = professorFields({ name: "Kavi Devraj " }, { chamber: "D-207", email: "k@x" });
  assert.equal(out.chamber, "D-207");
  assert.equal(out.chamberSearch, "d-207");
  assert.equal(out.email, "k@x");
  assert.equal(out.name, "Kavi Devraj");
});

test("an admin-edited chamber beats the roster's", () => {
  assert.equal(professorFields({ name: "A", chamber: "J-101" }, { chamber: "D-207" }).chamber, "D-207");
});

test("the roster fills a gap, including a placeholder", () => {
  assert.equal(professorFields({ name: "A", chamber: "J-101" }, { chamber: "Unavailable" }).chamber, "J-101");
  assert.equal(professorFields({ name: "A", chamber: "J-101" }).chamber, "J-101");
});

test("no chamber anywhere is 'Unavailable', not a skipped professor", () => {
  const out = professorFields({ name: "A", email: "a@x", phone: "040" });
  assert.equal(out.chamber, "Unavailable");
  assert.equal(out.email, "a@x");
  assert.equal(out.contact, "040");
});

// Real pairs from the 2026-10 Hyderabad roster vs the live professor docs.
test("a roster entry finds its existing doc by name, email, then spelling", () => {
  const live = [
    { name: "Kavi Devraj", chamber: "D-207" },
    { name: "Mahipal Reddy Benjaram", email: "bmreddy@hyderabad.bits-pilani.ac.in", chamber: "A-1" },
    { name: "Vuppuluri Amol", chamber: "B-2" },
  ];
  const m = matchExisting([
    { name: "Kavi Devraj" },
    { name: "B.M. Reddy", email: "BMReddy@hyderabad.bits-pilani.ac.in" },
    { name: "Amol Vuppuluri" },
    { name: "Manas Pradhan" },
  ], live);
  assert.deepEqual(m.map((e) => e && e.chamber), ["D-207", "A-1", "B-2", null]);
});

test("different emails are different people, however close the names", () => {
  const m = matchExisting(
    [{ name: "Amit Kumar Panda", email: "panda@x" }],
    [{ name: "Amit Kumar Panda ", email: "other@x" }].map((e) => ({ ...e, name: "Amit Kumar Pande" })),
  );
  assert.deepEqual(m, [null]);
});

test("an existing doc is claimed by one roster entry only", () => {
  const live = [{ name: "Jayesh A K" }];
  const m = matchExisting([{ name: "Jayesh A K" }, { name: "Jayesh A K" }], live);
  assert.equal(m[0], live[0]);
  assert.equal(m[1], null);
});

test("an unchanged professor is not rewritten, whatever order Firestore returns keys in", () => {
  const written = { name: "A", chamber: "D-1", schedule: [{ course_code: "CS F211", section_id: "L1", room: "F102", days: ["M"], hours: [2] }] };
  const readBack = { chamber: "D-1", name: "A", schedule: [{ days: ["M"], hours: [2], room: "F102", section_id: "L1", course_code: "CS F211" }] };
  assert.equal(sameProfessor(readBack, written), true);
  assert.equal(sameProfessor(readBack, { ...written, schedule: [{ ...written.schedule[0], room: "F103" }] }), false);
});

test("a professor keeps the name already on file; the roster names only new people", () => {
  assert.equal(professorFields({ name: "Amol Vuppuluri" }, { name: "Vuppuluri Amol" }).name, "Vuppuluri Amol");
  assert.equal(professorFields({ name: " Manas Pradhan " }).name, "Manas Pradhan");
});
