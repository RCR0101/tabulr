# Tabulr

A timetable builder for BITS Pilani students. Build clash-free schedules, compare options, track exams, and share timetables — all from one app.

**Web** &bull; **macOS** &bull; **Windows** &bull; **Linux**

## What it does

- **Build timetables** — browse the full course catalog, pick sections, and see clashes in real time
- **Auto-generate** — set constraints (max hours/day, avoid slots, prefer instructors) and get ranked timetable options
- **Calendar view** — weekly schedule with classes, exams, custom events, and professor office hours
- **Share & import** — share timetables via a short code; import a friend's with one tap
- **Compare** — side-by-side timetable comparison and common free-slot finder
- **Exam seating** — look up your exam room by student ID
- **Academic drives** — browse course materials uploaded by the community
- **Export** — PNG image (with exam dates), ICS for Google Calendar / Outlook, `.tt` file backup

## Quick start

```bash
cd timetable_maker
flutter pub get
flutter run -d chrome        # web
flutter run -d macos         # or windows / linux
```

Requires Flutter 3.7+ with desktop support enabled. The app uses Firebase — `lib/firebase_options.dart` and `.env` are gitignored and must be configured for your own Firebase project.

## Project structure

```
lib/
  models/       Data classes (Course, Timetable, Section, ExamSchedule)
  services/     Business logic, Firebase, clash detection, timetable generation
  screens/      Full-page views (timetables, calendar, CGPA, exam seating, ...)
  widgets/      Reusable UI components
  mixins/       Shared editor behavior (timetable editing, export, sharing)
  utils/        Design tokens, constants
  repositories/ Local + Firestore persistence
```

## Key features

| Feature | Description |
|---------|-------------|
| Clash detection | Prevents time conflicts between classes and exams across all section types |
| TT Generator | Cartesian product + scoring over selected courses with configurable constraints |
| Section shuffle | When a section closes, suggests alternative arrangements across your courses |
| Quick replace | Swap individual sections while preserving the rest of your timetable |
| Multi-campus | Supports Pilani, Goa, and Hyderabad course catalogs |
| Themes | 8 dark + light themes with system mode support |

## Tech stack

- **Flutter** (Dart) — cross-platform UI
- **Firebase** — Auth, Firestore (timetables, settings, shared data), Hosting (PWA)
- **Cloudflare R2** — academic drive file storage

## Created by

Aryan Dalmia
