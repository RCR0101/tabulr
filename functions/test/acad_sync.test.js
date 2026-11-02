const { test } = require("node:test");
const assert = require("node:assert/strict");

const Module = require("node:module");
const originalResolve = Module._resolveFilename;
const STUB = require.resolve("./helpers/stub-firebase-admin.js");
Module._resolveFilename = function (request, ...args) {
  if (request === "firebase-admin") return STUB;
  return originalResolve.call(this, request, ...args);
};
const { dispatchSync } = require("../admin.js")._test;
Module._resolveFilename = originalResolve;

test("approving a drive starts the sync workflow on main", async () => {
  let seen;
  const out = await dispatchSync("tok", async (url, opts) => {
    seen = { url, opts };
    return { status: 204, text: async () => "" };
  });
  assert.deepEqual(out, { started: true });
  assert.match(seen.url, /RCR0101\/tabulr\/actions\/workflows\/acad-drives-sync\.yml\/dispatches$/);
  assert.equal(seen.opts.method, "POST");
  assert.equal(seen.opts.headers.Authorization, "Bearer tok");
  assert.deepEqual(JSON.parse(seen.opts.body), { ref: "main" });
});

test("a refused start says the drive waits for Monday", async () => {
  const out = await dispatchSync("tok", async () => ({ status: 403, text: async () => "Resource not accessible" }));
  assert.equal(out.started, false);
  assert.match(out.reason, /403/);
});

test("no token: nothing is called", async () => {
  const out = await dispatchSync("", async () => { throw new Error("should not call"); });
  assert.equal(out.started, false);
});
