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
        (pageInfo?.features.any(
              (f) => '${f.label} ${f.description}'.toLowerCase().contains(q),
            ) ??
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

List<GuideTopic> get guideTopics => [
  for (final section in guideSections) ...section.topics,
];

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
  AppTool.degreeAudit => 'degree-audit',
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
            "Tabulr is a free, open-source academic companion for BITS Pilani students across Pilani, Goa and Hyderabad. Build a clash-free timetable from the course catalogue, plan your academic record, and find exam rooms, resources and course updates. Some previously loaded data is cached locally; signing in, fresh data, sharing, resources and community features need a connection.",
        steps: [
          'Pick your campus, then build a timetable — or auto-generate one — from the course catalogue.',
          'Tabulr checks every clash for you, including exam dates months out.',
          'Plan your CGPA, minors and electives, share and export, all from the same data.',
          'Look up exam rooms, professors, and crowd-sourced notes and announcements for your courses.',
        ],
        keywords: ['about', 'what is this', 'intro', 'overview', 'bits'],
      ),
      const GuideTopic(
        title: 'Signing in and picking a campus',
        anchor: 'signing-in',
        icon: Icons.login,
        lead:
            "Public lookups such as Course History, Minors, Exam Seating and Academic Rules are available without an account. Sign in with Google to save and sync your timetables and academic record. Guest timetable work is temporary and can be cleared when the browser session closes, so export anything you want to keep. Choose the correct campus before planning.",
        steps: [
          "Sign in, then choose your campus from the selector on My timetables.",
          "Set your ID, branch and semester in Profile to prefill planning tools.",
          "Keep an exported .tt backup of guest work; do not treat the guest editor as cloud storage.",
        ],
        keywords: [
          'google',
          'log in',
          'account',
          'guest',
          'campus',
          'pilani',
          'goa',
          'hyderabad',
        ],
      ),
      const GuideTopic(
        title: 'Finding your way around',
        anchor: 'finding-your-way',
        icon: Icons.explore_outlined,
        lead:
            "The app is organised into Timetables, Degree, Calendar, Explore and Exams. The tabs within each workspace keep related tools together, without mixing their data or changing what they do. Help & support lives in the desktop sidebar and the mobile More menu. Search with Ctrl+K or Cmd+K to jump to a feature, action or guide topic.",
        steps: [
          "Timetables: your saved and archived weeks, plus generated samples. Compare remains a timetable action.",
          "Degree: Audit, Grades & targets, Curriculum, Electives and Minors.",
          "Calendar: My week, Availability and, for eligible Hyderabad accounts, Updates.",
          "Explore: Acad Drives, Prerequisites, Faculty and Course history. Exams has its own workspace.",
          "Help & support: Using Tabulr, Academic rules, Report a problem and About.",
          "Page info opens a short explanation and a link to its full guide topic. Guided tours are available on selected screens, not every page.",
        ],
        keywords: [
          'navigation',
          'command palette',
          'shortcut',
          'search',
          'sidebar',
          'menu',
          'tutorial',
          'onboarding',
        ],
      ),
    ],
  ),
  GuideSection(
    title: 'Building a timetable',
    anchor: 'build',
    icon: Icons.grid_view_rounded,
    blurb: 'From an empty grid to a clash-free week you can share and export.',
    topics: [
      GuideTopic(
        title: 'Your timetables',
        anchor: 'your-timetables',
        icon: Icons.schedule,
        lead:
            "My timetables is your plan library. Each card surfaces its courses, credit load, last update and workload insight before you open the editor. New, Import and Compare sit beside the list heading; campus and sorting stay in the slim toolbar below. Rename, duplicate or delete from a card menu or swipe shortcut. Choose Custom Order to reveal drag handles. Past-semester plans remain grouped under archives.",
        pageInfo: PageInfoHelper.timetableList,
        keywords: [
          'home',
          'list',
          'my timetables',
          'duplicate',
          'rename',
          'delete',
          'swipe',
        ],
      ),
      GuideTopic(
        title: 'The editor',
        anchor: 'the-editor',
        icon: Icons.edit_calendar_outlined,
        lead:
            'The editor is one scheduling workspace: the course browser sits '
            'beside the timetable on desktop and opens from the bottom dock on '
            'mobile. Use Catalog to find sections; My Plan keeps selected '
            'courses and their exam schedule together. Save state, undo and '
            'redo live in the editor header, while view controls stay directly '
            'above the grid. Tabulr asks before leaving with unsaved changes.',
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
        keywords: [
          'layout',
          'vertical',
          'horizontal',
          'agenda',
          'size',
          'compact',
          'fit',
          'display',
          'mobile',
        ],
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
        keywords: [
          'add',
          'course',
          'section',
          'catalog',
          'catalogue',
          'search',
          'lecture',
          'tutorial',
          'practical',
          'lab',
        ],
      ),
      GuideTopic(
        title: 'Swapping a section',
        anchor: 'swapping-sections',
        icon: Icons.swap_horiz,
        lead:
            "Quick Replace can change a course or find new sections when registration closes your preferred option. A direct swap keeps the other courses unchanged. Repair can instead propose a clash-free plan that moves up to two other courses; protected courses are not moved. Review the complete preview before applying it.",
        steps: [
          "Open Replace for the affected course and review alternatives.",
          "For a repair, choose what to preserve: timing, instructors or free days, and protect courses you do not want moved.",
          "Compare the ranked plans and inspect every changed course before applying. Repairs are bounded, so no result is not proof that no possible timetable exists.",
          "Apply the plan to the editor, then save. Undo is available for the change.",
        ],
        pageInfo: PageInfoHelper.quickReplace,
        keywords: [
          'swap',
          'replace',
          'section full',
          'closed',
          'change section',
          'quick replace',
        ],
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
        keywords: [
          'clash',
          'conflict',
          'overlap',
          'exam clash',
          'midsem',
          'compre',
          'same course',
          'error',
          'warning',
        ],
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
        keywords: [
          'credits',
          'credit hours',
          'units',
          '2026 batch',
          'cap',
          'overload',
          'contact hours',
        ],
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
        keywords: [
          'stats',
          'insights',
          'load',
          'free day',
          'contact hours',
          'gaps',
          'earliest',
        ],
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
          'Open Why this rank to inspect the explanation, or Protect strength to preserve an advantage while refining.',
          'If hard constraints produce no matches, review the offered relaxation actions. The app only relaxes what you choose.',
        ],
        visuals: [GuideVisual.generatorResult, GuideVisual.rankingImportance],
        pageInfo: PageInfoHelper.generator,
        keywords: [
          'generate',
          'auto',
          'generator',
          'constraints',
          'optimise',
          'optimize',
          'ranking',
          'avoid',
          'free day',
        ],
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
        keywords: [
          'trim',
          'drop',
          'overload',
          'too many credits',
          'cut',
          'fit',
        ],
      ),
      GuideTopic(
        title: 'Sample timetables',
        anchor: 'sample-timetables',
        icon: Icons.calendar_view_week,
        lead:
            "Sample Timetables starts with CDC selection directly on the page: choose your branch, semester and optional second branch, then answer any core-course choices. Tabulr generates and ranks clash-free options from the published package; these are generated results, not fixed templates. After generation, Change reopens a prefilled dialog so you can try another package without repeating the setup from memory.",
        steps: [
          'Choose the branch and semester in the setup card, then generate samples.',
          'If a CDC slot offers alternatives, select the course you actually take.',
          'Swipe through the ranked results and open Use this sample on the one you want.',
          'Add it to the current editor, save it as a new timetable, or explicitly replace a saved plan.',
          'Use Change after generation to reopen the current CDC selection in a dialog.',
        ],
        pageInfo: PageInfoHelper.sampleTimetables,
        keywords: [
          'sample',
          'template',
          'first year',
          'cdc',
          'starter',
          'preset',
          'change branch',
          'ranked timetable',
        ],
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
        keywords: [
          'export',
          'png',
          'image',
          'ics',
          'calendar',
          'google calendar',
          'outlook',
          'backup',
          'tt file',
          'download',
          'print',
        ],
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
        keywords: [
          'compare',
          'side by side',
          'versus',
          'difference',
          'two timetables',
        ],
      ),
      GuideTopic(
        title: 'Finding free time with friends',
        anchor: 'free-slots',
        icon: Icons.group,
        lead:
            "Availability compares busy slots from saved timetables or imported share codes to find common free time. Choose the relevant sources and a free interval. Saving an event adds it to your own Calendar; it does not send an invitation or create a shared calendar for everyone.",
        pageInfo: PageInfoHelper.freeSlotFinder,
        keywords: [
          'free slot',
          'common',
          'friends',
          'group',
          'meet',
          'free time',
        ],
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
        keywords: ['archive', 'old', 'past semester', 'previous', 'read only'],
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
        title: 'Degree audit and bottlenecks',
        anchor: 'degree-audit',
        icon: Icons.fact_check_outlined,
        lead:
            'Degree Audit compares your saved academic record with the core requirements for your profile branch. It also uses prerequisite and historical offering data to highlight potential bottlenecks. Elective completions are counted, but elective graduation targets are not certified; missing reference data limits the analysis.',
        pageInfo: PageInfoHelper.degreeAudit,
        steps: [
          'Set your branch in Profile and save your grades in Grades & targets.',
          'Open Degree > Audit to review completed and remaining core requirements.',
          'Review prerequisite bottlenecks and offering gaps as planning signals, then confirm requirements with your department.',
        ],
        keywords: [
          'degree',
          'audit',
          'bottleneck',
          'graduation',
          'core',
          'requirements',
        ],
      ),
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
        keywords: [
          'cgpa',
          'sgpa',
          'gpa',
          'grades',
          'marks',
          'performance sheet',
          'repeat',
          'cdc',
        ],
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
        keywords: [
          'target',
          'goal',
          'what grades do i need',
          'planner',
          'required',
        ],
      ),
      GuideTopic(
        title: 'CG booster',
        anchor: 'cg-booster',
        icon: Icons.bolt_outlined,
        lead:
            "CG Booster explores retake combinations that could reach your target CGPA within a maximum credit budget. It works from the effective course attempts in your academic record, rather than ranking the effect of a single grade step. Select candidate courses and compare the proposed combinations; it is a planning estimate, not registration approval.",
        steps: [
          "Open Grades & targets, then Retakes.",
          "Set a target CGPA and maximum retake credits, then select candidate courses.",
          "Compare the ranked combinations and projected CGPA. Confirm retake eligibility separately.",
        ],
        pageInfo: PageInfoHelper.cgBooster,
        keywords: [
          'booster',
          'impact',
          'improve cgpa',
          'which course',
          'effort',
        ],
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
        keywords: [
          'trajectory',
          'chart',
          'graph',
          'projection',
          'history',
          'trend',
        ],
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
        keywords: [
          'cdc',
          'course guide',
          'branch',
          'curriculum',
          'what should i take',
        ],
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
        keywords: [
          'elective',
          'del',
          'hel',
          'oel',
          'humanities',
          'open elective',
          'discipline elective',
        ],
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
        keywords: [
          'prerequisite',
          'prereq',
          'chain',
          'requirement',
          'before',
          'unlock',
        ],
      ),
      GuideTopic(
        title: 'Course History',
        anchor: 'course-history',
        icon: Icons.history_toggle_off,
        lead:
            'Which courses actually ran in past semesters, who taught them, '
            'and how long it has been since one was last offered. The answer '
            'to "is this elective coming back?" — a course that has not run in '
            'three semesters probably is not worth waiting for.',
        pageInfo: PageInfoHelper.courseHistory,
        keywords: [
          'history',
          'past',
          'offered',
          'last offered',
          'who taught',
          'instructor in charge',
          'ic',
        ],
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
        keywords: [
          'calendar',
          'week',
          'events',
          'holiday',
          'scrap',
          'cancel',
          'academic calendar',
        ],
      ),
      GuideTopic(
        title: 'Exam seating',
        anchor: 'exam-seating',
        icon: Icons.event_seat,
        lead:
            'Build a personal exam plan, enter your student ID once, and Tabulr checks every selected course for its assigned room and published ID range. Search for courses or import them from a saved timetable; the plan stays chronological and shows dates, sessions and countdowns. Save the course list and ID for your next visit. Combined-exam codes, where two courses share one paper, are handled.',
        steps: [
          'Search by course code or title, or import the relevant courses from a saved timetable.',
          'Enter your student ID and choose Find rooms to look up every selected exam at once.',
          'Read the room and ID range on each exam card; No room found means the ID is absent from that course seating list.',
          'Save to keep the selected courses and ID, and refresh when a newer seating list is published.',
        ],
        pageInfo: PageInfoHelper.examSeating,
        visuals: [GuideVisual.examDates, GuideVisual.examTimeline],
        keywords: [
          'exam',
          'seat',
          'room',
          'seating',
          'midsem',
          'compre',
          'id number',
          'id range',
          'venue',
          'find rooms',
        ],
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
        keywords: [
          'professor',
          'chamber',
          'cabin',
          'office',
          'contact',
          'email',
          'faculty',
          'where',
        ],
      ),
      GuideTopic(
        title: 'Announcements',
        anchor: 'announcements',
        icon: Icons.campaign,
        lead:
            "Updates is a course-announcement feed shown to eligible signed-in Hyderabad users. Posting and voting have account restrictions, and suspended contributors cannot post. Entries can include sources, confidence and corrections; confirmations and flags help assess them, but an announcement is not automatically an official notice.",
        steps: [
          "Choose the timetable whose courses you want to follow; its campus and course codes determine the feed.",
          "Read the source and verification information before relying on an update.",
          "Confirm, deny, flag or propose a correction where the available actions allow it. Posting and community actions require an eligible account.",
        ],
        pageInfo: PageInfoHelper.announcements,
        keywords: [
          'announcement',
          'notice',
          'extra class',
          'cancelled',
          'update',
          'vote',
          'flag',
        ],
      ),
      GuideTopic(
        title: 'Acad drives',
        anchor: 'acad-drives',
        icon: Icons.folder_shared,
        lead:
            "Acad Drives is a searchable resource library for past papers, slides and notes. Star courses, bookmark individual files and use the enrolled-course section to find material related to saved timetables. On desktop, selecting a course keeps the course navigator beside its drives and folders; phones use a focused drill-down view. Submit a Google Drive link to suggest a resource; there is no direct file-upload form. Downloads and fresh listings require a connection.",
        steps: [
          "Search by course code or title, then open a course to browse its source drives and folders.",
          "Star courses and bookmark files to return to them. Enrolled courses are derived from your saved timetables.",
          "Open or download individual files. Bulk ZIP download is available on web and can be cancelled.",
          "Submit a Drive link with the appropriate course information when contributing.",
        ],
        pageInfo: PageInfoHelper.acadDrives,
        keywords: [
          'drive',
          'notes',
          'past papers',
          'resources',
          'material',
          'slides',
          'upload',
          'pyq',
        ],
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
        keywords: [
          'faq',
          'rules',
          'regulations',
          'attendance',
          'practice school',
          'ps',
          'bulletin',
          'clause',
        ],
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
        keywords: [
          'profile',
          'id number',
          'branch',
          'settings',
          'defaults',
          'f number',
        ],
      ),
      const GuideTopic(
        title: 'Themes',
        anchor: 'themes',
        icon: Icons.palette_outlined,
        lead:
            'Nine themes — GitHub, Dracula, Nord, Tokyo Night, Gruvbox, '
            'Catppuccin, Solarized, Arctic Frost and a true-black AMOLED — '
            'each in light, dark, or following your system. Preview cards show '
            'the real surfaces, timetable colours, inputs and actions before '
            'you choose; component shape and depth adapt with the palette too.',
        steps: [
          'Open Appearance from the sidebar or search Change Theme with Cmd/Ctrl K.',
          'Choose Light, Dark or System at the top. System follows the current device setting.',
          'Select a preview card to apply and save that palette to your account.',
        ],
        keywords: [
          'theme',
          'dark mode',
          'light mode',
          'colours',
          'colors',
          'amoled',
          'dracula',
          'appearance',
        ],
      ),
      const GuideTopic(
        title: 'Where it runs, and offline',
        anchor: 'offline-and-platforms',
        icon: Icons.devices,
        lead:
            "Previously loaded timetables and some reference data are cached on your device. This can help on a poor connection, but offline availability depends on what has already been loaded and is not a promise that every feature works offline. Authentication, fresh catalogues, sharing, resource downloads and community updates need network access.",
        keywords: [
          'offline',
          'desktop',
          'mac',
          'windows',
          'linux',
          'pwa',
          'install',
          'sync',
          'cache',
        ],
      ),
      GuideTopic(
        title: 'Reporting a bug',
        anchor: 'bug-reports',
        icon: Icons.bug_report_outlined,
        lead:
            "Report broken screens or course data that does not match the booklet from Help & support. Sign in to submit a report and follow its replies and status in the same place. Bug reports do not award contributor reputation.",
        steps: [
          "Describe what you did, what happened and what you expected; include the relevant campus and course when reporting data.",
          "Avoid including passwords or other sensitive account information.",
          "Return to Report a problem to read replies and status changes.",
        ],
        visuals: [GuideVisual.bugStatuses],
        pageInfo: PageInfoHelper.bugReport,
        keywords: [
          'bug',
          'report',
          'broken',
          'wrong data',
          'issue',
          'feedback',
          'problem',
        ],
      ),
      const GuideTopic(
        title: 'Credits',
        anchor: 'credits-page',
        icon: Icons.info_outline,
        lead:
            'Who built and maintains Tabulr, everyone who has contributed on '
            'GitHub, and the admins who keep the course data current. It is '
            'open source — the repository is linked from there.',
        keywords: [
          'credits',
          'contributors',
          'admins',
          'github',
          'open source',
          'who made this',
          'license',
        ],
      ),
      const GuideTopic(
        title: 'This guide',
        anchor: 'this-guide',
        icon: Icons.auto_stories_outlined,
        lead:
            "Using Tabulr now lives in Help & support, beside Academic rules, Report a problem and About. Search its topics, use the section navigation, or open the matching topic from a page info panel. Existing /guide links and topic anchors remain valid, and each topic can still be copied as a link.",
        keywords: [
          'guide',
          'help',
          'manual',
          'documentation',
          'how to',
          'tutorial',
        ],
      ),
    ],
  ),
];
