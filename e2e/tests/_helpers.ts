import { Page, expect } from '@playwright/test';

/**
 * The app shows a `#loading` spinner until Flutter's `flutter-first-frame`
 * fires, at which point index.html removes the element AND clears the boot
 * watchdog's `boot_fails` counter. So "spinner gone" is our single, robust
 * signal that the app actually painted.
 */
export async function waitForFirstFrame(page: Page, timeoutMs = 75_000) {
  await page.waitForSelector('#loading', { state: 'detached', timeout: timeoutMs });
}

/** Milliseconds from navigation start to first frame. */
export async function timeToFirstFrame(page: Page, url = '/'): Promise<number> {
  const start = Date.now();
  await page.goto(url, { waitUntil: 'commit' });
  await waitForFirstFrame(page);
  return Date.now() - start;
}

export async function readLocalStorage(page: Page, key: string): Promise<string | null> {
  return page.evaluate((k) => window.localStorage.getItem(k), key);
}

/** Names of every IndexedDB database currently present (Chromium/Firefox). */
export async function idbNames(page: Page): Promise<string[]> {
  return page.evaluate(async () => {
    if (!indexedDB.databases) return [];
    const dbs = await indexedDB.databases();
    return dbs.map((d) => d.name ?? '').filter(Boolean);
  });
}

/** True when a Firestore-owned IndexedDB store exists. */
export async function hasFirestoreIdb(page: Page): Promise<boolean> {
  const names = await idbNames(page);
  return names.some((n) => n.startsWith('firestore/'));
}

export { expect };
