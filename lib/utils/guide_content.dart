import 'package:flutter/material.dart';

import '../widgets/app_destinations.dart';
import '../widgets/app_tools.dart';
import 'page_info_helper.dart';

enum GuideVisual {
  weekGrid,
  agenda,
  courseCards,
  coursesTab,
  clashes,
  stats,
  weeklyLoad,
  generatorResult,
  rankingImportance,
  examTimeline,
  examDates,
  academicCalendar,
  cgpaTrajectory,
  bugStatuses,
}

class GuideTopic {
  const GuideTopic({
    required this.title,
    required this.anchor,
    required this.icon,
    required this.lead,
    this.pageInfo,
    this.steps = const [],
    this.visuals = const [],
    this.keywords = const [],
  });

  final String title;

  final String anchor;

  final IconData icon;
  final String lead;

  final PageInfo? pageInfo;

  final List<String> steps;
  final List<GuideVisual> visuals;

  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        lead.toLowerCase().contains(q) ||
        steps.any((s) => s.toLowerCase().contains(q)) ||
        keywords.any((k) => k.toLowerCase().contains(q)) ||
        (pageInfo?.features
                .any((f) => '${f.label} ${f.description}'.toLowerCase().contains(q)) ??
            false);
  }
}

class GuideSection {
  const GuideSection({
    required this.title,
    required this.anchor,
    required this.icon,
    required this.blurb,
    required this.topics,
  });

  final String title;
  final String anchor;
  final IconData icon;
  final String blurb;
  final List<GuideTopic> topics;
}

List<GuideTopic> get guideTopics =>
    [for (final section in guideSections) ...section.topics];

GuideTopic? guideTopicAt(String anchor) {
  for (final topic in guideTopics) {
    if (topic.anchor == anchor) return topic;
  }
  return null;
}

String? guideAnchorForScreen(DrawerScreen screen) => switch (screen) {
      DrawerScreen.timetables => 'your-timetables',
      DrawerScreen.calendar => 'calendar',
      DrawerScreen.freeSlotFinder => 'free-slots',
      DrawerScreen.cgpaCalculator => 'cgpa',
      DrawerScreen.examSeating => 'exam-seating',
      DrawerScreen.acadDrives => 'acad-drives',
      DrawerScreen.profChambers => 'professors',
      DrawerScreen.announcements => 'announcements',
      DrawerScreen.minors => 'minors',
      DrawerScreen.faq => 'academic-faq',
      DrawerScreen.bugReport => 'bug-reports',
      DrawerScreen.admin => null,
    };

String? guideAnchorForTool(AppTool tool) => switch (tool) {
      AppTool.sampleTimetables => 'sample-timetables',
      AppTool.trimTimetable => 'trim',
      AppTool.courseGuide => 'course-guide',
      AppTool.prerequisites => 'prerequisites',
      AppTool.electives => 'electives',
      AppTool.minors => 'minors',
      AppTool.courseHistory => 'course-history',
      AppTool.profChambers => 'professors',
      AppTool.compareTimetables => 'comparing',
      AppTool.credits => 'credits-page',
      AppTool.profile => 'profile',
      AppTool.guide => 'this-guide',
    };

final List<GuideSection> guideSections = [
  GuideSection(
    title: 'Getting started',
    anchor: 'start',
    icon: Icons.play_circle_outline,
    blurb: 'What Tabulr is, and how to find your way around it.',
    topics: [
      const GuideTopic(
        title: 'What Tabulr is',
        anchor: 'what-is-tabulr',
        icon: Icons.calendar_month_rounded,
        lead:
            'Tabulr is a free, open-source academic companion for BITS Pilani '
            'students across Pilani, Goa and Hyderabad, built by students. It '
            'started as a timetable maker — build a clash-free week from the '
            'real course booklet, or let it generate the options for you — and '
            'grew into most of what a degree needs around that: your CGPA and '
            'where it is heading, which minors and electives are still open, '
            'what you can register for next, your exam room and seat, and the '
            'past papers, notes and course updates other students share. It '
            'runs in a browser and as a desktop app, and works offline.',
        steps: [
          'Pick your campus, then build a timetable — or auto-generate one — from the course catalogue.',
          'Tabulr checks every clash for you, including exam dates months out.',
          'Plan your CGPA, minors and electives, share and export, all from the same data.',
          'Look up exam seats, professors, and crowd-sourced notes and announcements for your courses.',
        ],
        keywords: ['about', 'what is this', 'intro', 'overview', 'bits'],
      ),
      const GuideTopic(
        title: 'Signing in and picking a campus',
        anchor: 'signing-in',
        icon: Icons.login,
        lead:
            'You can browse without an account — the course history, minors, '
            'exam seating and the academic FAQ are all open. Signing in with '
            'Google is what lets Tabulr save your timetables, remember your '
            'CGPA record, and sync them to whatever device you open next. '
            'Your campus decides which course catalogue, exam schedule and '
            'academic calendar you see, so set it first.',
        steps: [
          'Tap Sign in and choose your Google account.',
          'Pick your campus from the selector at the top of the timetable list.',
          'Fill in your ID number and branch on the Profile page so exam seating and CDCs work without asking again.',
        ],
        keywords: ['google', 'log in', 'account', 'guest', 'campus', 'pilani', 'goa', 'hyderabad'],
      ),
      const GuideTopic(
        title: 'Finding your way around',
        anchor: 'finding-your-way',
        icon: Icons.explore_outlined,
        lead:
            'The sidebar on the left is every main screen. If you would rather '
            'not hunt for things, press Ctrl+K (Cmd+K on a Mac) anywhere in the '
            'app and start typing — the command palette jumps straight to any '
            'screen, tool or action, including the sections of this guide. Most '
            'screens also carry a small info button in the top bar that '
            'explains what that page can do.',
        steps: [
          'Sidebar — the main screens, in order.',
          'Ctrl+K / Cmd+K — search everything and jump.',
          'The info button in the top bar — what this page does.',
          'The first time you open a screen, a short tour points out the buttons that matter.',
        ],
        keywords: ['navigation', 'command palette', 'shortcut', 'search', 'sidebar', 'menu', 'tutorial', 'onboarding'],
      ),
    ],
  ),
  GuideSection(
    title: 'Building a timetable',
    anchor: 'build',
    icon: Icons.grid_view_rounded,
    blurb:
        'From an empty grid to a clash-free week you can share and export.',
    topics: [
      GuideTopic(
        title: 'Your timetables',
        anchor: 'your-timetables',
        icon: Icons.schedule,
        lead:
            'The TT Builder screen holds every timetable you have made. Keep as '
            'many as you like — one per plan you are weighing up is the normal '
            'way to use it. Cards can be renamed, duplicated, reordered and '
            'deleted, and a swipe does the common ones without opening a menu.',
        pageInfo: PageInfoHelper.timetableList,
        keywords: ['home', 'list', 'my timetables', 'duplicate', 'rename', 'delete', 'swipe'],
      ),
      GuideTopic(
        title: 'The editor',
        anchor: 'the-editor',
        icon: Icons.edit_calendar_outlined,
        lead:
            'Open a timetable and you get the week grid, the courses you have '
            'picked, and your exam dates. Everything you do here is undoable — '
            'add a course, change your mind, undo. Tabulr will not let you '
            'leave with unsaved changes without asking first.',
        pageInfo: PageInfoHelper.timetableCreator,
        visuals: [GuideVisual.weekGrid],
        keywords: ['grid', 'week', 'edit', 'undo', 'redo', 'save'],
      ),
      const GuideTopic(
        title: 'Grid, agenda and how it looks',
        anchor: 'views',
        icon: Icons.view_week_outlined,
        lead:
            'The same week, three ways. The vertical grid puts hours down the '
            'side and days across — the layout the printed timetable uses. The '
            'horizontal one flips it. Agenda drops the grid entirely and lists '
            'your day in order, which is what you want on a phone. You can also '
            'set how tall the rows are and which details each block shows, so a '
            'dense week stays readable.',
        visuals: [GuideVisual.agenda],
        steps: [
          'Layout — vertical, horizontal or agenda.',
          'Size — compact through extra large, or "fit" to get the whole week on one screen.',
          'Fields — hide the room or the instructor when blocks get crowded.',
        ],
        keywords: ['layout', 'vertical', 'horizontal', 'agenda', 'size', 'compact', 'fit', 'display', 'mobile'],
      ),
      GuideTopic(
        title: 'Adding courses',
        anchor: 'adding-courses',
        icon: Icons.add_circle_outline,
        lead:
            'Add / Swap opens the full course catalogue for your campus. Search '
            'by code or by name, open a course, and pick the lecture, tutorial '
            'and practical sections you want. Sections that would clash with '
            'what you already have are marked before you pick them, so you are '
            'not fixing a mistake afterwards.',
        steps: [
          'Tap Add / Swap in the editor.',
          'Search for the course code — CS F211 — or part of its title.',
          'Pick one section of each type the course requires (L, T, P).',
          'Anything left half-picked is flagged on the grid until you finish it.',
        ],
        visuals: [GuideVisual.courseCards],
        pageInfo: PageInfoHelper.addSwap,
        keywords: ['add', 'course', 'section', 'catalog', 'catalogue', 'search', 'lecture', 'tutorial', 'practical', 'lab'],
      ),
      GuideTopic(
        title: 'Swapping a section',
        anchor: 'swapping-sections',
        icon: Icons.swap_horiz,
        lead:
            'When a section closes during registration you rarely want to '
            'rebuild the week — you want that one section replaced. Quick '
            'Replace shows only the alternatives for that course, marks which '
            'ones fit your current week, and swaps it in place. The rest of '
            'your timetable is untouched.',
        steps: [
          'Tap the block you want to change, then Replace.',
          'Fitting alternatives are listed first; clashing ones say what they collide with.',
          'Pick one and it swaps in — undo if it was not what you meant.',
        ],
        pageInfo: PageInfoHelper.quickReplace,
        keywords: ['swap', 'replace', 'section full', 'closed', 'change section', 'quick replace'],
      ),
      const GuideTopic(
        title: 'Clashes',
        anchor: 'clashes',
        icon: Icons.warning_amber_rounded,
        lead:
            'Two kinds of collision matter and Tabulr checks both. A class '
            'clash is two sections in the same hour on the same day — that one '
            'is obvious the moment you see the grid. An exam clash is two '
            'papers in the same slot months later, which is the one that '
            'actually catches people out. Tabulr also stops you picking two '
            'sections of the same course, and warns when a compre and a class '
            'collide.',
        visuals: [GuideVisual.clashes],
        steps: [
          'Red — a real conflict; the combination will not work.',
          'Amber — worth knowing about, but you can proceed.',
          'The banner stays collapsed to one line so the grid keeps its space; tap it for the detail.',
        ],
        keywords: ['clash', 'conflict', 'overlap', 'exam clash', 'midsem', 'compre', 'same course', 'error', 'warning'],
      ),
      const GuideTopic(
        title: 'Credits and credit hours',
        anchor: 'credits',
        icon: Icons.schedule_outlined,
        lead:
            'Which number you count in depends on when you joined. The 2026 '
            'batch onwards registers in credit hours; the 2025 batch and '
            'earlier register in units. A timetable counts one way or the '
            'other — never both — so pick yours with the toggle and Tabulr '
            'will only offer courses that are on offer that way. It also '
            'keeps a running total against the semester cap, so you know when '
            'you are overloaded before registration tells you.',
        visuals: [GuideVisual.coursesTab],
        keywords: ['credits', 'credit hours', 'units', '2026 batch', 'cap', 'overload', 'contact hours'],
      ),
      const GuideTopic(
        title: 'Reading the week at a glance',
        anchor: 'stats',
        icon: Icons.insights_outlined,
        lead:
            'TT Stats turns your timetable into the things you actually want '
            'to know: how many contact hours you are carrying, which day is '
            'brutal, whether you have a free day, how long your longest '
            'back-to-back run is, and whether your exams are bunched. It is '
            'the fastest way to compare two plans that both look fine on the '
            'grid.',
        visuals: [GuideVisual.stats, GuideVisual.weeklyLoad],
        keywords: ['stats', 'insights', 'load', 'free day', 'contact hours', 'gaps', 'earliest'],
      ),
      GuideTopic(
        title: 'Auto-generate',
        anchor: 'auto-generate',
        icon: Icons.auto_awesome_mosaic,
        lead:
            'Tell Tabulr which courses you need and what a good week looks like '
            'to you, and it builds the options. You can cap hours per day, '
            'block out mornings or evenings, avoid particular instructors or '
            'lab slots, and say which of those matter most. Results come back '
            'ranked, and none of them clash — that part is not negotiable.',
        steps: [
          'Pick the courses you must take.',
          'Set your constraints: max hours a day, slots to avoid, instructors to prefer or avoid.',
          'Say what matters most — a free day, late starts, short days.',
          'Generate, then flip through the ranked options and keep one.',
        ],
        visuals: [GuideVisual.generatorResult, GuideVisual.rankingImportance],
        pageInfo: PageInfoHelper.generator,
        keywords: ['generate', 'auto', 'generator', 'constraints', 'optimise', 'optimize', 'ranking', 'avoid', 'free day'],
      ),
      GuideTopic(
        title: 'Trim to fit',
        anchor: 'trim',
        icon: Icons.content_cut,
        lead:
            'For when you have added more than you can register for. Trim to '
            'Fit takes an overloaded timetable and works out which courses to '
            'drop to get under the cap, keeping the ones you mark as '
            'non-negotiable and losing as little as it can.',
        pageInfo: PageInfoHelper.trimTimetable,
        keywords: ['trim', 'drop', 'overload', 'too many credits', 'cut', 'fit'],
      ),
      GuideTopic(
        title: 'Sample timetables',
        anchor: 'sample-timetables',
        icon: Icons.calendar_view_week,
        lead:
            'First semester and not sure what you are supposed to be taking? '
            'Sample timetables are ready-made weeks covering your branch\'s '
            'compulsory courses. Load one and edit from there instead of '
            'starting from an empty grid.',
        pageInfo: PageInfoHelper.sampleTimetables,
        keywords: ['sample', 'template', 'first year', 'cdc', 'starter', 'preset'],
      ),
      const GuideTopic(
        title: 'Sharing and importing',
        anchor: 'sharing',
        icon: Icons.share,
        lead:
            'Every timetable can be turned into a short code and a link. Send '
            'either to a friend and they get a copy of your week in one tap — '
            'they can edit theirs without touching yours. Pasting a link or a '
            'bare code both work, so it does not matter which one they sent.',
        steps: [
          'Share from the editor to get a link like tabulr.net/s/ABC123.',
          'On the other end, Import and paste the link or the code.',
          'The copy is theirs — later edits on either side stay separate.',
        ],
        keywords: ['share', 'code', 'link', 'import', 'friend', 'send', 'copy'],
      ),
      const GuideTopic(
        title: 'Exporting',
        anchor: 'exporting',
        icon: Icons.download,
        lead:
            'Three ways out. A PNG image of the grid, with your exam dates '
            'underneath, for sending or printing. An .ics calendar file that '
            'drops your whole semester into Google Calendar or Outlook, '
            'repeating weekly, with reminders. And a .tt file, which is a full '
            'backup you can import back into Tabulr later.',
        steps: [
          'PNG — the grid as a picture, exam table included.',
          'ICS — your classes as real calendar events with reminders.',
          'TT — a backup file, restorable into any Tabulr account.',
        ],
        keywords: ['export', 'png', 'image', 'ics', 'calendar', 'google calendar', 'outlook', 'backup', 'tt file', 'download', 'print'],
      ),
      GuideTopic(
        title: 'Comparing timetables',
        anchor: 'comparing',
        icon: Icons.compare,
        lead:
            'Put two plans side by side and the differences stop being '
            'abstract. Compare shows both weeks together, so a Tuesday that '
            'looks fine on its own and terrible next to the alternative is '
            'obvious immediately.',
        pageInfo: PageInfoHelper.timetableComparison,
        keywords: ['compare', 'side by side', 'versus', 'difference', 'two timetables'],
      ),
      GuideTopic(
        title: 'Finding free time with friends',
        anchor: 'free-slots',
        icon: Icons.group,
        lead:
            'Add your timetable and your friends\' — by share code, if they '
            'are not on your account — and Tabulr shows the hours nobody has '
            'class. Tap a free slot to turn it into a shared event.',
        pageInfo: PageInfoHelper.freeSlotFinder,
        keywords: ['free slot', 'common', 'friends', 'group', 'meet', 'free time'],
      ),
      GuideTopic(
        title: 'Archiving old semesters',
        anchor: 'archive',
        icon: Icons.inventory_2_outlined,
        lead:
            'When a semester ends you do not want its timetables in the way, '
            'but you probably do not want them gone either. Archiving moves '
            'them out of the main list and keeps them readable, which also '
            'means your CGPA record can still pull courses out of them.',
        pageInfo: PageInfoHelper.archivedTimetables,
        keywords: ['archive', 'old', 'past semester', 'previous', 'restore'],
      ),
    ],
  ),
  GuideSection(
    title: 'Planning your degree',
    anchor: 'plan',
    icon: Icons.school_outlined,
    blurb: 'Grades, electives, minors, and what you are allowed to take next.',
    topics: [
      GuideTopic(
        title: 'CGPA calculator',
        anchor: 'cgpa',
        icon: Icons.calculate,
        lead:
            'Keep every semester\'s courses and grades in one place and Tabulr '
            'works out your SGPA and CGPA the way the regulations do — '
            'including what happens when you repeat a course. You do not have '
            'to type it all in: pull courses from a timetable, load your '
            'branch\'s compulsory courses automatically, or import a '
            'performance sheet PDF.',
        pageInfo: PageInfoHelper.cgpaCalculator,
        keywords: ['cgpa', 'sgpa', 'gpa', 'grades', 'marks', 'performance sheet', 'repeat', 'cdc'],
      ),
      GuideTopic(
        title: 'Grade planner',
        anchor: 'grade-planner',
        icon: Icons.flag_outlined,
        lead:
            'Work backwards from where you want to be. Give the planner a '
            'target CGPA and it tells you what this semester has to look like '
            'to get there — and says plainly when the target is out of reach, '
            'which is worth knowing early.',
        pageInfo: PageInfoHelper.gradePlanner,
        keywords: ['target', 'goal', 'what grades do i need', 'planner', 'required'],
      ),
      GuideTopic(
        title: 'CG booster',
        anchor: 'cg-booster',
        icon: Icons.bolt_outlined,
        lead:
            'Not every course moves your CGPA by the same amount — a 5-unit '
            'course pulls far harder than a 2-unit one. CG Booster ranks your '
            'courses by how much one grade step in each would actually change '
            'your standing, so your effort goes where it counts.',
        pageInfo: PageInfoHelper.cgBooster,
        keywords: ['booster', 'impact', 'improve cgpa', 'which course', 'effort'],
      ),
      GuideTopic(
        title: 'CGPA trajectory',
        anchor: 'trajectory',
        icon: Icons.trending_up,
        lead:
            'Your semester-by-semester standing as a line, with each '
            'semester\'s SGPA against the cumulative CGPA it produced. Set a '
            'target and it draws that too, so you can see whether you are '
            'closing the gap or the gap is closing on you.',
        visuals: [GuideVisual.cgpaTrajectory],
        pageInfo: PageInfoHelper.cgpaTrajectory,
        keywords: ['trajectory', 'chart', 'graph', 'projection', 'history', 'trend'],
      ),
      GuideTopic(
        title: 'Course guide',
        anchor: 'course-guide',
        icon: Icons.menu_book,
        lead:
            'What your branch is supposed to take, semester by semester — the '
            'compulsory disciplinary courses and the electives that count. '
            'Useful when you are deciding what to register for and do not want '
            'to read the bulletin cover to cover.',
        pageInfo: PageInfoHelper.courseGuide,
        keywords: ['cdc', 'course guide', 'branch', 'curriculum', 'what should i take'],
      ),
      GuideTopic(
        title: 'Electives',
        anchor: 'electives',
        icon: Icons.school,
        lead:
            'Discipline, humanities and open electives in one browsable list '
            'instead of three documents. If you have filled in your CGPA '
            'record, courses you have already taken are marked, so you are not '
            'shortlisting something you passed last year.',
        pageInfo: PageInfoHelper.electives,
        keywords: ['elective', 'del', 'hel', 'oel', 'humanities', 'open elective', 'discipline elective'],
      ),
      GuideTopic(
        title: 'Minors',
        anchor: 'minors',
        icon: Icons.workspace_premium_outlined,
        lead:
            'Every minor programme on offer, the courses each one requires, '
            'and how far along you already are. Tabulr reads your completed '
            'courses out of your CGPA record and shows what is left, so '
            '"could I finish this one?" has an actual answer.',
        pageInfo: PageInfoHelper.minors,
        keywords: ['minor', 'programme', 'program', 'requirements', 'progress'],
      ),
      GuideTopic(
        title: 'Prerequisites',
        anchor: 'prerequisites',
        icon: Icons.account_tree,
        lead:
            'What you need before you can take a course, and what taking it '
            'opens up. Some courses want all of a set, some want any one of '
            'several — Tabulr shows which, and marks the ones you have already '
            'cleared.',
        pageInfo: PageInfoHelper.prerequisites,
        keywords: ['prerequisite', 'prereq', 'chain', 'requirement', 'before', 'unlock'],
      ),
      GuideTopic(
        title: 'Course history',
        anchor: 'course-history',
        icon: Icons.history_toggle_off,
        lead:
            'Which courses actually ran in past semesters, who taught them, '
            'and how long it has been since one was last offered. The answer '
            'to "is this elective coming back?" — a course that has not run in '
            'three semesters probably is not worth waiting for.',
        pageInfo: PageInfoHelper.courseHistory,
        keywords: ['history', 'past', 'offered', 'last offered', 'who taught', 'instructor in charge', 'ic'],
      ),
    ],
  ),
  GuideSection(
    title: 'Around campus',
    anchor: 'campus',
    icon: Icons.location_city_outlined,
    blurb: 'Exams, calendars, professors, and what your classmates know.',
    topics: [
      GuideTopic(
        title: 'Calendar',
        anchor: 'calendar',
        icon: Icons.calendar_month,
        lead:
            'Your week as a real calendar, with your classes, your exams and '
            'anything else you add. Cancelled class? Scrap that slot for the '
            'week and it disappears without touching your timetable. The whole '
            'semester\'s holidays and deadlines are one tap away.',
        pageInfo: PageInfoHelper.calendar,
        visuals: [GuideVisual.academicCalendar],
        keywords: ['calendar', 'week', 'events', 'holiday', 'scrap', 'cancel', 'academic calendar'],
      ),
      GuideTopic(
        title: 'Exam seating',
        anchor: 'exam-seating',
        icon: Icons.event_seat,
        lead:
            'Your room and seat number for midsems and compres, looked up by '
            'ID. Pull your courses straight from a timetable rather than '
            'typing them, save the list, and it is there next exam season. '
            'Combined-exam codes — where two course codes sit one paper — are '
            'handled.',
        pageInfo: PageInfoHelper.examSeating,
        visuals: [GuideVisual.examDates, GuideVisual.examTimeline],
        keywords: ['exam', 'seat', 'room', 'seating', 'midsem', 'compre', 'id number', 'venue'],
      ),
      GuideTopic(
        title: 'Prof chambers',
        anchor: 'professors',
        icon: Icons.person_search,
        lead:
            'Where a professor sits, how to reach them, and whether they are '
            'in class right now. Worth checking before you walk across campus '
            'to a closed door.',
        pageInfo: PageInfoHelper.profChambers,
        keywords: ['professor', 'chamber', 'cabin', 'office', 'contact', 'email', 'faculty', 'where'],
      ),
      GuideTopic(
        title: 'Announcements',
        anchor: 'announcements',
        icon: Icons.campaign,
        lead:
            'The things that never make it to a notice board — an extra class, '
            'a moved deadline, a cancelled lab — posted by the students in '
            'your course. Anyone can post, everyone can vote, and wrong '
            'information gets flagged and falls away.',
        pageInfo: PageInfoHelper.announcements,
        keywords: ['announcement', 'notice', 'extra class', 'cancelled', 'update', 'vote', 'flag'],
      ),
      GuideTopic(
        title: 'Acad drives',
        anchor: 'acad-drives',
        icon: Icons.folder_shared,
        lead:
            'Past papers, notes and slides, organised by course and shared by '
            'students. If you have something useful, submitting it takes a '
            'file or a link and about ten seconds.',
        pageInfo: PageInfoHelper.acadDrives,
        keywords: ['drive', 'notes', 'past papers', 'resources', 'material', 'slides', 'upload', 'pyq'],
      ),
      GuideTopic(
        title: 'Academic FAQ',
        anchor: 'academic-faq',
        icon: Icons.help_outline,
        lead:
            'Straight answers to the rules students actually ask about — what '
            'each grade is worth, how CGPA is really calculated, attendance, '
            'registration, Practice School, what happens if you fail. Every '
            'answer cites the clause it comes from, so you can check it '
            'yourself when it matters.',
        pageInfo: PageInfoHelper.academicFaq,
        keywords: ['faq', 'rules', 'regulations', 'attendance', 'practice school', 'ps', 'bulletin', 'clause'],
      ),
    ],
  ),
  GuideSection(
    title: 'Your account and the app',
    anchor: 'app',
    icon: Icons.tune,
    blurb: 'Settings, themes, where it runs, and how to tell us it broke.',
    topics: [
      GuideTopic(
        title: 'Profile',
        anchor: 'profile',
        icon: Icons.badge_outlined,
        lead:
            'Your ID number, branch and default semester. Filling these in '
            'once means exam seating knows who to look up, the CGPA calculator '
            'knows which compulsory courses to load, and the course guide '
            'opens on your branch.',
        pageInfo: PageInfoHelper.profile,
        keywords: ['profile', 'id number', 'branch', 'settings', 'defaults', 'f number'],
      ),
      const GuideTopic(
        title: 'Themes',
        anchor: 'themes',
        icon: Icons.palette_outlined,
        lead:
            'Nine themes — GitHub Dark, Dracula, Nord, Tokyo Night, Gruvbox, '
            'Catppuccin, Solarized, Arctic Frost and a true-black AMOLED — '
            'each in light, dark, or following your system. Every screen, '
            'chart and timetable colour adapts, including the components on '
            'this page.',
        keywords: ['theme', 'dark mode', 'light mode', 'colours', 'colors', 'amoled', 'dracula', 'appearance'],
      ),
      const GuideTopic(
        title: 'Where it runs, and offline',
        anchor: 'offline-and-platforms',
        icon: Icons.devices,
        lead:
            'Tabulr runs in a browser and as a proper app on macOS, Windows '
            'and Linux, signed in to the same account everywhere. Your '
            'timetables are cached on the device, so a bad campus connection '
            'means a slow sync, not a blank screen.',
        keywords: ['offline', 'desktop', 'mac', 'windows', 'linux', 'pwa', 'install', 'sync', 'cache'],
      ),
      GuideTopic(
        title: 'Reporting a bug',
        anchor: 'bug-reports',
        icon: Icons.bug_report_outlined,
        lead:
            'If something is wrong — a broken screen, or course data that does '
            'not match the booklet — report it in the app. You can follow the '
            'thread and see when it is fixed, and reporting things that turn '
            'out to be real builds your contributor standing.',
        steps: [
          'Describe what you did and what happened instead.',
          'Data problems are worth reporting too — wrong sections, wrong exam dates.',
          'Track the report in the same screen; you will see replies and the status change.',
        ],
        visuals: [GuideVisual.bugStatuses],
        pageInfo: PageInfoHelper.bugReport,
        keywords: ['bug', 'report', 'broken', 'wrong data', 'issue', 'feedback', 'problem'],
      ),
      const GuideTopic(
        title: 'Credits',
        anchor: 'credits-page',
        icon: Icons.info_outline,
        lead:
            'Who built and maintains Tabulr, everyone who has contributed on '
            'GitHub, and the admins who keep the course data current. It is '
            'open source — the repository is linked from there.',
        keywords: ['credits', 'contributors', 'admins', 'github', 'open source', 'who made this', 'license'],
      ),
      const GuideTopic(
        title: 'This guide',
        anchor: 'this-guide',
        icon: Icons.auto_stories_outlined,
        lead:
            'Everything Tabulr does, with the real components rendered inline '
            'so you are looking at the app rather than a description of it. '
            'Search the whole thing from the box at the top, jump to any '
            'section from the list, and copy a link to a section to send '
            'someone straight to it.',
        keywords: ['guide', 'help', 'manual', 'documentation', 'how to', 'tutorial'],
      ),
    ],
  ),
];
