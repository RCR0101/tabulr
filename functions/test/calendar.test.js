const { test } = require("node:test");
const assert = require("node:assert/strict");

const Module = require("node:module");
const originalResolve = Module._resolveFilename;
const STUB = require.resolve("./helpers/stub-firebase-admin.js");
Module._resolveFilename = function (request, ...args) {
  if (request === "firebase-admin") return STUB;
  return originalResolve.call(this, request, ...args);
};
const { parseSeatingDate, liveSections, docIdFor } = require("../calendar.js")._test;
Module._resolveFilename = originalResolve;

test("seating sheet dates parse to calendar dates", () => {
  assert.equal(parseSeatingDate("09 October 26 - 09:30 AM"), "2026-10-09");
  assert.equal(parseSeatingDate("7 May 2027"), "2027-05-07");
  assert.equal(parseSeatingDate("TBA"), null);
});

test("the feed shows a section as it is now, and keeps one that vanished", () => {
  const saved = [
    { courseCode: "CS F211", sectionId: "L1", section: { sectionId: "L1", room: "F102" } },
    { courseCode: "CS F211", sectionId: "L9", section: { sectionId: "L9", room: "G101" } },
  ];
  const courses = { "CS F211": { sections: [{ sectionId: "L1", room: "D311" }] } };
  const out = liveSections(saved, courses);
  assert.equal(out[0].section.room, "D311");
  assert.equal(out[1].section.room, "G101");
});

test("course doc ids match the uploader's", () => {
  assert.equal(docIdFor("CS F211"), "CS_F211");
  assert.equal(docIdFor("BITS F101-2"), "BITS_F101-2");
});
