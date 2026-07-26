import { test, expect, Page } from '@playwright/test';
import { waitForFirstFrame } from './_helpers';

/**
 * URL routing in a real browser.
 *
 * What is NOT covered here: switching tabs with the back button — because the
 * app does not do it. A plain `Navigator` keeps the web engine in single-entry
 * history mode, where a URL update replaces the current entry instead of adding
 * one, so Back leaves the site. `AppRoutes.show` documents why the obvious fix
 * (calling `selectMultiEntryHistory` later) makes things worse; the cold-load
 * test below is the one that caught it.
 *
 * What IS covered: everything a signed-out visitor arriving from a search
 * result or a pasted link actually experiences.
 *
 *   flutter build web && python3 e2e/serve.py
 *   npx playwright test routing --project=chromium
 *
 * `serve.py` adds the SPA fallback that Firebase Hosting provides; a plain
 * `http.server` 404s on `/credits` and cannot exercise a cold-loaded deep link
 * at all. The cold-load tests detect the fallback and skip without it.
 */

const path = (page: Page) => page.evaluate(() => window.location.pathname);

/** Whether the harness rewrites unknown paths to index.html, as Hosting does. */
async function hasSpaFallback(page: Page): Promise<boolean> {
  const response = await page.request.get('/__spa_probe__');
  return response.status() === 200;
}

/** Turns on Flutter's semantics tree so the canvas has readable DOM nodes. */
async function enableSemantics(page: Page) {
  await page.evaluate(() =>
    (document.querySelector('flt-semantics-placeholder') as HTMLElement | null)?.click(),
  );
  await page.waitForTimeout(1000);
}

/**
 * Navigates within the loaded app the way the browser does, without a reload:
 * a static file server has no SPA rewrite, so `page.goto('/faq')` would 404 on
 * the harness rather than exercise the app.
 */
async function navigateInPlace(page: Page, to: string) {
  await page.evaluate((p) => {
    window.history.pushState(null, '', p);
    window.dispatchEvent(new PopStateEvent('popstate'));
  }, to);
  await page.waitForTimeout(2000);
}

async function labels(page: Page): Promise<string[]> {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('[aria-label]'))
      .map((e) => e.getAttribute('aria-label') ?? '')
      .filter(Boolean),
  );
}

test.describe('routing', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/', { waitUntil: 'commit' });
    await waitForFirstFrame(page);
  });

  test('the landing page keeps a clean, fragment-free URL', async ({ page }) => {
    // usePathUrlStrategy. Without it every path carries a `#`, and neither the
    // static course pages nor a pasted share link would resolve.
    expect(await path(page)).toBe('/');
    expect(page.url()).not.toContain('#');
  });

  test('a deep link survives the sign-in wall instead of being rewritten', async ({ page }) => {
    // The property that makes links from the static course pages worth having.
    // A signed-out visitor sees the auth screen — but the app must leave the
    // URL alone, because AppShell reads it when it finally mounts. If anything
    // wrote the URL back here, the visitor would sign in and land on the
    // default tab, and the link would have been for nothing.
    await enableSemantics(page);
    await navigateInPlace(page, '/exam-seating');

    expect(await path(page)).toBe('/exam-seating');
    expect(await labels(page)).toContain('Sign in with Google');
  });

  test('an unknown path neither throws nor wedges the app', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));

    await enableSemantics(page);
    await navigateInPlace(page, '/not-a-real-screen');

    expect(errors, errors.join('\n')).toEqual([]);
    // Still interactive, not a blank canvas.
    expect(await labels(page)).toContain('Continue as Guest');
  });

  test('a signed-out visitor is not stranded on /profile', async ({ page }) => {
    // /profile is signedInOnly, so its route must not generate. Flutter drops
    // an initial route it cannot build and falls back to the app — the failure
    // mode being guarded against is an empty settings form over nothing.
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));

    await enableSemantics(page);
    await navigateInPlace(page, '/profile');

    expect(errors, errors.join('\n')).toEqual([]);
    expect(await labels(page)).toContain('Continue as Guest');
  });

  test('a cold-loaded URL opens the screen it names', async ({ page }) => {
    // The reported bug, in its general shape: typing a path into the address
    // bar must open that screen, with no in-app navigation to help it. Uses
    // /credits because it is the one pushed screen a signed-out visitor may
    // open; the gated ones (/prerequisites, /electives, /profile) take the same
    // route table but need a session this harness has not got.
    test.skip(!(await hasSpaFallback(page)), 'needs e2e/serve.py or a deployed BASE_URL');

    await page.goto('/credits', { waitUntil: 'commit' });
    await waitForFirstFrame(page);
    await enableSemantics(page);

    expect(await path(page)).toBe('/credits');
    const found = await labels(page);
    expect(
      found.some((l) => /credit|contributor|about|tabulr/i.test(l)),
      `no Credits content in: ${JSON.stringify(found)}`,
    ).toBe(true);
  });

  test('closing a cold-loaded screen leaves a sane URL, not /', async ({ page }) => {
    // The Navigator announces the route it uncovers — `home`, named `/` — so
    // without AppRouteHistory's correction the address bar reads `/` while a
    // tab is showing.
    test.skip(!(await hasSpaFallback(page)), 'needs e2e/serve.py or a deployed BASE_URL');

    await page.goto('/credits', { waitUntil: 'commit' });
    await waitForFirstFrame(page);
    await page.goBack();
    await page.waitForTimeout(2000);

    expect(await path(page)).not.toBe('/credits');
  });

  test('cold-loading a deep link works through the hosting rewrite', async ({ page }) => {
    // Only meaningful against Firebase Hosting, where `** -> /index.html`
    // serves the app for an arbitrary path. A static file server 404s instead,
    // which is a property of the harness, not of the app.
    test.skip(
      !process.env.BASE_URL || process.env.BASE_URL.includes('localhost'),
      'needs a deployed BASE_URL with the SPA rewrite',
    );
    const response = await page.goto('/exam-seating', { waitUntil: 'commit' });
    expect(response?.status()).toBe(200);
    await waitForFirstFrame(page);
    expect(await path(page)).toBe('/exam-seating');
  });
});
