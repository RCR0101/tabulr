# Tabulr

![Platform](https://img.shields.io/badge/platform-web%20%7C%20macOS%20%7C%20windows%20%7C%20linux-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.7%2B-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-backend-FFCA28?logo=firebase&logoColor=black)
![Version](https://img.shields.io/badge/version-2.5.29-informational)
![License](https://img.shields.io/badge/license-MIT-green)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

A course-planning and timetable app for BITS Pilani students. Build clash-free
schedules, plan your CGPA, look up exam rooms and professor chambers, explore
electives and minors, and share it all — across **Pilani, Goa, and Hyderabad**.

**Web** &bull; **macOS** &bull; **Windows** &bull; **Linux**

> ~70k lines of Dart across 40+ screens and 50+ services, backed by Firebase and
> a Cloud Functions backend.

## What it does

### Timetables
- **Build** — browse the full course catalog, pick sections, and see clashes (class *and* exam) in real time
- **Auto-generate** — set constraints (max hours/day, avoid slots, prefer instructors) and get ranked timetable options
- **Add / swap / quick-replace** — swap a single closed section while preserving the rest of your schedule
- **Calendar view** — weekly grid with classes, exams, custom events, and professor office hours
- **Compare** — side-by-side timetables and a common free-slot finder
- **Share & import** — hand a friend a short code; they import your timetable with one tap
- **Archive & export** — PNG (with exam dates), ICS for Google Calendar / Outlook, `.tt` file backup

### Academic planning
- **CGPA calculator** with duplicate-course guards and semester-by-semester breakdown
- **CG booster & grade planner** — what grades do you need this sem to hit a target CGPA
- **CGPA trajectory** — visualize your grade history and projections
- **Prerequisites explorer**, **course guide**, and **auto-loaded CDCs** by branch
- **Electives & minors** — open, discipline, and humanities electives, plus minor catalogs

### Campus info
- **Exam seating** — look up your room and seat by student ID (handles combined-exam codes)
- **Prof Chambers** — professor office locations and live "in class / free" status
- **Academic calendar**, **course announcements**, and **academic drives** (community-uploaded materials)

### Account & platform
- Google sign-in, profile, and per-campus catalogs
- 9 themes (GitHub Dark, Dracula, Nord, Tokyo Night, Gruvbox, Catppuccin, Solarized, Arctic Frost, AMOLED) with light/dark/system modes
- In-app bug reporting with a contributor reputation system
- An **admin suite** for maintainers: course, exam-seating, professor, prerequisite, minor, and academic-calendar management, plus a bug tracker and duplicate-course cleanup

## Quick start

```bash
cd timetable_maker
flutter pub get
flutter run -d chrome        # web
flutter run -d macos         # or windows / linux
```

Requires **Flutter 3.7+** with desktop support enabled (the pinned version lives
in `.fvmrc` — [FVM](https://fvm.app/) recommended). The app needs Firebase:
`lib/firebase_options.dart` and `.env` are gitignored and must be supplied for
your own project — see [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md).

## Architecture at a glance

```
lib/
  models/         Pure data classes & enums (no service imports)
  services/
    core/         Algorithms — clash detection, timetable generation, CGPA, undo/redo
    data/         Firestore & persistence services (40+ singletons)
    ui/           Theme, responsive, toast, export, logging
    parsers/      File-format parsers
  screens/        Full-page views (+ screens/admin/ for the maintainer suite)
  widgets/        Reusable UI components (widgets/common/ = the design system)
  mixins/         Shared editor behavior (editing, export, sharing)
  repositories/   Local + Firestore persistence abstractions
  utils/          Design tokens, constants, helpers

functions-python/ Python Cloud Functions (exam/timetable parsing & sync) — main.py
functions/        JS Cloud Functions (admin.js, index.js)
scripts/          Data upload/convert tooling (courses, exams, timetables, prereqs)
e2e/              Playwright cross-browser tests (loading, cache recovery, multi-tab)
test/             63 Dart tests — property, fuzz, concurrency, and widget tests
```

- **State management**: `ChangeNotifier` factory-singletons + `setState`. No Provider/Riverpod/BLoC.
- **Navigation**: imperative `Navigator.push` with `FadeSlidePageRoute`. No go_router.
- **Data flow**: Firestore → Service (Future/Stream) → Screen (`setState`) → Widget. Algorithm services are stateless pure functions.

Full conventions, dependency rules, and the design language are in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Tech stack

- **Flutter / Dart** — cross-platform UI (web PWA + native desktop)
- **Firebase** — Auth (Google), Firestore, Storage, App Check, Cloud Functions, Hosting
- **Python & JS Cloud Functions** — server-side parsing and data sync
- **Cloudflare R2** — academic-drive file storage
- **syncfusion_flutter_pdf** — PDF/image export
- Testing: `flutter_test` (63 suites) + **Playwright** across Chromium, Firefox, WebKit, and a Brave-like profile

## Contributing

Contributions are welcome — bug fixes, new BITS data, and features all help.

1. **Find or open an issue** describing the bug or feature (or use the in-app bug reporter).
2. **Fork & branch** off `main` (`main` is the deploy branch — feature-branch your work).
3. **Make the change**, keeping PRs focused on one issue or feature.
4. **Run the checks** — every PR must pass these (CI runs them too):
   ```bash
   flutter analyze     # no new errors
   flutter test        # all suites green
   ```
5. **Open a PR** with a short _what_ and _why_; the diff covers the _how_.

Before writing code, read **[CONTRIBUTING.md](CONTRIBUTING.md)** — it covers the
project structure, dependency rules, state/naming conventions, the design system
(themes, spacing tokens, components), and what not to touch without asking.
Firebase setup is in [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md); please also
follow the [Code of Conduct](CODE_OF_CONDUCT.md), and report vulnerabilities per
[SECURITY.md](SECURITY.md) rather than in a public issue.

## License

Released under the [MIT License](LICENSE).

## Created by

Aryan Dalmia
