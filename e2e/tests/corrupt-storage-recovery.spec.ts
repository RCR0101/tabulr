import { test, expect } from '@playwright/test';
import { waitForFirstFrame, readLocalStorage, idbNames } from './_helpers';

/**
 * #11 — boot-watchdog corrupt-storage recovery.
 *
 * index.html counts boots that never reach first frame in localStorage
 * (`boot_fails`); after two it purges IndexedDB (incl. Firestore), Cache
 * Storage, service workers and localStorage, then boots clean. A healthy boot
 * clears the counter on first frame. These assert both halves: it recovers a
 * wedged store, and it never fires on healthy loads.
 */

test.describe('boot watchdog', () => {
  test('healthy loads never accumulate toward a purge', async ({ page }) => {
    for (let i = 0; i < 3; i++) {
      await page.goto('/', { waitUntil: 'commit' });
      await waitForFirstFrame(page);
      // Cleared on every first frame, so it can never reach the limit (2).
      expect(await readLocalStorage(page, 'boot_fails')).toBeNull();
    }
  });

  test('a simulated wedge is purged and recovers on the next load', async ({ page }) => {
    // Reach a good state first so we have an origin to seed.
    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);

    // Simulate two prior boots that never painted, plus junk local state.
    await page.evaluate(async () => {
      window.localStorage.setItem('boot_fails', '2');
      window.localStorage.setItem('user_timetable_data', '{corrupt-json');
      // A bogus Firestore-shaped IndexedDB the watchdog should delete.
      await new Promise<void>((resolve) => {
        const req = indexedDB.open('firestore/[DEFAULT]/tabulr/main', 1);
        req.onsuccess = () => {
          req.result.close();
          resolve();
        };
        req.onerror = () => resolve();
        req.onupgradeneeded = () => {
          try {
            req.result.createObjectStore('junk');
          } catch {
            /* ignore */
          }
        };
      });
    });

    // Next load: boot_fails >= 2 -> purge everything, then boot clean.
    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);

    expect(await readLocalStorage(page, 'boot_fails')).toBeNull();
    expect(await readLocalStorage(page, 'user_timetable_data')).toBeNull();
    const dbs = await idbNames(page);
    expect(dbs.some((n) => n.includes('firestore/[DEFAULT]/tabulr/main'))).toBeFalsy();
  });
});
