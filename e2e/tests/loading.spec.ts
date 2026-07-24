import { test, expect } from '@playwright/test';
import { timeToFirstFrame, waitForFirstFrame } from './_helpers';

/**
 * #9 (network fault injection) + #10 (cross-browser loading).
 *
 * The original bug: on some browsers/extensions requests to Google endpoints
 * *stall* (never resolve, never error), so Firestore reads hung and the app
 * sat on the spinner for minutes. The Dart fix bounds every startup read; the
 * index.html fix bounds the version fetch and injects the engine regardless.
 * These tests assert the observable guarantee: the app paints within a bounded
 * time even when Firestore/version requests are deliberately stalled or failed.
 */

// Ceiling that catches the original "stuck for minutes" regression while
// tolerating a cold first run (uncached engine + first TLS handshake to Google
// endpoints can add ~30s once). Warm runs land at 1–13s; the app caps its own
// startup pre-fetch at ~12s.
const FIRST_FRAME_BUDGET_MS = 45_000;

test.describe('loading resilience', () => {
  test('paints quickly on a healthy load', async ({ page }) => {
    const ms = await timeToFirstFrame(page);
    expect(ms, `first frame took ${ms}ms`).toBeLessThan(FIRST_FRAME_BUDGET_MS);
  });

  test('paints even when Firestore requests stall indefinitely', async ({ page }) => {
    // Hold every Firestore request open forever — the classic "silent stall".
    await page.route(/firestore\.googleapis\.com/, () => {
      /* never fulfilled: the route handler simply never calls route.* */
    });
    const start = Date.now();
    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);
    const ms = Date.now() - start;
    expect(ms, `first frame took ${ms}ms with Firestore stalled`).toBeLessThan(
      FIRST_FRAME_BUDGET_MS,
    );
  });

  test('paints even when the version.json check stalls', async ({ page }) => {
    // index.html aborts the version fetch after ~4s and boots with the last
    // known version; a stall here must not block the engine injection.
    await page.route(/version\.json/, () => {
      /* never fulfilled */
    });
    const start = Date.now();
    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);
    expect(Date.now() - start).toBeLessThan(FIRST_FRAME_BUDGET_MS);
  });

  test('paints when Firestore requests are aborted (hard failure)', async ({ page }) => {
    await page.route(/firestore\.googleapis\.com/, (route) => route.abort());
    const start = Date.now();
    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);
    expect(Date.now() - start).toBeLessThan(FIRST_FRAME_BUDGET_MS);
  });

  test('paints under high added latency', async ({ page }) => {
    await page.route(/firestore\.googleapis\.com/, async (route) => {
      await new Promise((r) => setTimeout(r, 6000));
      await route.continue();
    });
    const ms = await timeToFirstFrame(page);
    expect(ms).toBeLessThan(FIRST_FRAME_BUDGET_MS);
  });
});
