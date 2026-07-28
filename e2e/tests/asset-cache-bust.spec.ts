import { test, expect } from '@playwright/test';
import { waitForFirstFrame, readLocalStorage } from './_helpers';

/**
 * One-shot asset cache bust.
 *
 * assets/ used to ship as `immutable, max-age=1y` while its contents are
 * rebuilt every deploy at stable URLs — MaterialIcons-Regular.otf is
 * tree-shaken to whichever icons the code references — so returning browsers
 * held a subset missing every newly added icon. Nothing on the page can evict
 * an HTTP cache entry, so index.html re-fetches those files with
 * `cache: 'reload'`, which overwrites the entry, before the engine loads.
 *
 * The two things that must hold: the refresh wins the race against Flutter's
 * own asset load, and it never runs twice.
 */

const FONT = 'assets/fonts/MaterialIcons-Regular.otf';
const BUST_KEY = 'asset_cache_bust_v1';

/**
 * Request paths in flight order. Ordering is the observable signal here:
 * the refresh is only useful if it lands before flutter_bootstrap.js, and
 * checking order rather than counts keeps this independent of whether a
 * given browser served something from cache.
 */
function trackRequests(page: import('@playwright/test').Page): string[] {
  const seen: string[] = [];
  page.on('request', (r) => seen.push(new URL(r.url()).pathname));
  return seen;
}

const indexOfMatch = (paths: string[], needle: string) =>
  paths.findIndex((p) => p.includes(needle));

test.describe('asset cache bust', () => {
  test('refreshes the icon font before the engine loads, then records itself', async ({
    page,
  }) => {
    const requests = trackRequests(page);

    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);

    const font = indexOfMatch(requests, 'MaterialIcons-Regular.otf');
    const bootstrap = indexOfMatch(requests, 'flutter_bootstrap.js');
    expect(font, 'icon font was never re-fetched').toBeGreaterThanOrEqual(0);
    expect(bootstrap).toBeGreaterThanOrEqual(0);
    expect(font, 'refresh lost the race to the engine').toBeLessThan(bootstrap);

    expect(await readLocalStorage(page, BUST_KEY)).toBe('1');
  });

  test('does not run again once recorded', async ({ page, context }) => {
    // Seed only the bust flag. Leaving `app_version` unset matters: with it
    // set, index.html preloads flutter_bootstrap.js before any of this runs,
    // and the ordering assertion below would pass for the wrong reason.
    await context.addInitScript(
      ([key]) => window.localStorage.setItem(key, '1'),
      [BUST_KEY],
    );

    const requests = trackRequests(page);

    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);

    const bootstrap = indexOfMatch(requests, 'flutter_bootstrap.js');
    expect(bootstrap).toBeGreaterThanOrEqual(0);

    const before = requests.slice(0, bootstrap);
    expect(
      before.filter((p) => p.includes(FONT)),
      'the one-shot refresh ran a second time',
    ).toEqual([]);
  });
});
