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
- Firestore query changes may need a composite index; check `firestore.indexes.json`.

### Dependency rules

Models (`lib/models/`) are pure data — they must **not** import from `services/`, `screens/`, or `widgets/`. If a model needs a display name or formatted value that requires service data, the caller (screen or controller) should perform the lookup.

Screens may import services, models, widgets, and utils. Services may import models and utils. Widgets may import models and utils. Never create a cycle.

### Architecture

**State management**: `ChangeNotifier` singletons + `setState` in screens. No Provider, Riverpod, or BLoC. Screens subscribe to services via `addListener` in `initState` and `removeListener` in `dispose`. Some use `ListenableBuilder`. Controllers (`CGPACalculatorController`, `TimetableGeneratorController`) are `ChangeNotifier`s instantiated inside their screen, not injected from above.

**Dependency injection**: Factory-singleton pattern — every service has `factory AuthService() => _instance`. Access a service by calling its constructor. Controllers that need testable deps accept optional constructor params defaulting to the singletons.

**Navigation**: Imperative `Navigator.push` with `FadeSlidePageRoute` (defined in `utils/page_transitions.dart`). No named routes, no go_router.

**Data flow**: Firestore → Service (Future/Stream) → Screen (`setState`) → Widget. Algorithm services (`clash_detector`, `timetable_generator`) are stateless pure functions called by controllers.

**Naming**: Files use `snake_case.dart`. Classes use `PascalCase` with role suffixes: `*Service` (data/logic singletons), `*Controller` (ChangeNotifier for screen state), `*Screen` (full pages), `*Widget` (reusable UI). Private fields: `_camelCase`; getters: `camelCase`.

**When to use a Controller vs screen State**: Create a `*Controller` (extending `ChangeNotifier`) when the screen has complex business logic, multiple data sources, or needs testability. Simple screens can keep logic in the `State` class directly.

### Design language

**Themes**: Material 3 color roles, manual `ThemeData` construction (not `useMaterial3: true`). 9 named themes (GitHub Dark, Dracula, Nord, Tokyo Night, Gruvbox, Catppuccin, Solarized Dark, Arctic Frost, AMOLED Dark) with dark + light variants. Each theme carries a `ThemeGeometry` extension for per-theme shape radii (`cardRadius`, `buttonRadius`, `dialogRadius`, `inputRadius`, `chipRadius`).

**Typography**: Inter, bundled as `assets/fonts/Inter.ttf` and declared in `pubspec.yaml` (no `google_fonts` — the font ships with the app to avoid FOUT). Always derive from `Theme.of(context).textTheme.*` — never use raw `TextStyle(fontSize: ...)`.

**Spacing**: Use tokens from `AppDesign` in `utils/design_constants.dart`: `spacingXxs=2`, `spacingXs=4`, `spacingSm=8`, `spacingMd=16`, `spacingLg=24`, `spacingXl=32`, `spacingXxl=48`.

**Semantic colors**: `AppDesign.success(ctx)`, `.warning(ctx)`, `.info(ctx)`, `.danger(ctx)`, `.muted(ctx)`, `.dividerColor(ctx)`.

**Motion**: `flutter_animate` with standardized extensions: `.motionEntry()` (fade + slide-up for cards), `.motionFadeIn()` (content swaps), `.motionScale()` (dialogs, FABs), `.motionListItem(index)` (staggered lists). Tokens: `motionFast=200ms`, `motionStandard=350ms`, `motionEmphasized=500ms`.

**Responsive**: Three breakpoints via `ResponsiveService` — use `context.isMobile` / `context.isDesktop` or `ResponsiveService.getValue(context, mobile: ..., tablet: ..., desktop: ...)`. Dialogs must use `AppDialog.adaptive()` — modal bottom sheet on mobile, standard dialog on desktop.

**Components**: `AppButton` (variant enum: primary/secondary/ghost/danger), `AppDialog.adaptive` (static factory), `FrostedContainer` (blur overlay for sheets), `EmptyStateWidget` (icon + message). See `lib/widgets/common/` for the full set.

**Icons**: Material Icons (`Icons.*`) throughout — no third-party icon package.

### Style

- No comments unless the _why_ is non-obvious.
- No speculative abstractions — three similar lines beats a premature helper.
- Prefer editing existing files over creating new ones.
- Never silently swallow errors with empty `catch (_) {}` — at minimum log the error or rethrow.
- For clickable elements that aren't Material ink surfaces, use `AppTappable` (`widgets/common/app_tappable.dart`), not a raw `GestureDetector` — the latter keeps the default arrow cursor on web instead of the pointer/hand. Pan/swipe/drag-only handlers stay on a plain `GestureDetector`.
- `GradeConstants.normal` and `GradeConstants.points` are parallel arrays — always keep them in sync.

## What not to touch without asking

- `firestore.rules` (production config)
- Anything under `macos/`, `windows/`, `linux/`, `web/`, `build/` (platform scaffolding)
- Scripts that write to Firestore or R2 (`upload-*`, `purge-*`, `full-sync`)
