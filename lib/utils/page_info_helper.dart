import 'package:flutter/material.dart';
import '../widgets/common/app_dialog.dart';

class PageInfoHelper {
  PageInfoHelper._();

  static void show(BuildContext context, PageInfo info) {
    final scheme = Theme.of(context).colorScheme;

    AppDialog.adaptive(
      context: context,
      title: info.title,
      icon: Icons.info_outline,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              info.purpose,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: scheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          if (info.features.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...List.generate(info.features.length, (i) {
              final f = info.features[i];
              return Column(
                children: [
                  if (i > 0)
                    Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(f.icon, size: 15, color: scheme.primary.withValues(alpha: 0.8)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '${f.label}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(
                                  text: f.description,
                                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 12, color: scheme.onSurface, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }

  static Widget infoButton(BuildContext context, PageInfo info, {Key? key}) {
    return IconButton(
      key: key,
      icon: const Icon(Icons.info_outline, size: 20),
      tooltip: 'Page info',
      onPressed: () => show(context, info),
    );
  }

  static final timetableCreator = PageInfo(
    title: 'Timetable Creator',
    purpose: 'Build your semester timetable by adding courses and sections. Clash detection prevents scheduling conflicts.',
    features: [
      FeatureInfo(Icons.swap_horiz, 'Add/Swap', 'search and add or swap courses from the catalog'),
      FeatureInfo(Icons.auto_awesome_mosaic, 'Auto-Generate', 'generates optimal timetables based on your constraints'),
      FeatureInfo(Icons.share, 'Share', 'share your timetable via a code others can import'),
      FeatureInfo(Icons.menu_book, 'Tools', 'course guide, prerequisites, discipline & humanities electives'),
      FeatureInfo(Icons.more_vert, 'More', 'import/export .tt files, export to .ics calendar or .png image'),
      FeatureInfo(Icons.keyboard, 'Ctrl+K / Cmd+K', 'command palette to quickly jump to any feature or action'),
      // Which number a student is looking at depends on when they joined, and
      // nothing else on the screen says so.
      FeatureInfo(Icons.schedule_outlined, 'Credits vs credit hours',
          '2026 batch onwards registers in credit hours; 2025 batch and earlier in credits. Pick yours with the toggle — a timetable counts one way or the other, never both'),
    ],
  );

  static final timetableList = PageInfo(
    title: 'My Timetables',
    purpose: 'Manage all your timetables. Swipe cards for quick actions, or use the menu for more options.',
    features: [
      FeatureInfo(Icons.swipe_right, 'Swipe Right', 'rename or duplicate a timetable'),
      FeatureInfo(Icons.swipe_left, 'Swipe Left', 'delete a timetable'),
      FeatureInfo(Icons.drag_handle, 'Long Press', 'reorder timetables (in custom sort mode)'),
      FeatureInfo(Icons.add, 'New Timetable', 'create a new timetable from scratch'),
      FeatureInfo(Icons.download, 'Import', 'import a shared timetable via code'),
      FeatureInfo(Icons.compare, 'Compare', 'side-by-side timetable comparison'),
      FeatureInfo(Icons.keyboard, 'Ctrl+K / Cmd+K', 'command palette to quickly jump to any feature'),
    ],
  );

  static final calendar = PageInfo(
    title: 'Calendar',
    purpose: 'View your timetable as a weekly calendar with custom events. Navigate between weeks and temporarily hide slots.',
    features: [
      FeatureInfo(Icons.event_note, 'Academic Calendar', 'the whole semester\'s holidays, deadlines and exam windows in one list'),
      FeatureInfo(Icons.add, 'Add Event', 'add personal events alongside your classes'),
      FeatureInfo(Icons.event_busy, 'Scrap Slots', 'temporarily hide individual slots, courses, days, or the entire week'),
      FeatureInfo(Icons.restore, 'Restore', 'bring back scrapped slots'),
      FeatureInfo(Icons.chevron_right, 'Week Navigation', 'browse past and future weeks'),
    ],
  );

  static final freeSlotFinder = PageInfo(
    title: 'Free Time Finder',
    purpose: 'Compare multiple timetables side-by-side to find common free slots — useful for planning group activities.',
    features: [
      FeatureInfo(Icons.group, 'Add Timetables', 'add your own or import a friend\'s timetable via share code'),
      FeatureInfo(Icons.download, 'Import from Code', 'import a shared timetable by code'),
      FeatureInfo(Icons.touch_app, 'Select & Save', 'tap free slots to create a shared event'),
    ],
  );

  static final cgpaCalculator = PageInfo(
    title: 'CGPA Calculator',
    purpose: 'Track grades across semesters and calculate your SGPA/CGPA. Import courses from timetables or performance sheets.',
    features: [
      FeatureInfo(Icons.add_rounded, 'Add Course', 'manually add a course with credits and grade'),
      FeatureInfo(Icons.file_download_outlined, 'Import from Timetable', 'pull courses from an existing timetable'),
      FeatureInfo(Icons.picture_as_pdf_outlined, 'Import Performance Sheet', 'import grades from a PDF performance sheet'),
      FeatureInfo(Icons.school_outlined, 'Load CDCs', 'auto-load compulsory courses for your branch'),
      FeatureInfo(Icons.calculate_outlined, 'Grade Planner', 'plan what grades you need to reach a target CG'),
      FeatureInfo(Icons.bolt_outlined, 'CG Booster', 'find which courses have the biggest CG impact'),
      FeatureInfo(Icons.schedule_outlined, 'Credits vs credit hours',
          '2026 batch onwards is graded in credit hours; 2025 batch and earlier in credits. A record uses one or the other, so courses of the other kind are not accepted'),
    ],
  );

  static final examSeating = PageInfo(
    title: 'Exam Seating',
    purpose: 'Look up your exam room and seat number for midsems and compres.',
    features: [
      FeatureInfo(Icons.file_download_outlined, 'Import Courses', 'pull courses from an existing timetable'),
      FeatureInfo(Icons.save_outlined, 'Save', 'save your course list for quick access next time'),
      FeatureInfo(Icons.search, 'Search', 'search by course code or ID number'),
    ],
  );

  static final acadDrives = PageInfo(
    title: 'Academic Drives',
    purpose: 'Browse and download past papers, notes, and resources shared by students, organised by course.',
    features: [
      FeatureInfo(Icons.cloud_upload_outlined, 'Submit Resource', 'upload a file or link for a course'),
      FeatureInfo(Icons.search, 'Search', 'search across all courses and resources'),
    ],
  );

  static final profChambers = PageInfo(
    title: 'Prof Chambers',
    purpose: 'Find professor cabin locations and contact details.',
    features: [
      FeatureInfo(Icons.search, 'Search', 'search professors by name or department'),
      FeatureInfo(Icons.refresh, 'Refresh', 'reload the latest data'),
    ],
  );

  static final courseHistory = PageInfo(
    title: 'Course History',
    purpose: 'Every semester on record for this campus — which courses ran, who '
        'taught them, and how long it has been since one was last offered.',
    features: [
      FeatureInfo(Icons.menu_book_outlined, 'Courses',
          'see the semesters a course ran in and who taught each one'),
      FeatureInfo(Icons.person_search_outlined, 'Professors',
          'see what a professor has taught, semester by semester'),
      FeatureInfo(Icons.workspace_premium_outlined, 'IC badge',
          'marks the instructor-in-charge — who ran the course, not just taught a section'),
      FeatureInfo(Icons.filter_alt_outlined, 'Filter',
          'narrow to what is offered now, on pause, or new this semester'),
      FeatureInfo(Icons.touch_app_outlined, 'Cross-link',
          'tap a name or a course code to jump straight to its record'),
    ],
  );

  static final generator = PageInfo(
    title: 'Timetable Generator',
    purpose: 'Give it the courses you need and what a good week looks like to you; it returns clash-free options, ranked.',
    features: [
      FeatureInfo(Icons.playlist_add_check, 'Courses', 'mark which courses are required and which are optional'),
      FeatureInfo(Icons.schedule, 'Time limits', 'cap hours per day and block out mornings, evenings or whole days'),
      FeatureInfo(Icons.person_off_outlined, 'Avoid', 'rule out instructors, time slots or lab sessions'),
      FeatureInfo(Icons.tune, 'Ranking importance', 'say which matters more — a free day, light days, or exam spacing'),
      FeatureInfo(Icons.compare_arrows, 'Compare results', 'shortlist options and put them side by side'),
    ],
  );

  static final addSwap = PageInfo(
    title: 'Add / Swap Courses',
    purpose: 'The full course catalogue for your campus. Search, open a course, and pick the sections you want.',
    features: [
      FeatureInfo(Icons.search, 'Search', 'by course code or any part of the title'),
      FeatureInfo(Icons.filter_alt_outlined, 'Filter', 'narrow to a department, or to what fits your current week'),
      FeatureInfo(Icons.warning_amber_rounded, 'Clash marks', 'sections that would collide are flagged before you pick them'),
      FeatureInfo(Icons.layers_outlined, 'Section types', 'a course may need one lecture, one tutorial and one practical'),
    ],
  );

  static final quickReplace = PageInfo(
    title: 'Quick Replace',
    purpose: 'Swap one section for another without disturbing the rest of your timetable — for when a section closes.',
    features: [
      FeatureInfo(Icons.swap_horiz, 'Alternatives', 'every other section of the same course, in one list'),
      FeatureInfo(Icons.check_circle_outline, 'Fits first', 'sections that slot into your week are listed before the ones that clash'),
      FeatureInfo(Icons.undo, 'Undo', 'the swap is undoable like any other edit'),
    ],
  );

  static final trimTimetable = PageInfo(
    title: 'Trim to Fit',
    purpose: 'Work out which courses to drop from an overloaded timetable to get back under the credit cap.',
    features: [
      FeatureInfo(Icons.push_pin_outlined, 'Keep', 'mark the courses you will not drop'),
      FeatureInfo(Icons.content_cut, 'Suggestions', 'the smallest set of drops that gets you under the cap'),
      FeatureInfo(Icons.calculate_outlined, 'Running total', 'see the credit count update as you choose'),
    ],
  );

  static final sampleTimetables = PageInfo(
    title: 'Sample Timetables',
    purpose: 'Ready-made weeks covering your branch\'s compulsory courses, so a first semester does not start from an empty grid.',
    features: [
      FeatureInfo(Icons.school_outlined, 'By branch', 'pick your branch and year to see what applies to you'),
      FeatureInfo(Icons.download_outlined, 'Load', 'copy one into a new timetable and edit from there'),
    ],
  );

  static final archivedTimetables = PageInfo(
    title: 'Archived Timetables',
    purpose: 'Past semesters, kept out of the way but still readable — and still available to the CGPA calculator.',
    features: [
      FeatureInfo(Icons.inventory_2_outlined, 'Archive', 'move a finished semester out of the main list'),
      FeatureInfo(Icons.unarchive_outlined, 'Restore', 'bring one back if you need to edit it'),
      FeatureInfo(Icons.file_download_outlined, 'Still importable', 'pull courses from an archived semester into your CGPA record'),
    ],
  );

  static final timetableComparison = PageInfo(
    title: 'Compare Timetables',
    purpose: 'Two plans side by side, so the difference between them stops being abstract.',
    features: [
      FeatureInfo(Icons.compare, 'Side by side', 'both weeks on one screen'),
      FeatureInfo(Icons.insights_outlined, 'Stats', 'contact hours, free days and exam spread for each'),
    ],
  );

  static final electives = PageInfo(
    title: 'Electives',
    purpose: 'Discipline, humanities and open electives in one browsable list instead of three documents.',
    features: [
      FeatureInfo(Icons.category_outlined, 'Pools', 'switch between discipline, humanities and open electives'),
      FeatureInfo(Icons.check_circle_outline, 'Already taken', 'courses in your CGPA record are marked so you do not re-pick them'),
      FeatureInfo(Icons.add_circle_outline, 'Add', 'put a section straight onto the timetable you came from'),
    ],
  );

  static final minors = PageInfo(
    title: 'Minors',
    purpose: 'Every minor programme, the courses it requires, and how far along you already are.',
    features: [
      FeatureInfo(Icons.workspace_premium_outlined, 'Programmes', 'browse the minors on offer at your campus'),
      FeatureInfo(Icons.donut_large, 'Progress', 'requirements met and left, read from your CGPA record'),
      FeatureInfo(Icons.playlist_add_check, 'Remaining', 'what you would still have to take to finish'),
    ],
  );

  static final prerequisites = PageInfo(
    title: 'Prerequisites',
    purpose: 'What a course needs before you can take it, and what taking it opens up.',
    features: [
      FeatureInfo(Icons.account_tree, 'Chains', 'follow a course back to its prerequisites, and forward to what it unlocks'),
      FeatureInfo(Icons.rule, 'All vs any', 'some courses need every prerequisite, some need any one of a set'),
      FeatureInfo(Icons.check_circle_outline, 'Cleared', 'prerequisites you have already passed are marked'),
    ],
  );

  static final courseGuide = PageInfo(
    title: 'Course Guide',
    purpose: 'What your branch is meant to take, semester by semester — the compulsory courses and the electives that count.',
    features: [
      FeatureInfo(Icons.school_outlined, 'Branch', 'pick your branch, and a second one if you are dual degree'),
      FeatureInfo(Icons.view_timeline_outlined, 'By semester', 'the expected load for each semester of the programme'),
    ],
  );

  static final cgBooster = PageInfo(
    title: 'CG Booster',
    purpose: 'Which courses move your CGPA most, so your effort goes where it counts.',
    features: [
      FeatureInfo(Icons.bolt_outlined, 'Impact ranking', 'courses ordered by how much one grade step would change your CGPA'),
      FeatureInfo(Icons.balance, 'Weight', 'a heavier course pulls harder than a lighter one'),
    ],
  );

  static final gradePlanner = PageInfo(
    title: 'Grade Planner',
    purpose: 'Work backwards from a target CGPA to the grades this semester would have to produce.',
    features: [
      FeatureInfo(Icons.flag_outlined, 'Target', 'set the CGPA you are aiming for'),
      FeatureInfo(Icons.calculate_outlined, 'Required grades', 'what you would need in each course to get there'),
      FeatureInfo(Icons.report_gmailerrorred_outlined, 'Out of reach', 'says so plainly when a target cannot be hit this semester'),
    ],
  );

  static final cgpaTrajectory = PageInfo(
    title: 'CGPA Trajectory',
    purpose: 'Your standing semester by semester, with each SGPA against the cumulative CGPA it produced.',
    features: [
      FeatureInfo(Icons.trending_up, 'Trend', 'see whether you are climbing, flat or slipping'),
      FeatureInfo(Icons.flag_outlined, 'Target line', 'your goal drawn across the chart'),
    ],
  );

  static final profile = PageInfo(
    title: 'Profile',
    purpose: 'Your ID number, branch and default semester — filled in once, used everywhere.',
    features: [
      FeatureInfo(Icons.badge_outlined, 'ID number', 'so exam seating can look you up without asking'),
      FeatureInfo(Icons.school_outlined, 'Branch', 'so CDCs and the course guide open on the right programme'),
      FeatureInfo(Icons.palette_outlined, 'Theme', 'pick a theme and light, dark or system'),
    ],
  );

  static final bugReport = PageInfo(
    title: 'Bug Report',
    purpose: 'Report anything broken — a screen that misbehaves, or course data that does not match the booklet.',
    features: [
      FeatureInfo(Icons.add, 'Report', 'describe what you did and what happened instead'),
      FeatureInfo(Icons.forum_outlined, 'Follow up', 'read replies and watch the status change'),
      FeatureInfo(Icons.military_tech_outlined, 'Reputation', 'reports that turn out to be real build your contributor standing'),
    ],
  );

  static final academicFaq = PageInfo(
    title: 'Academic FAQ',
    purpose: 'Short answers to the academic rules students actually ask about, each citing the clause it comes from.',
    features: [
      FeatureInfo(Icons.search, 'Search', 'across every question, answer and synonym'),
      FeatureInfo(Icons.category_outlined, 'Categories', 'grades, attendance, registration, Practice School and more'),
      FeatureInfo(Icons.menu_book_outlined, 'Sources', 'every answer names the regulation it came from'),
    ],
  );

  static final announcements = PageInfo(
    title: 'Announcements',
    purpose: 'Course-specific announcements posted by students — schedule changes, extra classes, exam updates.',
    features: [
      FeatureInfo(Icons.add, 'Post', 'create an announcement for a course'),
      FeatureInfo(Icons.arrow_upward_rounded, 'Vote', 'upvote or downvote announcements'),
      FeatureInfo(Icons.flag_outlined, 'Flag', 'report incorrect information'),
      FeatureInfo(Icons.check_circle_outline, 'Verify', 'confirm or deny announcements'),
    ],
  );

  static final List<PageInfo> all = [
    timetableCreator,
    timetableList,
    calendar,
    freeSlotFinder,
    cgpaCalculator,
    examSeating,
    acadDrives,
    profChambers,
    courseHistory,
    announcements,
    generator,
    addSwap,
    quickReplace,
    trimTimetable,
    sampleTimetables,
    archivedTimetables,
    timetableComparison,
    electives,
    minors,
    prerequisites,
    courseGuide,
    cgBooster,
    gradePlanner,
    cgpaTrajectory,
    profile,
    bugReport,
    academicFaq,
  ];
}

class PageInfo {
  final String title;
  final String purpose;
  final List<FeatureInfo> features;

  const PageInfo({
    required this.title,
    required this.purpose,
    this.features = const [],
  });
}

class FeatureInfo {
  final IconData icon;
  final String label;
  final String description;

  const FeatureInfo(this.icon, this.label, this.description);
}
