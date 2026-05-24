import 'package:flutter/material.dart';
import '../widgets/common/app_dialog.dart';

class PageInfoHelper {
  PageInfoHelper._();

  static void show(BuildContext context, PageInfo info) {
    AppDialog.adaptive(
      context: context,
      title: info.title,
      icon: Icons.info_outline,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.purpose,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          if (info.features.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...info.features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(f.icon, size: 14,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                        children: [
                          TextSpan(text: '${f.label}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: f.description),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )),
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

  static Widget infoButton(BuildContext context, PageInfo info) {
    return IconButton(
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
      FeatureInfo(Icons.brightness_auto, 'Theme', 'switch between light, dark, and system theme'),
    ],
  );

  static final calendar = PageInfo(
    title: 'Calendar',
    purpose: 'View your timetable as a weekly calendar with custom events. Navigate between weeks and temporarily hide slots.',
    features: [
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
