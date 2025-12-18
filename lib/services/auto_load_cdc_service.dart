import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_guide_service.dart';
import '../services/course_data_service.dart';
import '../services/responsive_service.dart';

class AutoLoadCDCService {
  static final AutoLoadCDCService _instance = AutoLoadCDCService._internal();
  factory AutoLoadCDCService() => _instance;
  AutoLoadCDCService._internal();

  final CourseGuideService _courseGuideService = CourseGuideService();

  final Map<String, String> _branchCodeToName = {
    'A1': 'Chemical',
    'A2': 'Civil',
    'A3': 'Electrical and Electronics',
    'A4': 'Mechanical',
    'A5': 'Pharma',
    'A7': 'Computer Science',
    'A8': 'Electronics and Instrumentation',
    'AA': 'Electronics and Communication',
    'AB': 'Manufacturing',
    'AJ': 'Biotechnology',
    'B1': 'Economics',
    'B2': 'Mathematics',
    'B3': 'Physics',
    'B4': 'Chemistry',
    'B5': 'Biology',
  };

  Future<AutoLoadCDCResult?> showBranchYearDialog(BuildContext context) async {
    return await showDialog<AutoLoadCDCResult?>(
      context: context,
      builder: (BuildContext context) => const AutoLoadCDCDialog(),
    );
  }

  Future<List<SelectedSection>> loadCDCsForBranchAndSemester({
    required String branch,
    required String semester,
    required List<Course> availableCourses,
  }) async {
    try {
      print('Loading CDCs for branch: $branch, semester: $semester');

      // Load course guide data
      final semesters = await _courseGuideService.getAllSemesters();
      
      // Convert semester format (e.g., "3-1" to "semester_3_1")
      final semesterId = 'semester_${semester.replaceAll('-', '_')}';
      
      final cdcCourses = <CourseGuideEntry>[];
      
      // Find the specific semester
      final targetSemester = semesters.where((s) => s.semesterId == semesterId).firstOrNull;
      if (targetSemester != null) {
        // Get the full branch name for searching
        final branchFullName = _branchCodeToName[branch];
        
        for (final group in targetSemester.groups) {
          // Check if group contains either the branch code or the full branch name
          bool containsBranch = group.branches.contains(branch) || 
                               (branchFullName != null && group.branches.contains(branchFullName));
          
          if (containsBranch) {
            cdcCourses.addAll(group.courses);
            print('Found group ${group.groupId} with ${group.courses.length} courses for branch $branch (${branchFullName ?? branch})');
          }
        }
      } else {
        print('Semester $semesterId not found in course guide');
      }

      print('Found ${cdcCourses.length} CDC courses for $branch semester $semester');

      // Convert to SelectedSection objects by finding available lecture sections
      final selectedSections = <SelectedSection>[];

      for (final cdcCourse in cdcCourses) {
        final course = availableCourses.where((c) => c.courseCode == cdcCourse.code).firstOrNull;
        if (course != null) {
          // Find all lecture sections and try each one until we find one without conflicts
          final lectureSections = course.sections.where((s) => s.type == SectionType.L).toList();
          bool added = false;
          
          for (final lectureSection in lectureSections) {
            // Create a temporary SelectedSection to test for conflicts
            final tempSection = SelectedSection(
              courseCode: course.courseCode,
              sectionId: lectureSection.sectionId,
              section: lectureSection,
            );
            
            // Check if this section conflicts with already selected sections
            bool hasConflict = false;
            for (final existing in selectedSections) {
              if (_hasTimeConflict(tempSection.section, existing.section)) {
                hasConflict = true;
                break;
              }
            }
            
            if (!hasConflict) {
              selectedSections.add(tempSection);
              print('Auto-loaded: ${course.courseCode} - ${lectureSection.sectionId}');
              added = true;
              break;
            }
          }
          
          if (!added && lectureSections.isNotEmpty) {
            print('Could not add ${course.courseCode} - all lecture sections have conflicts');
          }
        }
      }

      print('Successfully loaded ${selectedSections.length} CDC sections');
      return selectedSections;
    } catch (e) {
      print('Error loading CDCs: $e');
      rethrow;
    }
  }

  bool _hasTimeConflict(Section section1, Section section2) {
    // Check if sections have time conflicts
    for (final entry1 in section1.schedule) {
      for (final entry2 in section2.schedule) {
        // Check if they share any common days
        final commonDays = entry1.days.where((day) => entry2.days.contains(day));
        if (commonDays.isNotEmpty) {
          // Check for hour overlap
          final hours1 = Set.from(entry1.hours);
          final hours2 = Set.from(entry2.hours);
          if (hours1.intersection(hours2).isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

class AutoLoadCDCResult {
  final String branch;
  final String year;

  AutoLoadCDCResult({required this.branch, required this.year});
}

class AutoLoadCDCDialog extends StatefulWidget {
  const AutoLoadCDCDialog({super.key});

  @override
  State<AutoLoadCDCDialog> createState() => _AutoLoadCDCDialogState();
}

class _AutoLoadCDCDialogState extends State<AutoLoadCDCDialog> {
  final List<String> _branches = [
    'A1', 'A2', 'A3', 'A4', 'A5', 'A7', 'A8', 'AA', 'AB', 'AJ', 'B1', 'B2', 'B3', 'B4', 'B5'
  ];

  final List<String> _semesters = ['1-1', '1-2', '2-1', '2-2', '3-1', '3-2', '4-1', '4-2'];

  String? _selectedBranch;
  String? _selectedSemester;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.school,
            color: Theme.of(context).colorScheme.primary,
            size: ResponsiveService.getAdaptiveIconSize(context, 24),
          ),
          SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
          Expanded(
            child: Text(
              'Auto Load CDCs',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 20),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: ResponsiveService.getValue(context, 
          mobile: MediaQuery.of(context).size.width - 32,
          tablet: 400, 
          desktop: 350
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select your branch and year to automatically load Core Discipline Courses (CDCs):',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 20)),
            
            // Branch Selection
            Text(
              'Branch *',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            DropdownButtonFormField<String>(
              value: _selectedBranch,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              ),
              items: _branches.map((branch) {
                return DropdownMenuItem<String>(
                  value: branch,
                  child: Text(branch),
                );
              }).toList(),
              onChanged: (String? newValue) {
                ResponsiveService.triggerSelectionFeedback(context);
                setState(() {
                  _selectedBranch = newValue;
                });
              },
              isExpanded: true,
              hint: const Text('Select your branch'),
            ),
            
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),
            
            // Semester Selection
            Text(
              'Semester *',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            DropdownButtonFormField<String>(
              value: _selectedSemester,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              ),
              items: _semesters.map((semester) {
                return DropdownMenuItem<String>(
                  value: semester,
                  child: Text('Semester $semester'),
                );
              }).toList(),
              onChanged: (String? newValue) {
                ResponsiveService.triggerSelectionFeedback(context);
                setState(() {
                  _selectedSemester = newValue;
                });
              },
              isExpanded: true,
              hint: const Text('Select your semester'),
            ),
            
            // Mobile actions inline
            if (isMobile) ...[
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 20)),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    ResponsiveService.triggerSelectionFeedback(context);
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    minimumSize: Size(
                      double.infinity,
                      ResponsiveService.getTouchTargetSize(context),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_selectedBranch != null && _selectedSemester != null) 
                    ? () {
                        ResponsiveService.triggerMediumFeedback(context);
                        Navigator.of(context).pop(AutoLoadCDCResult(
                          branch: _selectedBranch!,
                          year: _selectedSemester!,
                        ));
                      }
                    : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: Size(
                      double.infinity,
                      ResponsiveService.getTouchTargetSize(context),
                    ),
                  ),
                  icon: Icon(Icons.download, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
                  label: const Text('Load CDCs'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: isMobile ? null : [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: (_selectedBranch != null && _selectedSemester != null) 
            ? () {
                Navigator.of(context).pop(AutoLoadCDCResult(
                  branch: _selectedBranch!,
                  year: _selectedSemester!,
                ));
              }
            : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Load CDCs'),
        ),
      ],
    );
  }
}