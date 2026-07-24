import { test, expect } from '@playwright/test';
import { waitForFirstFrame } from './_helpers';

/**
 * #12 — multi-tab.
 *
 * Firestore web persistence (`persistenceEnabled: true`) is single-tab-locked:
 * only the first tab gets the IndexedDB lease; the rest must degrade gracefully
 * (fall back to in-memory) rather than hang. Open several tabs in one context
 * (shared storage, like a real user) and assert every one still reaches first
 * frame.
 */

test('several tabs of the same app all reach first frame', async ({ context }) => {
  const TAB_COUNT = 6;
  const pages = await Promise.all(
    Array.from({ length: TAB_COUNT }, () => context.newPage()),
  );

  await Promise.all(
    pages.map(async (p) => {
      await p.goto('/', { waitUntil: 'commit' });
      await waitForFirstFrame(p, 60_000);
    }),
  );

  // Every tab painted; none wedged on the persistence lock.
  for (const p of pages) {
    await expect(p.locator('#loading')).toHaveCount(0);
  }

  await Promise.all(pages.map((p) => p.close()));
});
