import { test, expect } from '@playwright/test';
import { waitForFirstFrame } from './_helpers';

test('Chromium uses SkWasm rather than the JavaScript fallback', async ({
  page,
  browserName,
}) => {
  test.skip(browserName !== 'chromium', 'SkWasm is currently enabled for Chromium');

  await page.goto('/', { waitUntil: 'commit' });
  await waitForFirstFrame(page);

  const runtime = await page.evaluate(() => ({
    isolated: window.crossOriginIsolated,
    skwasm: Boolean(
      (window as typeof window & { _flutter_skwasmInstance?: unknown })
        ._flutter_skwasmInstance,
    ),
    wasmEntrypoint: performance
      .getEntriesByType('resource')
      .some((entry) => entry.name.endsWith('/main.dart.wasm')),
  }));

  expect(runtime.skwasm).toBe(true);
  expect(runtime.wasmEntrypoint).toBe(true);
  // Must stay false. Cross-origin isolation is what multi-threaded SkWasm wants,
  // but it makes COEP block Firebase Auth's /__/auth/iframe and every signed-in
  // Chromium user gets ERR_BLOCKED_BY_RESPONSE. See firebase.json.
  expect(runtime.isolated).toBe(false);
});

test('the JavaScript fallback is downloaded once, not twice', async ({
  page,
  browserName,
}) => {
  test.skip(browserName === 'chromium', 'Chromium takes the Wasm entrypoint');

  let entrypointRequests = 0;
  page.on('request', (request) => {
    if (request.url().endsWith('/main.dart.js')) entrypointRequests += 1;
  });

  await page.goto('/', { waitUntil: 'commit' });
  await waitForFirstFrame(page);

  expect(entrypointRequests).toBe(1);
});
