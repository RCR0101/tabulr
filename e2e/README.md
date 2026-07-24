# Tabulr browser stress harness (`e2e/`)

Browser-level regression/stress tests that can't run inside `flutter test` because
they need a real browser, real IndexedDB/Cache Storage, real service workers, and
network-level fault injection. These target the **loading / storage / multi-tab**
failure classes behind the original "Brave, non-incognito, 5–10 min, stuck on
loading" reports.

They are **not** wired into the Dart unit suite and won't run in CI until you set
this up — they're committed as a ready-to-run harness.

## Prerequisites

- Node 18+.
- A **built, served web app** to point at:
  ```bash
  # from repo root
  flutter build web
  cd build/web && python3 -m http.server 8080     # or any static server
  # …or the fast path for iteration:
  flutter run -d web-server --web-port 8080
  ```
- Playwright + browsers:
  ```bash
  cd e2e
  npm install
  npm run install:browsers
  ```

## Running

```bash
cd e2e
BASE_URL=http://localhost:8080 npm test            # all projects
BASE_URL=http://localhost:8080 npx playwright test --project=chromium-brave-like
BASE_URL=https://your-deployed-build npm test      # against a deployed build
npm run report                                     # open the HTML report
```

The `chromium-brave-like` project approximates Brave's storage posture with
Chromium flags. For the **real** browser, install Brave and run headed against it
via `channel`/`executablePath` in `playwright.config.ts`, or drive it manually
with Shields on/off while watching the console.

## What maps to what (from the stress-test menu)

| # | Area | Where |
|---|------|-------|
| 9  | Network fault injection (stall / abort / latency on Firestore + version.json) | `tests/loading.spec.ts` (route interception — no emulator needed) |
| 10 | Cross-browser first-frame timing | `tests/loading.spec.ts` × the 4 Playwright projects |
| 11 | Corrupt-storage boot-watchdog recovery | `tests/corrupt-storage-recovery.spec.ts` |
| 12 | Multi-tab persistence-lock degradation | `tests/multi-tab.spec.ts` |
| 13 | Monkey / random-gesture soak | see **Flutter integration_test** below |
| 14 | Memory / leak soak | see **DevTools procedure** below |
| 15 | Generator combinatorial blow-up | see **DevTools procedure** below |
| 16 | Offline↔online flapping | Playwright `context.setOffline(true/false)` — extend `loading.spec.ts` |
| 17 | Clock-skew / timezone | launch context with `timezoneId` + a fake `Date` init script |

### #9 alternative — backend-side faults (Firebase emulator + toxiproxy)

Route interception (above) reproduces the *client-observed* stall faithfully and
needs no backend. If you also want to fault the **backend** (permission-denied
bursts, reordered responses, connection resets mid-write):

```bash
firebase emulators:start --only firestore          # emulator on :8080
toxiproxy-cli create fs -l 127.0.0.1:8666 -u 127.0.0.1:8080
toxiproxy-cli toxic add fs -t latency -a latency=300000   # 5-min stall
# point the app's Firestore host at 127.0.0.1:8666, then run the loading specs
```

### #13 — monkey soak (Flutter, not Playwright)

Add `integration_test` + a random-action driver (weighted toward the course-panel
collapse toggle, FAB, save, and back-button mid-save). Run for 30+ min on device/
emulator and watch for `setState after dispose`, double-pop, and animation-vs-
rebuild crashes. Skeleton lives in `integration_test/monkey_test.dart` once the
`integration_test` dev-dependency is added.

### #14 — memory / leak soak (DevTools)

Navigate every screen ~500× (or loop a script) with the DevTools memory profiler
attached; a monotonically climbing heap points at an undisposed `StreamSubscription`
(`_campusSubscription`, `_authSub`), `ValueNotifier`, or tutorial coach-mark
controller.

### #15 — generator blow-up (DevTools)

Feed the TT Generator a dense course set (many courses × many sections) and assert
it bounds its search (timeout/iteration cap) and stays responsive rather than
freezing the isolate or OOMing.

## Notes

- "First frame" is detected via the `#loading` spinner being removed — index.html
  removes it on `flutter-first-frame` and simultaneously clears the boot-watchdog
  counter, so it's a reliable single signal.
- Tests run **serially** (`workers: 1`) because the storage/watchdog tests mutate
  per-origin IndexedDB/localStorage and must not interleave.
