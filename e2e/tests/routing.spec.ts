import { test, expect, Page } from '@playwright/test';
import { waitForFirstFrame } from './_helpers';

/**
 * URL routing in a real browser.
 *
 * Every test here cold-loads its path, because that is the only way a visitor
 * arrives at one: from a search result, a pasted link, or the address bar. An
 * earlier version drove navigation with `pushState` + a synthetic `popstate`,
 * which tested nothing — in single-entry history mode the Flutter engine owns
 * `popstate` and reads it as a back press, so the app never saw the new path.
 *
 * What is NOT covered: watching the back button switch tabs. The shell only
 * exists for a signed-in user, and this harness has no session. The mode that
 * makes it work is asserted instead — see the multi-entry test below.
 *
 *   flutter build web && python3 e2e/serve.py
 *   npx playwright test routing --project=chromium
 *
 * `serve.py` adds the SPA fallback that Firebase Hosting provides; a plain
 * `http.server` 404s on `/credits` and cannot exercise a cold-loaded deep link
 * at all. Without it every test here skips.
 */

const path = (page: Page) => page.evaluate(() => window.location.pathname);

/** Whether the harness rewrites unknown paths to index.html, as Hosting does. */
async function hasSpaFallback(page: Page): Promise<boolean> {
  const response = await page.request.get('/__spa_probe__');
  return response.status() === 200;
}

/**
 * Loads `to` the way a visitor does, and turns on Flutter's semantics tree so
 * the canvas has readable DOM nodes.
 */
async function coldLoad(page: Page, to: string) {
  await page.goto(to, { waitUntil: 'commit' });
  await waitForFirstFrame(page);
  await page.evaluate(() =>
    (document.querySelector('flt-semantics-placeholder') as HTMLElement | null)?.click(),
  );
  await page.waitForTimeout(1000);
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
    test.skip(!(await hasSpaFallback(page)), 'needs e2e/serve.py or a deployed BASE_URL');
  });

  test('the landing page keeps a clean, fragment-free URL', async ({ page }) => {
    // usePathUrlStrategy. Without it every path carries a `#`, and neither the
    // static course pages nor a pasted share link would resolve.
    await coldLoad(page, '/');
    expect(await path(page)).toBe('/');
    expect(page.url()).not.toContain('#');
  });

  test('a deep link survives the sign-in wall instead of being rewritten', async ({ page }) => {
    // The property that makes links from the static course pages worth having.
    // A signed-out visitor sees the auth screen — but the app must leave the
    // URL alone, because AppShell reads it when it finally mounts. If anything
    // wrote the URL back here, the visitor would sign in and land on the
    // default tab, and the link would have been for nothing.
    await coldLoad(page, '/exam-seating');

    expect(await path(page)).toBe('/exam-seating');
    expect(await labels(page)).toContain('Sign in with Google');
  });

  test('an unknown path neither throws nor wedges the app', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));

    await coldLoad(page, '/not-a-real-screen');

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

    await coldLoad(page, '/profile');

    expect(errors, errors.join('\n')).toEqual([]);
    expect(await labels(page)).toContain('Continue as Guest');
  });

  test('a cold-loaded URL opens the screen it names', async ({ page }) => {
    // The reported bug, in its general shape: typing a path into the address
    // bar must open that screen, with no in-app navigation to help it. Uses
    // /credits because it is the one pushed screen a signed-out visitor may
    // open; the gated ones (/prerequisites, /electives, /profile) take the same
    // route table but need a session this harness has not got.
    await coldLoad(page, '/credits');

    expect(await path(page)).toBe('/credits');
    const found = await labels(page);
    expect(
      found.some((l) => /credit|contributor|about|tabulr/i.test(l)),
      `no Credits content in: ${JSON.stringify(found)}`,
    ).toBe(true);
  });

  test('the browser is in multi-entry history mode', async ({ page }) => {
    // The precondition for the back button doing anything useful. In
    // single-entry mode — which a plain `MaterialApp(home:)` selects — every URL
    // update replaces the current entry, so Back leaves the site instead of
    // walking back through the app. `MaterialApp.router` is what avoids it.
    //
    // Read off the engine's own history state, whose shape differs between the
    // two modes: multi-entry stores `{serialCount, state}`, single-entry a
    // `{flutter: true}` sentinel entry over an `{origin: true}` one. Watching
    // the back button switch tabs would be better, but the shell only exists
    // for a signed-in user and this harness has no session.
    await coldLoad(page, '/');
    const state = await page.evaluate(() => window.history.state);

    expect(state, 'engine history state').not.toBeNull();
    expect(state).toHaveProperty('serialCount');
  });

  test('cold-loading a deep link works through the hosting rewrite', async ({ page }) => {
    // Only meaningful against Firebase Hosting, where `** -> /index.html`
    // serves the app for an arbitrary path. serve.py mimics it; this asserts
    // the status code the real thing returns.
    const response = await page.goto('/exam-seating', { waitUntil: 'commit' });
    expect(response?.status()).toBe(200);
    await waitForFirstFrame(page);
    expect(await path(page)).toBe('/exam-seating');
  });
});
