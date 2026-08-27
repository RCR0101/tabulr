/**
 * Input-validation tests for the callable functions.
 *
 * These callables run on the Admin SDK, so firestore.rules does not apply to
 * them — the bounds the rules enforce on direct client writes have to be
 * re-stated in the handlers. Several of these fields are copied onto the
 * announcement document that every reader of a course's feed downloads, so an
 * unbounded one is a ~1MB write anybody can trigger.
 *
 *   node --test functions/test/
 */
const { test } = require("node:test");
const assert = require("node:assert/strict");

// The validators are internal to index.js, which calls admin.initializeApp() at
// load time. Re-declaring them here would let the copies drift, so instead the
// module is loaded with a stubbed firebase-admin.
const Module = require("node:module");
const originalResolve = Module._resolveFilename;
const STUB = require.resolve("./helpers/stub-firebase-admin.js");
Module._resolveFilename = function (request, ...args) {
  if (request === "firebase-admin") return STUB;
  return originalResolve.call(this, request, ...args);
};
const fns = require("../index.js");
Module._resolveFilename = originalResolve;

const { requireString, optionalString, requireAnnouncementId } = fns._test;

test("requireString accepts a value inside its bound", () => {
  assert.equal(requireString("hello", "f", 10), "hello");
});

test("requireString trims", () => {
  assert.equal(requireString("  hello  ", "f", 10), "hello");
});

test("requireString rejects non-strings", () => {
  for (const bad of [null, undefined, 42, {}, [], true]) {
    assert.throws(() => requireString(bad, "f", 10), /must be a string/);
  }
});

test("requireString rejects empty and whitespace-only", () => {
  assert.throws(() => requireString("", "f", 10), /must not be empty/);
  assert.throws(() => requireString("   ", "f", 10), /must not be empty/);
});

test("requireString rejects an over-long value", () => {
  assert.throws(() => requireString("x".repeat(11), "f", 10), /at most 10/);
});

test("requireString rejects a 1MB payload — the actual abuse case", () => {
  assert.throws(() => requireString("x".repeat(1_000_000), "reason", 500));
});

test("optionalString passes null and undefined through", () => {
  assert.equal(optionalString(null, "f", 10), null);
  assert.equal(optionalString(undefined, "f", 10), null);
});

test("optionalString still bounds a value that is present", () => {
  assert.equal(optionalString("ok", "f", 10), "ok");
  assert.throws(() => optionalString("x".repeat(11), "f", 10), /at most 10/);
});

test("requireAnnouncementId accepts a Firestore auto-id", () => {
  assert.equal(requireAnnouncementId("Ab3xY9zQ1mNpLk2JhG7f"), "Ab3xY9zQ1mNpLk2JhG7f");
});

test("requireAnnouncementId rejects path traversal into a subcollection", () => {
  // collection("announcements").doc("a/b/c") resolves to a nested document, so
  // an unvalidated id lets a caller steer writes off-target.
  for (const bad of ["a/b/c", "../other", "x/votes/y", "a/b"]) {
    assert.throws(() => requireAnnouncementId(bad), /Invalid announcementId/);
  }
});

test("requireAnnouncementId rejects empty, non-string and over-long ids", () => {
  for (const bad of ["", null, undefined, 42, {}, "x".repeat(65)]) {
    assert.throws(() => requireAnnouncementId(bad), /Invalid announcementId/);
  }
});

function deletionDatabase(announcement) {
  const ref = {
    get: async () => ({
      exists: announcement !== null,
      data: () => announcement,
    }),
  };
  const state = { deleted: false };
  return {
    state,
    collection: () => ({ doc: () => ref }),
    recursiveDelete: async (received) => {
      assert.equal(received, ref);
      state.deleted = true;
    },
  };
}

test("delete announcement rejects a caller who is not the author", async () => {
  const database = deletionDatabase({
    authorUid: "authorH",
    disputeState: "undisputed",
  });

  await assert.rejects(
    () => fns._test.deleteAnnouncementForCaller({
      callerDocId: "otherH",
      announcementId: "announcement-1",
      database,
      addReputation: async () => {},
    }),
    /authored/
  );
  assert.equal(database.state.deleted, false);
});

test("delete announcement recursively removes interaction subcollections", async () => {
  const database = deletionDatabase({
    authorUid: "authorH",
    disputeState: "undisputed",
  });
  const reputationEvents = [];

  const result = await fns._test.deleteAnnouncementForCaller({
    callerDocId: "authorH",
    announcementId: "announcement-1",
    database,
    addReputation: async (event) => reputationEvents.push(event),
  });

  assert.deepEqual(result, { success: true, deleted: true });
  assert.equal(database.state.deleted, true);
  assert.deepEqual(reputationEvents, []);
});

test("deleting a disputed post applies its idempotent penalty first", async () => {
  const database = deletionDatabase({
    authorUid: "authorH",
    disputeState: "disputed",
  });
  const reputationEvents = [];

  await fns._test.deleteAnnouncementForCaller({
    callerDocId: "authorH",
    announcementId: "announcement-1",
    database,
    addReputation: async (event) => reputationEvents.push(event),
  });

  assert.equal(reputationEvents.length, 1);
  assert.equal(reputationEvents[0].type, "post_removed_inaccuracy");
  assert.equal(reputationEvents[0].points, -15);
  assert.equal(database.state.deleted, true);
});
