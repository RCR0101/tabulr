# Contributing to Tabulr

## Setup

1. Install Flutter (version pinned in `.fvmrc` — use [FVM](https://fvm.app/) or match manually).
2. `flutter pub get`
3. Create `lib/firebase_options.dart` and `.env` from the project's Firebase config (ask a maintainer).
4. `flutter run -d macos` (or `-d chrome` for web).

## Branch strategy

- `main` is the deploy branch — pushes trigger a preview deploy.
- Work on feature branches off `main`; open a PR when ready.
- Production deploys are manual (`Deploy Production` workflow).

## PR process

1. Run `flutter analyze` — no new errors allowed (pre-existing `deprecated_member_use` infos are fine).
2. Run `flutter test` — all tests must pass.
3. Keep PRs focused: one issue or feature per PR.
4. Write a short description of _what_ and _why_; the diff covers _how_.

## Code standards

### Project structure

```
lib/
  models/       — plain data classes, enums, no Flutter imports where possible
  services/
    core/       — algorithms (clash detection, timetable generation)
    data/       — Firestore/persistence services
    ui/         — theme, responsive, toast, export (may import Flutter)
    parsers/    — file format parsers
  screens/      — full-page widgets
  widgets/      — reusable UI components
  repositories/ — persistence abstractions
  utils/        — pure helpers
  mixins/       — shared widget behavior
```

### Conventions

- New types go in `models/`, not inside service files.
- Services must not call `showDialog` or own UI — return data and let the caller handle presentation.
- Services under `data/` and `core/` should import `foundation.dart` not `material.dart` when they only need `ChangeNotifier`.
- `home_screen.dart` has **two** state classes — mirror changes in both.
- Firestore query changes may need a composite index; check `FIREBASE_INDEXES.md`.

### Style

- No comments unless the _why_ is non-obvious.
- No speculative abstractions — three similar lines beats a premature helper.
- Prefer editing existing files over creating new ones.

## What not to touch without asking

- `firestore.rules` (production config)
- Anything under `macos/`, `windows/`, `linux/`, `web/`, `build/` (platform scaffolding)
- Scripts that write to Firestore or R2 (`upload-*`, `purge-*`, `full-sync`)
