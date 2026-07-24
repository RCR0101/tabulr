import { defineConfig, devices } from '@playwright/test';

/**
 * Tabulr browser stress harness.
 *
 * Target the app under test with BASE_URL (a deployed build or a local
 * `flutter run -d web-server` / `python3 -m http.server` over `build/web`).
 * Defaults to the local Flutter web-server port.
 *
 *   BASE_URL=https://tabulr.example.app npx playwright test
 *
 * The "chromium-brave-like" project approximates Brave's posture — a Chromium
 * with third-party storage partitioning and reduced-state flags — which is
 * where the original 5–10 min / stuck-on-loading reports came from. It is an
 * approximation, not Brave itself; see README for running real Brave.
 */
export default defineConfig({
  testDir: './tests',
  timeout: 120_000,
  expect: { timeout: 40_000 },
  fullyParallel: false, // storage/boot-watchdog tests must not share a profile
  workers: 1,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:8080',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    {
      name: 'chromium-brave-like',
      use: {
        ...devices['Desktop Chrome'],
        launchOptions: {
          args: [
            '--enable-features=ThirdPartyStoragePartitioning,PartitionedCookies',
            '--disable-features=PrivacySandboxSettings4',
          ],
        },
      },
    },
  ],
});
