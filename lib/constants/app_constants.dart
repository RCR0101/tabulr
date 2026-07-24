/// Centralized constants for the Tabulr app.
///
/// Organized by category so changes to collection names, keys, limits, etc.
/// propagate everywhere automatically.
library;

// ── Firestore collection / document paths ──────────────────────────────

abstract final class FirestoreCollections {
  static const String users = 'users';
  static const String timetables = 'timetables';
  static const String campuses = 'campuses';
  static const String coursesMaster = 'courses_master';
  static const String examSeating = 'exam_seating';
  static const String reference = 'reference';
  static const String reputation = 'reputation';
  static const String announcements = 'announcements';
  static const String sharedTimetables = 'shared_timetables';
  static const String settings = 'settings';
  static const String preferences = 'preferences';
  static const String calendarPrefs = 'calendar_prefs';
  static const String flags = 'flags';
  static const String verifications = 'verifications';
  static const String votes = 'votes';
  static const String data = 'data';
  static const String branches = 'branches';
  static const String professors = 'professors';
  static const String timetable = 'timetable';
  static const String metadata = 'metadata';
  static const String current = 'current';
  /// Pre-bundled catalogue: one document holding the whole courses_master list,
  /// so a cold load costs 1 read instead of ~2.8k.
  static const String catalog = 'catalog';
  static const String coursesMasterBundle = 'courses_master';
  static const String prerequisites = 'prerequisites';
  static const String courses = 'courses';
  static const String acadDrivesIndex = 'acad_drives_index';
  static const String acadDrivesFiles = 'acad_drives_files';
  static const String acadDrivesSubmissions = 'acad_drives_submissions';
  static const String examSeatingPrefs = 'exam_seating_prefs';
  static const String cgpaSemesters = 'cgpa_semesters';
  static const String archivedTimetables = 'archivedTimetables';
  static const String minors = 'minors';
  static const String bugReports = 'bug_reports';
  static const String bugReportMessages = 'messages';
  static const String profile = 'profile';
  static const String academicCalendar = 'academicCalendar';
}

// ── SharedPreferences / local-storage keys ─────────────────────────────

abstract final class StorageKeys {
  static const String isAuthenticated = 'is_authenticated';
  static const String isGuest = 'is_guest';
  static const String selectedTheme = 'selected_theme';
  static const String selectedThemeName = 'selected_theme_name';
  static const String themeMode = 'theme_mode';
  static const String timetableSize = 'timetable_size';
  static const String timetableLayout = 'timetable_layout';
  static const String userSettings = 'user_settings';
  static const String selectedCampus = 'selected_campus';
  static const String userTimetableData = 'user_timetable_data';
  static const String userTimetablesList = 'user_timetables_list';
  static const String normalizedTimetablePrefix = 'normalized_timetable_';
  static const String courseMetadata = 'course_metadata';
  static const String migrationVersion = 'migration_version';
  static const String currentMigrationVersion = '1.0.0';
}

// ── Remote URLs ────────────────────────────────────────────────────────

abstract final class FirebaseConfig {
  static const String functionsRegion = 'asia-south1';
  static const String recaptchaSiteKey = '6LddywotAAAAAB_ZxyOdhXcE58f8jVNRLuTP0HE3';
  static const String recaptchaEnterpriseSiteKey = '6LeXHQ0tAAAAAKF6s3MnZGKsm9MMzbbU8rHwjmwJ';
}

abstract final class AppUrls {
  static const String perfLoggerWorker =
      'https://test-logger.dalmia-aryan.workers.dev';
  static const String cgpaEncryptionWorker =
      'https://cgpa-encryption.dalmia-aryan.workers.dev';
  static const String githubRepo =
      'https://github.com/RCR0101/timetable_maker';
  static const String acadDrivesIndexUrl =
      'https://pub-f49326688b9147a48953bfe887abd9ce.r2.dev/tabulr_meta/acad-drives-index.json';
}

// ── Campus identifiers & labels ────────────────────────────────────────

abstract final class CampusConstants {
  static const List<String> ids = ['hyderabad', 'pilani', 'goa'];
  static const Map<String, String> labels = {
    'hyderabad': 'Hyderabad',
    'pilani': 'Pilani',
    'goa': 'Goa',
  };
}

// ── Grades & grade points ──────────────────────────────────────────────

abstract final class GradeConstants {
  static const Map<String, double> gradePoints = {
    'A': 10.0, 'A-': 9.0, 'B': 8.0, 'B-': 7.0,
    'C': 6.0, 'C-': 5.0, 'D': 4.0, 'D-': 3.0, 'E': 2.0,
  };

  static const Map<String, String> descriptions = {
    'A': '10 Grade Points', 'A-': '9 Grade Points',
    'B': '8 Grade Points', 'B-': '7 Grade Points',
    'C': '6 Grade Points', 'C-': '5 Grade Points',
    'D': '4 Grade Points', 'D-': '3 Grade Points',
    'E': '2 Grade Points',
    'GD': 'Good', 'PR': 'Poor', 'NC': 'Not Cleared',
    'SA': 'Satisfactory', 'US': 'Unsatisfactory',
    'W': 'Withdrawn', 'RC': 'Registration Cancelled',
    'I': 'Incomplete', 'GA': 'Grade Awaited',
  };

  /// Reports, not grades (Academic Regulations clause 4.12).
  ///
  /// None of these carry grade points or units, and none displaces an earlier
  /// letter grade on a repeat — clauses 4.17 (W) and 4.18–4.19 (RC) spell out
  /// the same "go backward to the previous performance" rule that 4.21 gives
  /// for NC. `I` and `GA` are transient placeholders awaiting a real grade.
  static const List<String> reports = ['NC', 'W', 'RC', 'I', 'GA'];

  /// The one letter grade that is a fail (clause 5.02: a first degree tolerates
  /// no more than one, a higher degree none).
  static const String failingGrade = 'E';

  static final List<String> normal = gradePoints.keys.toList();
  static final List<double> points = gradePoints.values.toList();
  static final List<String> normalWithReports = [...normal, ...reports];
  static const List<String> atc = ['GD', 'PR', 'SA', 'US', 'NC'];
  static final Set<String> allValid = {
    ...gradePoints.keys,
    ...reports,
    'GD',
    'PR',
    'SA',
    'US',
  };
  static const Set<String> electiveTags = {'HEL', 'DEL', 'EL'};

  static double pointsFor(String grade) => gradePoints[grade] ?? 0.0;

  /// Whether [grade] is a *letter grade* (A…E) as opposed to a *report*
  /// (NC, W, I, GA, RC, …).
  ///
  /// Academic Regulations clause 4.21: the CGPA covers "all courses in which
  /// He/she is awarded letter grades", and "if through this process merely a
  /// report emerges, this event by itself will not alter the CGPA". So a report
  /// contributes neither grade points nor units, and never displaces an earlier
  /// letter grade on a repeat.
  static bool isLetterGrade(String? grade) =>
      grade != null && gradePoints.containsKey(grade);
  static String descriptionFor(String grade) => descriptions[grade] ?? '';
}

// ── Semester labels ────────────────────────────────────────────────────

abstract final class SemesterConstants {
  static const List<String> all = [
    '1-1', '1-2', '2-1', '2-2', 'ST 1',
    '3-1', '3-2', 'ST 2', '4-1', '4-2', 'ST 3', '5-1', '5-2',
  ];

  /// Regular teaching semesters (special terms excluded) — the base every
  /// year-range subset below is derived from, so there is one list to edit.
  static final List<String> regular =
      all.where((s) => !s.startsWith('ST')).toList();

  static int _year(String semester) => int.parse(semester.split('-').first);

  static List<String> _range(int from, int to) =>
      regular.where((s) => _year(s) >= from && _year(s) <= to).toList();

  /// Years 1–4 — where the 5th year isn't offered (CDCs, course guide).
  static List<String> get yearsOneToFour => _range(1, 4);

  /// Years 1–3 — Quick Replace's simplified range.
  static List<String> get yearsOneToThree => _range(1, 3);

  /// Years 2–4 — electives are taken from the second year on (DEL/HUEL/OPEL).
  static List<String> get electives => _range(2, 4);
}

// ── Day / schedule labels ──────────────────────────────────────────────

abstract final class DayConstants {
  static const List<String> shortLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
  ];
  static const List<String> singleChar = ['M', 'T', 'W', 'Th', 'F', 'S'];
  static const List<String> monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> weekDays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
}

// ── Exam time-slot enum & campus-specific mappings ────────────────────

// ignore_for_file: constant_identifier_names
enum TimeSlot { FN, AN, MS1, MS2, MS3, MS4 }

abstract final class ExamSlotConstants {
  static const Map<String, Map<TimeSlot, String>> campusTimeSlotNames = {
    'pilani': {
      TimeSlot.FN: '8:00AM-11:00AM',
      TimeSlot.AN: '3:00PM-6:00PM',
      TimeSlot.MS1: '9:30AM-11:00AM',
      TimeSlot.MS2: '11:30AM-1:00PM',
      TimeSlot.MS3: '2:00PM-3:30PM',
      TimeSlot.MS4: '4:00PM-5:30PM',
    },
    'goa': {
      TimeSlot.FN: '10:00AM-1:00PM',
      TimeSlot.AN: '2:00PM-5:00PM',
      TimeSlot.MS1: '9:30AM-11:00AM',
      TimeSlot.MS2: '11:30AM-1:00PM',
      TimeSlot.MS3: '2:00PM-3:30PM',
      TimeSlot.MS4: '4:00PM-5:30PM',
    },
    'hyderabad': {
      TimeSlot.FN: '9:30AM-12:30PM',
      TimeSlot.AN: '2:00PM-5:00PM',
      TimeSlot.MS1: '9:30AM-11:00AM',
      TimeSlot.MS2: '11:30AM-1:00PM',
      TimeSlot.MS3: '2:00PM-3:30PM',
      TimeSlot.MS4: '4:00PM-5:30PM',
    },
  };

  static const Map<TimeSlot, String> defaultTimeSlotNames = {
    TimeSlot.FN: '8:00AM-11:00AM',
    TimeSlot.AN: '3:00PM-6:00PM',
    TimeSlot.MS1: '9:30AM-11:00AM',
    TimeSlot.MS2: '11:30AM-1:00PM',
    TimeSlot.MS3: '2:00PM-3:30PM',
    TimeSlot.MS4: '4:00PM-5:30PM',
  };

  static const Map<String, Map<TimeSlot, List<int>>> campusExamStartTimes = {
    'pilani': {
      TimeSlot.FN: [8, 0],
      TimeSlot.AN: [15, 0],
      TimeSlot.MS1: [9, 30],
      TimeSlot.MS2: [11, 30],
      TimeSlot.MS3: [14, 0],
      TimeSlot.MS4: [16, 0],
    },
    'goa': {
      TimeSlot.FN: [10, 0],
      TimeSlot.AN: [14, 0],
      TimeSlot.MS1: [9, 30],
      TimeSlot.MS2: [11, 30],
      TimeSlot.MS3: [14, 0],
      TimeSlot.MS4: [16, 0],
    },
    'hyderabad': {
      TimeSlot.FN: [9, 30],
      TimeSlot.AN: [14, 0],
      TimeSlot.MS1: [9, 30],
      TimeSlot.MS2: [11, 30],
      TimeSlot.MS3: [14, 0],
      TimeSlot.MS4: [16, 0],
    },
  };
}

// ── Class hour / exam time-slot schedule ───────────────────────────────

abstract final class ScheduleConstants {
  static const List<int> classHours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  static const Map<int, List<int>> hourToTime = {
    1: [8, 0], 2: [9, 0], 3: [10, 0], 4: [11, 0],
    5: [12, 0], 6: [13, 0], 7: [14, 0], 8: [15, 0],
    9: [16, 0], 10: [17, 0], 11: [18, 0], 12: [19, 0],
  };

  static const Map<int, String> hourLabels = {
    1: '8AM', 2: '9AM', 3: '10AM', 4: '11AM', 5: '12PM',
    6: '1PM', 7: '2PM', 8: '3PM', 9: '4PM', 10: '5PM',
    11: '6PM', 12: '7PM',
  };

  static const Map<int, String> hourSlotNames = {
    1: '8:00-8:50 AM', 2: '9:00-9:50 AM', 3: '10:00-10:50 AM',
    4: '11:00-11:50 AM', 5: '12:00-12:50 PM', 6: '1:00-1:50 PM',
    7: '2:00-2:50 PM', 8: '3:00-3:50 PM', 9: '4:00-4:50 PM',
    10: '5:00-5:50 PM', 11: '6:00-6:50 PM', 12: '7:00-7:50 PM',
  };

  static const Duration midsemExamDuration = Duration(minutes: 90);
  static const Duration endsemExamDuration = Duration(hours: 3);
}

// ── Algorithm / behavior limits ────────────────────────────────────────

abstract final class AppLimits {
  static const int maxUndoStackSize = 50;
  static const int combinationCap = 10000;
  static const int coursePageSize = 100;
  static const int acadDriveCoursePageSize = 40;
  static const int acadDriveFilePageSize = 200;
  static const int acadDriveFileMaxSize = 5000;
  static const int perfFlushThreshold = 50;
  static const int logFlushThreshold = 50;
  static const int maxPdfSize = 10 * 1024 * 1024; // 10 MB
}

// ── Durations / timeouts ───────────────────────────────────────────────

abstract final class AppDurations {
  static const Duration cacheTimeout = Duration(hours: 24);
  static const Duration versionCheckInterval = Duration(minutes: 5);
  static const Duration perfFlushInterval = Duration(seconds: 30);
  static const Duration logFlushInterval = Duration(seconds: 30);
  static const Duration uploadTimetableTimeout = Duration(minutes: 8);
  static const Duration uploadExamSeatingTimeout = Duration(minutes: 5);
  static const Duration networkTimeout = Duration(seconds: 20);
  static const Duration shortNetworkTimeout = Duration(seconds: 15);
  static const Duration startupReadTimeout = Duration(seconds: 8);
  static const Duration startupPrefetchTimeout = Duration(seconds: 12);
}

// ── Responsive breakpoints & scaling ───────────────────────────────────

abstract final class ResponsiveConstants {
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 900.0;

  static const double minTouchTarget = 48.0;
  static const double preferredTouchTarget = 56.0;
  static const double largeTouchTarget = 64.0;

  static const double mobilePaddingScale = 0.75;
  static const double tabletPaddingScale = 0.9;
  static const double desktopPaddingScale = 1.0;

  static const double mobileFontScale = 0.9;
  static const double tabletFontScale = 0.95;
  static const double desktopFontScale = 1.0;

  static const double mobileMinFontSize = 11.0;
}

// ── Course comparison scoring weights ──────────────────────────────────

abstract final class ComparisonWeights {
  static const double lecture = 0.4;
  static const double tutorial = 0.3;
  static const double practical = 0.3;
  static const double midSem = 0.4;
  static const double endSem = 0.6;
}

// ── App metadata ───────────────────────────────────────────────────────

abstract final class AppMeta {
  static const String logTag = 'TimetableMaker';
}

// ── Tutorial sections ──────────────────────────────────────────────────

abstract final class TutorialSections {
  static const String timetableList = 'timetable_list';
  static const String editor = 'editor';
  static const String cgpa = 'cgpa';
  static const String acadDrives = 'acad_drives';
  static const String admin = 'admin';
}
