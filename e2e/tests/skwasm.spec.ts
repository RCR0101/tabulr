import { test, expect } from '@playwright/test';
import { waitForFirstFrame } from './_helpers';

test('Chromium uses isolated SkWasm rather than the JavaScript fallback', async ({
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

  expect(runtime.isolated).toBe(true);
  expect(runtime.skwasm).toBe(true);
  expect(runtime.wasmEntrypoint).toBe(true);
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
