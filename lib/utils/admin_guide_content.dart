import 'package:flutter/material.dart';

import 'guide_content.dart';

/// The admin handbook: what each part of the admin dashboard does, and the
/// routine that keeps Tabulr's data correct. Rendered by [GuideScreen], the
/// same screen as the student guide. The repo-side detail (scripts, deploys,
/// credentials) lives in docs/RUNBOOK.md; keep the two consistent.
final List<GuideSection> adminGuideSections = [
  const GuideSection(
    title: 'Getting started',
    anchor: 'admin-start',
    icon: Icons.play_circle_outline,
    blurb: 'What admins look after, and how the dashboard is laid out.',
    topics: [
      GuideTopic(
        title: 'What being an admin means',
        anchor: 'admin-role',
        icon: Icons.admin_panel_settings_outlined,
        lead:
            "Students trust Tabulr because its data is right this week: sections, rooms, exams, holidays, professors. Admins keep it that way. Almost all of it is uploading the official documents each semester and fixing what the parsers get wrong.",
        steps: [
          'Admin access comes from a document named after your email in the admin_emails collection. An existing admin or the Firebase owner adds it in the Firebase console; sign out and back in afterwards.',
          'Everything you change is live for every student, usually on their next open.',
          'Every bulk upload previews its changes before writing. Read the preview: it is the approval step.',
        ],
        keywords: ['access', 'permission', 'become admin', 'admin_emails'],
      ),
      GuideTopic(
        title: 'Reading the dashboard',
        anchor: 'admin-layout',
        icon: Icons.dashboard_outlined,
        lead:
            "The top of the dashboard tells you what needs doing; the cards open editors for each kind of data; the sections below them are the bulk uploads and app-wide switches.",
        steps: [
          'Upstream changes (only shown when there is something new): timetable-change and seating posts from the LMS, new Bulletins, and new faculty on the BITS website. Timetable changes have a Review button; seating and new-faculty notices have an Apply button.',
          'Data freshness: when each dataset was last uploaded. Green is this term, amber last term, red never.',
          'Cards: Course Management, Courses Master, Minor Programmes, Exam Seating, Professor Chambers, Course Guide, Branch Groups, Prerequisites, Duplicate Courses, Academic Calendar, Drive Submissions and Bug Tracker.',
          'Sections: Timetable Upload, Archive Timetables, Exam Seating upload, Professor Schedules, Semester Dates and Live Calendar Links.',
          'An amber number on the sidebar Admin item and on the Bug Tracker card counts bug reports waiting on an admin.',
        ],
        keywords: ['layout', 'overview', 'cards', 'sections', 'badge'],
      ),
    ],
  ),
  const GuideSection(
    title: 'The semester routine',
    anchor: 'admin-routine',
    icon: Icons.event_repeat_rounded,
    blurb: 'What to do, and when, so nothing goes stale.',
    topics: [
      GuideTopic(
        title: 'When a new timetable booklet comes out',
        anchor: 'admin-new-semester',
        icon: Icons.fiber_new_rounded,
        lead:
            "Booklets come out in July (odd semester) and December (even semester). Do these in order; Data freshness turns green as you go.",
        steps: [
          'Archive Timetables for the semester that just ended. This also moves the app to the new term.',
          'Timetable Upload for each campus, with the timetable page range and the academic-calendar page range filled in.',
          'Open Academic Calendar and check each campus: classes begin, last day of classes, holidays and exam weeks. Students\' calendars and the calendar export are built from it.',
          'Check Semester Dates match the new term.',
          'Professor schedules rebuild by themselves after the upload; for new faculty, upload a fresh roster under Professor Schedules.',
          'Approve any Drive Submissions; the weekly sync copies their files every Monday morning.',
        ],
        keywords: ['checklist', 'new term', 'rollover', 'july', 'december', 'booklet'],
      ),
      GuideTopic(
        title: 'During the semester',
        anchor: 'admin-during',
        icon: Icons.update_rounded,
        lead:
            "The Timetable Division posts 'Timetable changes' PDFs on the LMS front page. Tabulr checks every Monday and lists new ones under Upstream changes; press Check now on Data freshness when you know something was just posted.",
        steps: [
          "Press Review on the notice. Tabulr reads the PDF and lists every change against the live timetable: 'Ready' rows still match what the PDF calls existing and start ticked; 'Check' rows differ from it, so tick them only if the PDF is right anyway; 'Already in' rows need nothing. Press Apply.",
          "'Add by hand' rows are new courses with several sections sharing one hours line, which the PDF does not split; add those in Course Management.",
          "Students' saved timetables pick the change up on their next open, with a 'What changed' notice; live calendar links update at their next refresh; professor schedules rebuild by themselves.",
          'Mark the notice Done. Dismiss anything that needs no action.',
          'Seating posted on the LMS arrives under Upstream changes already read, with a one-line summary (courses, rooms, dates). Check it and press Apply; it replaces Hyderabad\'s seating.',
          'Work through Bug Tracker and chamber reports (in Professor Chambers) every week or so.',
        ],
        keywords: ['timetable changes', 'lms', 'changes pdf', 'weekly'],
      ),
      GuideTopic(
        title: 'Once a year',
        anchor: 'admin-yearly',
        icon: Icons.menu_book_outlined,
        lead:
            "A new Bulletin appears under Upstream changes when it is published. It changes prerequisites, minors and first-year course groups.",
        steps: [
          'Prerequisites: re-run the bulletin extraction script (see the runbook), then review with Prerequisites.',
          'Minors: check each programme in Minor Programmes; use the Needs review filter.',
          'New batch: update Branch Groups and Course Guide for the incoming year.',
        ],
        keywords: ['bulletin', 'annual', 'prerequisites', 'minors', 'new batch'],
      ),
    ],
  ),
  const GuideSection(
    title: 'Courses and timetables',
    anchor: 'admin-courses',
    icon: Icons.menu_book_rounded,
    blurb: 'The catalogue, this semester\'s sections, and the uploads that fill them.',
    topics: [
      GuideTopic(
        title: 'Timetable Upload',
        anchor: 'admin-timetable-upload',
        icon: Icons.upload_file_rounded,
        lead:
            "Parses a campus's timetable booklet into this semester's courses, sections and exam dates, and optionally its academic calendar. It replaces that campus's timetable.",
        steps: [
          'Pick the PDF for each campus and set the page range of the course tables. Leaving it empty parses page headers as courses.',
          'Fill the calendar page range (usually page 2) to update the academic calendar in the same upload.',
          'Check the exam year (the calendar year the exams fall in; it defaults correctly) and the semester.',
          'Read the preview. If it refuses because fewer than 80% of current courses remain, check the page range first; only tick "Upload anyway" if the booklet really is smaller.',
          "Saved student timetables are never lost: they keep their own copy of each section and are flagged if a section disappears.",
        ],
        keywords: ['booklet', 'pdf', 'parse', 'page range', 'exam year', 'upload'],
      ),
      GuideTopic(
        title: 'Course Management',
        anchor: 'admin-course-management',
        icon: Icons.menu_book_rounded,
        lead:
            "Edits this semester's courses on a campus: sections, instructors, rooms, timings and exam dates. LMS timetable changes are applied from Upstream changes; this is for anything that review leaves to you.",
        steps: [
          'Search the course, open it, and edit the section that changed.',
          'Saving updates students on their next open and rebuilds professor schedules.',
          'Only reaches courses running this semester; catalogue-only courses are in Courses Master.',
        ],
        keywords: ['section', 'room', 'instructor', 'timing', 'edit course', 'exam date'],
      ),
      GuideTopic(
        title: 'Courses Master',
        anchor: 'admin-courses-master',
        icon: Icons.inventory_2_outlined,
        lead:
            "The catalogue of every course that exists, offered this semester or not: code, title, units, credit hours. Titles everywhere in the app come from here.",
        steps: [
          'Use it to fix a wrong title or units, or add a course the catalogue is missing.',
          'Timetable uploads add new courses here automatically but never delete rows.',
        ],
        keywords: ['catalogue', 'catalog', 'title', 'units', 'credits'],
      ),
      GuideTopic(
        title: 'Duplicate Courses',
        anchor: 'admin-duplicates',
        icon: Icons.content_copy_rounded,
        lead:
            "Groups of course codes that are the same course under different numbers (cross-listings). Prerequisite checks, CGPA and Acad Drives treat a group as one course.",
        steps: [
          'Add a code to a group when a cross-listed twin is not being recognised.',
          'Save once at the end; leaving with unsaved changes asks first.',
        ],
        keywords: ['cross-listed', 'equivalent', 'same course', 'twin'],
      ),
      GuideTopic(
        title: 'Prerequisites',
        anchor: 'admin-prerequisites',
        icon: Icons.account_tree_rounded,
        lead:
            "Each course's prerequisites as groups: every group must be met, and any one course in a group meets it.",
        steps: [
          'Search a course to edit its groups; add a requirement for each separate condition.',
          'Bulk updates from the official list or the Bulletin are scripts; see the runbook.',
        ],
        keywords: ['prereq', 'pre-requisite', 'requirement', 'co-requisite'],
      ),
    ],
  ),
  const GuideSection(
    title: 'Degree data',
    anchor: 'admin-degree',
    icon: Icons.school_outlined,
    blurb: 'Branch curricula, first-year groups and minors.',
    topics: [
      GuideTopic(
        title: 'Course Guide',
        anchor: 'admin-course-guide',
        icon: Icons.auto_stories_rounded,
        lead:
            "Each branch's compulsory courses (CDCs) by semester, including choose-one CDC slots. Degree audit, auto-load CDCs and the course guide all read it.",
        steps: [
          'Pick a branch, then add or remove courses per semester; a choose-one slot lists its alternatives.',
          'Dual-degree branches are made from an MSc and a BE branch.',
        ],
        keywords: ['cdc', 'curriculum', 'branch', 'compulsory', 'degree audit'],
      ),
      GuideTopic(
        title: 'Branch Groups',
        anchor: 'admin-branch-groups',
        icon: Icons.workspaces_rounded,
        lead:
            "First-year course packages. Every branch in a group takes the group's first-year CDCs; saving copies them to the member branches.",
        steps: [
          'Move a branch between groups, or edit a group\'s 1-1 and 1-2 courses.',
          'Update these when a new batch\'s first-year packages are announced.',
        ],
        keywords: ['first year', 'package', '1-1', '1-2', 'group'],
      ),
      GuideTopic(
        title: 'Minor Programmes',
        anchor: 'admin-minors',
        icon: Icons.workspace_premium_outlined,
        lead:
            "The published catalogue of minors: requirements and course groups. Some records were imported with their Core and Electives split wrong; they carry a Needs review flag.",
        steps: [
          'Use the Needs review filter as the queue; fix the groups, then clear the flag.',
          'Courses are added with the course picker, so codes and titles are never typed by hand.',
        ],
        keywords: ['minor', 'needs review', 'core', 'electives'],
      ),
    ],
  ),
  const GuideSection(
    title: 'Exams, professors and the calendar',
    anchor: 'admin-campus',
    icon: Icons.event_note_rounded,
    blurb: 'Seating, faculty, holidays and term dates.',
    topics: [
      GuideTopic(
        title: 'Exam Seating',
        anchor: 'admin-exam-seating',
        icon: Icons.event_seat_rounded,
        lead:
            "Rooms and ID ranges for each exam (Hyderabad). Students see their room in Exam Seating, and in their live calendar once they have saved their ID.",
        steps: [
          'Usually nothing to upload: seating posted on the LMS front page shows up under Upstream changes after the Monday check, or straight away with Check now, ready to Apply.',
          'For a PDF from anywhere else, upload it in the Exam Seating section.',
          'Fix or add a single course\'s rooms in the Exam Seating card.',
        ],
        keywords: ['seating', 'room', 'id range', 'midsem', 'compre'],
      ),
      GuideTopic(
        title: 'Professor Chambers and Schedules',
        anchor: 'admin-professors',
        icon: Icons.person_rounded,
        lead:
            "Faculty with their chamber, email and what they teach this semester. Schedules rebuild by themselves whenever the timetable changes. The faculty website publishes no chambers, so chambers come from admins and students.",
        steps: [
          'Professor Chambers: edit a chamber, email or phone. Students see it straight away.',
          'Chamber reports from students appear at the top of Professor Chambers; Accept writes the chamber, Reject discards it.',
          'New faculty: every Monday Tabulr compares the BITS faculty website with its list; new names appear under Upstream changes. Apply adds them (chambers and names already on file are kept).',
          'Professor Schedules: Rebuild by hand only if something looks off; it also takes a roster file made by functions-python/faculty.py.',
          'After a rebuild, check the names it says it matched only by spelling.',
        ],
        keywords: ['chamber', 'faculty', 'professor', 'roster', 'schedule', 'profs.json'],
      ),
      GuideTopic(
        title: 'Academic Calendar',
        anchor: 'admin-academic-calendar',
        icon: Icons.event_note_rounded,
        lead:
            "Each campus's holidays, deadlines and exam weeks, read from the booklet. It decides which days have class in the app's Calendar, the calendar export and live calendar links.",
        steps: [
          'Check every row after a timetable upload; the parser is good but not perfect.',
          "A day has no class if it is a holiday, marked (H), or covered by an entry that says classwork suspended, recess or vacation.",
          "Classes run from the 'Class work begins' row to the 'Last day of classes' row; keep those two labels intact.",
        ],
        keywords: ['holiday', 'calendar', 'deadline', 'classwork suspended', 'recess'],
      ),
      GuideTopic(
        title: 'Semester Dates',
        anchor: 'admin-semester-dates',
        icon: Icons.date_range_rounded,
        lead:
            "Start and end of the semester and of the mid-sem and end-sem exam windows. The Calendar shows exams in place of classes during the exam windows, and these dates are the fallback when a campus has no academic calendar.",
        steps: ['Update them each semester; they apply to everyone on their next open.'],
        keywords: ['semester start', 'semester end', 'midsem', 'endsem', 'dates'],
      ),
      GuideTopic(
        title: 'Archive Timetables',
        anchor: 'admin-archive',
        icon: Icons.archive_outlined,
        lead:
            "Moves every student's timetables from a finished semester into their archive and advances the app to the next term.",
        steps: [
          'Enter the academic year (YYYY-YYYY) and semester that just ended, then Archive All Users.',
          'Do this before uploading the new booklet.',
        ],
        keywords: ['archive', 'term', 'rollover', 'end of semester'],
      ),
    ],
  ),
  const GuideSection(
    title: 'Community and feedback',
    anchor: 'admin-community',
    icon: Icons.groups_outlined,
    blurb: 'What students send in, and the switches that protect them.',
    topics: [
      GuideTopic(
        title: 'Drive Submissions',
        anchor: 'admin-drive-submissions',
        icon: Icons.add_link_rounded,
        lead:
            "Google Drive links students submit from Acad Drives. Approving one adds it to the drive sync, which runs every Monday morning; its files appear after that.",
        steps: [
          'Open the link and check it is academic material and publicly viewable.',
          'Approve and give the drive a short name; students see that name. A name already in use is refused.',
          "If the student picked a course, every file in the drive is filed under it.",
        ],
        keywords: ['acad drives', 'drive link', 'submission', 'approve'],
      ),
      GuideTopic(
        title: 'Bug Tracker',
        anchor: 'admin-bug-tracker',
        icon: Icons.bug_report_rounded,
        lead:
            "Every bug report, newest first. 'Needs a look' lists those nobody has picked up and those where the reporter replied last.",
        steps: [
          'Set a status as you work: Pending, In Review, Dev In Progress, Fixed.',
          'Reply in the thread; the reporter sees it in Report a problem.',
          'Hide reports that need no action (duplicates, spam). They move to the Hidden tab and stop counting; the reporter still sees theirs.',
        ],
        keywords: ['bug', 'report', 'feedback', 'hidden', 'needs a look'],
      ),
      GuideTopic(
        title: 'Live Calendar Links',
        anchor: 'admin-calendar-links',
        icon: Icons.event_repeat_rounded,
        lead:
            "Students can subscribe to their timetable from Google, Apple or Outlook Calendar. This switch turns every link off at once.",
        steps: [
          'Turned off, every link serves an empty calendar, which clears the events from subscribers\' calendars, and the app hides the option.',
          'Turning it back on restores everyone; nobody needs to resubscribe.',
          'Changes reach calendars at their next refresh, which can take from minutes to a day.',
        ],
        keywords: ['webcal', 'ics', 'subscribe', 'calendar link', 'kill switch'],
      ),
    ],
  ),
  const GuideSection(
    title: 'Outside the app',
    anchor: 'admin-outside',
    icon: Icons.terminal_rounded,
    blurb: 'Jobs that need the repository or the Firebase console.',
    topics: [
      GuideTopic(
        title: 'Scripts and the runbook',
        anchor: 'admin-scripts',
        icon: Icons.terminal_rounded,
        lead:
            "Most checks run on their own: the LMS and the faculty website weekly (Check now runs the LMS check on demand), the Acad Drives sync weekly (GitHub Actions). What is left in the repository is yearly: Bulletin prerequisites and ERP exports. docs/RUNBOOK.md has the commands, credentials and deploy steps.",
        steps: [
          'Every script is a dry run unless you add --apply (or --commit). Read the whole dry run first.',
          'Maintenance mode (taking the app offline for students) is the maintenance field on reference/app_config in the Firebase console.',
          'Handing over: add the next admins to admin_emails and give them Firebase and GitHub access; the runbook lists everything else.',
        ],
        keywords: ['script', 'runbook', 'deploy', 'maintenance', 'handover', 'firebase console'],
      ),
    ],
  ),
];
