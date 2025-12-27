/// Centralized constants and mappings for the Timetable Creator app
class AppConstants {
  /// Valid grades for CGPA calculation
  static const List<String> validGrades = [
    'A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'E', 'F'
  ];

  /// Grade point mapping for CGPA calculation
  static const Map<String, double> gradePoints = {
    'A+': 10.0,
    'A': 10.0,
    'A-': 9.0,
    'B+': 8.0,
    'B': 7.0,
    'B-': 6.0,
    'C+': 5.0,
    'C': 4.0,
    'C-': 3.0,
    'D': 2.0,
    'E': 1.0,
    'F': 0.0,
  };

  /// Common course types
  static const List<String> courseTypes = [
    'CDC',
    'Discipline Elective',
    'Humanities Elective',
    'Open Elective',
    'Research',
    'Practical',
  ];

  /// Time slot constants
  static const List<String> timeSlots = [
    '8:00 AM - 8:50 AM',
    '9:00 AM - 9:50 AM',
    '10:00 AM - 10:50 AM',
    '11:00 AM - 11:50 AM',
    '12:00 PM - 12:50 PM',
    '1:00 PM - 1:50 PM',
    '2:00 PM - 2:50 PM',
    '3:00 PM - 3:50 PM',
    '4:00 PM - 4:50 PM',
    '5:00 PM - 5:50 PM',
  ];

  /// Days of the week
  static const List<String> weekDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Short day names
  static const List<String> shortWeekDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Exam types
  static const List<String> examTypes = [
    'Midsem',
    'Compre',
    'Quiz',
    'Viva',
    'Lab Exam',
  ];

  /// Campus locations
  static const List<String> campusLocations = [
    'Pilani',
    'Goa',
    'Hyderabad',
    'Dubai',
  ];
}

/// Branch-specific constants and mappings
class BranchConstants {
  /// Mapping of branch codes to full names (from discipline_electives_service.dart and humanities_electives_service.dart)
  static const Map<String, String> branchCodeToName = {
    'A1': 'Chemical',
    'A2': 'Civil', 
    'A3': 'Electrical and Electronics',
    'A4': 'Mechanical',
    'A7': 'Computer Science',
    'A8': 'Electronics and Instrumentation',
    'AA': 'Electronics and Communication',
    'AB': 'Electrical and Electronics (Dual)',
    'B1': 'Chemistry',
    'B2': 'Economics',
    'B3': 'English',
    'B4': 'History',
    'B5': 'Philosophy',
    'B6': 'Political Science',
    'B7': 'Psychology',
    'B8': 'Sociology',
    'C1': 'Biological Sciences',
    'C2': 'Mathematics',
    'C3': 'Physics',
    'C4': 'Statistics',
    // Additional mappings found in the codebase
    'D1': 'Pharmacy',
    'D2': 'Biotechnology',
    'D3': 'Food Technology',
    // MSc branches
    'M1': 'Mathematics',
    'M2': 'Physics',
    'M3': 'Chemistry',
    'M4': 'Biological Sciences',
  };

  /// Reverse mapping: full names to branch codes
  static final Map<String, String> branchNameToCode = {
    for (var entry in branchCodeToName.entries) entry.value: entry.key
  };

  /// Engineering branches only
  static const List<String> engineeringBranches = [
    'A1', 'A2', 'A3', 'A4', 'A7', 'A8', 'AA', 'AB'
  ];

  /// Science branches only
  static const List<String> scienceBranches = [
    'B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7', 'B8',
    'C1', 'C2', 'C3', 'C4'
  ];

  /// Pharmacy and Technology branches
  static const List<String> pharmacyTechBranches = [
    'D1', 'D2', 'D3'
  ];

  /// MSc branches
  static const List<String> mscBranches = [
    'M1', 'M2', 'M3', 'M4'
  ];

  /// All undergraduate branches
  static const List<String> undergraduateBranches = [
    ...engineeringBranches,
    ...scienceBranches,
    ...pharmacyTechBranches,
  ];

  /// All branches
  static const List<String> allBranches = [
    ...undergraduateBranches,
    ...mscBranches,
  ];

  /// Get branch name from code
  static String getBranchName(String code) {
    return branchCodeToName[code.toUpperCase()] ?? 'Unknown Branch';
  }

  /// Get branch code from name
  static String? getBranchCode(String name) {
    return branchNameToCode[name];
  }

  /// Check if branch is engineering
  static bool isEngineering(String code) {
    return engineeringBranches.contains(code.toUpperCase());
  }

  /// Check if branch is science
  static bool isScience(String code) {
    return scienceBranches.contains(code.toUpperCase());
  }

  /// Check if branch is MSc
  static bool isMSc(String code) {
    return mscBranches.contains(code.toUpperCase());
  }

  /// Get all branches for a category
  static List<String> getBranchesForCategory(BranchCategory category) {
    switch (category) {
      case BranchCategory.engineering:
        return engineeringBranches;
      case BranchCategory.science:
        return scienceBranches;
      case BranchCategory.pharmacyTech:
        return pharmacyTechBranches;
      case BranchCategory.msc:
        return mscBranches;
      case BranchCategory.undergraduate:
        return undergraduateBranches;
      case BranchCategory.all:
        return allBranches;
    }
  }
}

/// Branch category enumeration
enum BranchCategory {
  engineering,
  science,
  pharmacyTech,
  msc,
  undergraduate,
  all,
}

/// Semester constants
class SemesterConstants {
  /// Available semesters (years)
  static const List<String> availableYears = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year', // For pharmacy
  ];

  /// Semester numbers
  static const List<int> semesterNumbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  /// Academic year semesters
  static const Map<String, List<int>> yearToSemesters = {
    '1st Year': [1, 2],
    '2nd Year': [3, 4],
    '3rd Year': [5, 6],
    '4th Year': [7, 8],
    '5th Year': [9, 10], // For pharmacy
  };

  /// Get semester year from semester number
  static String getSemesterYear(int semesterNumber) {
    if (semesterNumber <= 2) return '1st Year';
    if (semesterNumber <= 4) return '2nd Year';
    if (semesterNumber <= 6) return '3rd Year';
    if (semesterNumber <= 8) return '4th Year';
    return '5th Year';
  }

  /// Get semester numbers for a year
  static List<int> getSemestersForYear(String year) {
    return yearToSemesters[year] ?? [];
  }
}

/// Course-related constants
class CourseConstants {
  /// Lecture hour options
  static const List<int> lectureHours = [0, 1, 2, 3, 4, 5, 6];

  /// Tutorial hour options
  static const List<int> tutorialHours = [0, 1, 2, 3];

  /// Practical hour options
  static const List<int> practicalHours = [0, 1, 2, 3, 4, 5, 6];

  /// Credit options
  static const List<int> creditOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8];

  /// Default units mapping (L-T-P format)
  static const Map<String, List<int>> defaultUnits = {
    '3-0-0': [3, 0, 0], // 3 lecture hours, 0 tutorial, 0 practical
    '2-1-0': [2, 1, 0],
    '3-1-0': [3, 1, 0],
    '2-0-3': [2, 0, 3],
    '1-0-3': [1, 0, 3],
    '0-0-3': [0, 0, 3],
    '4-0-0': [4, 0, 0],
  };

  /// Common course code prefixes
  static const List<String> coursePrefixes = [
    'CS', 'MATH', 'PHY', 'CHEM', 'BIO', 'EEE', 'MECH', 'CIVIL', 'ECE',
    'INSTR', 'ECON', 'ENG', 'HIST', 'PHIL', 'POLI', 'PSY', 'SOC',
    'PHARM', 'BITS', 'GS', 'HSS'
  ];

  /// Course level indicators
  static const Map<String, String> courseLevels = {
    'F1': 'Foundation Level 1',
    'F2': 'Foundation Level 2',
    'F3': 'Foundation Level 3',
    'F4': 'Foundation Level 4',
    'C3': 'Core Level 3',
    'C4': 'Core Level 4',
  };
}

/// UI-related constants
class UIConstants {
  /// Animation durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  /// Border radius values
  static const double smallRadius = 8.0;
  static const double mediumRadius = 12.0;
  static const double largeRadius = 16.0;

  /// Padding values
  static const double smallPadding = 8.0;
  static const double mediumPadding = 16.0;
  static const double largePadding = 24.0;

  /// Icon sizes
  static const double smallIcon = 16.0;
  static const double mediumIcon = 24.0;
  static const double largeIcon = 32.0;

  /// Maximum content width for responsive design
  static const double maxContentWidth = 1200.0;
  
  /// Mobile breakpoint
  static const double mobileBreakpoint = 600.0;
  
  /// Tablet breakpoint
  static const double tabletBreakpoint = 900.0;
}

/// Network and storage constants
class NetworkConstants {
  /// Cache durations
  static const Duration shortCache = Duration(minutes: 5);
  static const Duration mediumCache = Duration(hours: 1);
  static const Duration longCache = Duration(hours: 24);

  /// Request timeouts
  static const Duration shortTimeout = Duration(seconds: 10);
  static const Duration mediumTimeout = Duration(seconds: 30);
  static const Duration longTimeout = Duration(minutes: 2);

  /// Retry counts
  static const int defaultRetryCount = 3;
  static const int maxRetryCount = 5;

  /// Batch sizes for pagination
  static const int smallBatchSize = 25;
  static const int mediumBatchSize = 50;
  static const int largeBatchSize = 100;
}