import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../widgets/common/empty_state_widget.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/core/course_comparison_service.dart';
import '../services/data/humanities_electives_service.dart';
import '../services/data/discipline_electives_service.dart';
import '../services/core/clash_detector.dart';
import '../services/core/timetable_repair_service.dart';
import '../services/data/campus_service.dart';
import '../services/data/profile_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../services/ui/secure_logger.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../utils/design_constants.dart';
import '../utils/page_info_helper.dart';

enum CourseCategory { huel, del, other }

class QuickReplaceScreen extends StatefulWidget {
  final List<Course> availableCourses;
  final List<SelectedSection> selectedSections;
  final Function(Course selectedCourse, Course replacementCourse) onReplace;
  final Function(List<SelectedSection> newSections)? onSectionShuffle;
  final CreditBasis creditBasis;

  const QuickReplaceScreen({
    super.key,
    required this.availableCourses,
    required this.selectedSections,
    required this.onReplace,
    this.onSectionShuffle,
    this.creditBasis = CreditBasis.units,
  });

  @override
  State<QuickReplaceScreen> createState() => _QuickReplaceScreenState();
}

class _QuickReplaceScreenState extends State<QuickReplaceScreen> {
  int _selectedTab = 0;
  Course? _selectedCourse;
  List<CourseComparison> _similarCourses = [];
  bool _isLoading = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  
  // Category filtering
  bool _isLoadingCategories = false;
  Set<String> _huelCourses = {};
  Set<String> _delCourses = {};
  final Set<CourseCategory> _selectedCategories = {CourseCategory.huel, CourseCategory.other}; // DEL not selected by default
  
  // DEL-specific filtering parameters
  List<BranchInfo> _availableBranches = [];
  String? _primaryBranch;
  String? _secondaryBranch;
  String? _primarySemester;
  String? _secondarySemester;
  
  // UI state
  bool _isSearchParamsExpanded = true;
  
  final HumanitiesElectivesService _huelService = HumanitiesElectivesService();
  final DisciplineElectivesService _delService = DisciplineElectivesService();
  
  static final List<String> _semesterOptions = SemesterConstants.yearsOneToThree;

  // Section shuffle state
  Course? _shuffleCourse;
  Set<String> _closedSectionIds = {};
  List<TimetableRepairPlan> _shuffleResults = [];
  bool _isShuffling = false;
  bool _hasSearchedRepairs = false;
  bool _preserveFreeDays = true;
  bool _preserveInstructors = true;
  final Set<String> _lockedRepairCourses = {};
  bool _isPlanningReplacement = false;
  String? _planningReplacementCode;

  @override
  void initState() {
    super.initState();
    _loadCourseCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Pre-selects the student's saved branch and semester for the DEL filters,
  /// so choosing the DEL category doesn't mean re-entering what the profile
  /// already knows. Everything stays editable.
  void _prefillFromProfile() {
    final profile = ProfileService().cached;
    final codes = _availableBranches.map((b) => b.code).toSet();

    if (profile.primaryBranch != null && codes.contains(profile.primaryBranch)) {
      _primaryBranch = profile.primaryBranch;
    }
    // The secondary dropdown excludes the primary, so never pre-fill it to the
    // same branch.
    if (profile.secondaryBranch != null &&
        profile.secondaryBranch != _primaryBranch &&
        codes.contains(profile.secondaryBranch)) {
      _secondaryBranch = profile.secondaryBranch;
    }
    if (profile.currentSemester != null &&
        _semesterOptions.contains(profile.currentSemester)) {
      _primarySemester = profile.currentSemester;
    }
  }

  Future<void> _loadCourseCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      // Branches are needed for the DEL dropdowns; DEL courses themselves load
      // lazily only once a branch/semester is chosen.
      _availableBranches = await _delService.getAvailableBranches();
      _prefillFromProfile();

      final huelCourses = await _huelService.getAllHumanitiesElectives(widget.availableCourses);
      _huelCourses = huelCourses.map((course) => course.courseCode).toSet();
    } catch (e) {
      SecureLogger.warning('QuickReplace', 'Failed to load course categories', {'error': e.toString()});
    } finally {
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }
  
  // Load DEL courses based on selected branch and semester
  Future<void> _loadDelCourses() async {
    if (_primaryBranch != null && _primarySemester != null) {
      try {
        // Load filtered DEL courses with clash detection
        final delElectives = await _delService.getFilteredDisciplineElectivesWithClashDetection(
          _primaryBranch!,
          _secondaryBranch,
          _primarySemester!,
          _secondarySemester,
          widget.availableCourses,
        );
        _delCourses = delElectives.map((del) => del.courseCode).toSet();
      } catch (e) {
        // Fallback to all DEL courses
        await _loadAllDelCourses();
      }
    } else {
      // Load all DEL courses if no specific branch/semester selected
      await _loadAllDelCourses();
    }
  }
  
  // Load all DEL courses (fallback method)
  Future<void> _loadAllDelCourses() async {
    final allDelCourses = <String>{};
    
    for (final branch in _availableBranches) {
      final delCourses = await _delService.getDisciplineElectives(branch.code);
      allDelCourses.addAll(delCourses.map((course) => course.courseCode));
    }
    _delCourses = allDelCourses;
  }

  List<Course> get _selectedCourses {
    final selectedCourseCodes = widget.selectedSections
        .map((section) => section.courseCode)
        .toSet();
    
    return widget.availableCourses
        .where((course) => selectedCourseCodes.contains(course.courseCode))
        .toList();
  }

  CourseCategory _getCourseCategory(String courseCode) {
    if (_huelCourses.contains(courseCode)) {
      return CourseCategory.huel;
    } else if (_delCourses.contains(courseCode)) {
      return CourseCategory.del;
    } else {
      return CourseCategory.other;
    }
  }

  String _getCategoryDisplayName(CourseCategory category) {
    switch (category) {
      case CourseCategory.huel:
        return 'HUELs';
      case CourseCategory.del:
        return 'DELs';
      case CourseCategory.other:
        return 'Other';
    }
  }
  
  bool _canSearch() {
    // Must have selected a course
    if (_selectedCourse == null) return false;
    
    // Must have selected at least one category
    if (_selectedCategories.isEmpty) return false;
    
    // If DEL is selected, must have branch and semester
    if (_selectedCategories.contains(CourseCategory.del)) {
      if (_primaryBranch == null || _primarySemester == null) {
        return false;
      }
    }
    
    return true;
  }
  
  String _getValidationMessage() {
    if (_selectedCourse == null) {
      return 'Please select a course to replace';
    }
    
    if (_selectedCategories.isEmpty) {
      return 'Please select at least one course category';
    }
    
    if (_selectedCategories.contains(CourseCategory.del)) {
      if (_primaryBranch == null || _primarySemester == null) {
        return 'Please select branch and semester for DEL courses';
      }
    }
    
    return '';
  }

  void _findSimilarCourses() async {
    if (_selectedCourse == null) return;

    setState(() {
      _isLoading = true;
    });

    // Find similar courses in a microtask to avoid blocking UI
    await Future.microtask(() {
      // First filter available courses by selected categories
      final filteredCoursePool = _getFilteredCoursePool();
      
      final comparisons = CourseComparisonService.findSimilarCourses(
        _selectedCourse!,
        filteredCoursePool,
        limit: 50, // Increased limit since we're pre-filtering
      );
      
      setState(() {
        _similarCourses = comparisons;
        _isLoading = false;
      });
    });
  }
  
  // Get filtered course pool based on selected categories
  List<Course> _getFilteredCoursePool() {
    if (_selectedCategories.isEmpty) {
      return []; // No courses if no categories selected
    }
    
    return widget.availableCourses.where((course) {
      final category = _getCourseCategory(course.courseCode);
      return _selectedCategories.contains(category);
    }).toList();
  }

  List<CourseComparison> get _filteredCourses {
    // Only apply search text filtering since category filtering happens at course pool level
    if (_searchText.isEmpty) return _similarCourses;
    
    final lowercaseSearch = _searchText.toLowerCase();
    return _similarCourses
        .where((comparison) =>
            comparison.course.courseCode.toLowerCase().contains(lowercaseSearch) ||
            comparison.course.courseTitle.toLowerCase().contains(lowercaseSearch))
        .toList();
  }

  Future<void> _performReplace(Course replacementCourse) async {
    if (widget.onSectionShuffle == null) {
      _performLegacyReplace(replacementCourse);
      return;
    }

    setState(() {
      _isPlanningReplacement = true;
      _planningReplacementCode = replacementCourse.courseCode;
    });
    final plans = await Future(
      () => TimetableRepairService.planCourseReplacement(
        currentSections: widget.selectedSections,
        availableCourses: widget.availableCourses,
        sourceCourseCode: _selectedCourse!.courseCode,
        replacementCourse: replacementCourse,
        creditBasis: widget.creditBasis,
        preferences: _repairPreferences,
      ),
    );
    if (!mounted) return;
    setState(() {
      _isPlanningReplacement = false;
      _planningReplacementCode = null;
    });

    if (plans.isEmpty) {
      ToastService.showWarning(
        'No clash-free repair found without moving protected courses.',
      );
      return;
    }
    _showRepairPlanPicker(
      title: 'Replace ${_selectedCourse!.courseCode}',
      subtitle:
          'Plans are ranked by collateral changes, free days, instructors, and timing drift.',
      plans: plans,
    );
  }

  TimetableRepairPreferences get _repairPreferences =>
      TimetableRepairPreferences(
        preserveFreeDays: _preserveFreeDays,
        preserveInstructors: _preserveInstructors,
        lockedCourseCodes: _lockedRepairCourses,
      );

  void _showRepairPlanPicker({
    required String title,
    required String subtitle,
    required List<TimetableRepairPlan> plans,
  }) {
    AppDialog.adaptive(
      context: context,
      title: title,
      icon: Icons.auto_fix_high_outlined,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (var index = 0; index < plans.take(5).length; index++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(
                    plans[index].isDirect
                        ? 'Minimum-disruption fit'
                        : plans[index].impactLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${plans[index].changes.length} total '
                    '${plans[index].changes.length == 1 ? 'change' : 'changes'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showRepairPreview(plans[index]);
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Continue Browsing',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _showRepairPreview(TimetableRepairPlan plan) {
    AppDialog.adaptive(
      context: context,
      title: 'Preview repair',
      icon: Icons.fact_check_outlined,
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    plan.isDirect
                        ? AppDesign.success(context).withValues(alpha: 0.1)
                        : Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                plan.impactLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            for (final change in plan.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      change.requested
                          ? Icons.build_outlined
                          : Icons.call_split_outlined,
                      size: 17,
                      color:
                          change.requested
                              ? Theme.of(context).colorScheme.primary
                              : AppDesign.warning(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(change.summary),
                          if (change.instructorChanged)
                            Text(
                              '${change.fromInstructor} -> ${change.toInstructor}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (plan.lostFreeDays.isNotEmpty)
              Text(
                'Free days lost: ${plan.lostFreeDays.map((day) => day.name).join(', ')}',
                style: TextStyle(color: AppDesign.warning(context)),
              ),
          ],
        ),
      ),
      actions: [
        AppButton(label: 'Cancel', onTap: () => Navigator.of(context).pop()),
        AppButton(
          label: 'Apply Repair',
          onTap: () {
            Navigator.of(context).pop();
            widget.onSectionShuffle?.call(plan.newSections);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _performLegacyReplace(Course replacementCourse) {
    // Check if both courses have only lecture sections
    if (!_canReplaceCourses(_selectedCourse!, replacementCourse)) {
      ToastService.showWarning('Can only replace between courses that have only lecture sections');
      return;
    }

    final clashCheckResult = _checkForClashes(replacementCourse);
    if (clashCheckResult.hasClashes) {
      _showClashDialog(replacementCourse, clashCheckResult.clashWarnings);
      return;
    }

    widget.onReplace(_selectedCourse!, replacementCourse);
    
    ToastService.showSuccess(
      'Replaced ${_selectedCourse!.courseCode} with ${replacementCourse.courseCode}',
    );
    
    Navigator.of(context).pop();
  }

  bool _canReplaceCourses(Course selectedCourse, Course replacementCourse) {
    return CourseComparisonService.hasOnlyLectureSections(selectedCourse) && 
           CourseComparisonService.hasOnlyLectureSections(replacementCourse);
  }

  ClashCheckResult _checkForClashes(Course replacementCourse) {
    final tempSelectedSections = widget.selectedSections
        .where((section) => section.courseCode != _selectedCourse!.courseCode)
        .toList();
    
    final replacementSections = replacementCourse.sections;
    final lectureSection = replacementSections
        .where((s) => s.type == SectionType.L)
        .isNotEmpty ? replacementSections.firstWhere((s) => s.type == SectionType.L) : null;
    
    final tutorialSection = replacementSections
        .where((s) => s.type == SectionType.T)
        .isNotEmpty ? replacementSections.firstWhere((s) => s.type == SectionType.T) : null;
    
    final practicalSection = replacementSections
        .where((s) => s.type == SectionType.P)
        .isNotEmpty ? replacementSections.firstWhere((s) => s.type == SectionType.P) : null;

    if (lectureSection != null) {
      tempSelectedSections.add(SelectedSection(
        courseCode: replacementCourse.courseCode,
        sectionId: lectureSection.sectionId,
        section: lectureSection,
      ));
    }
    
    if (tutorialSection != null) {
      tempSelectedSections.add(SelectedSection(
        courseCode: replacementCourse.courseCode,
        sectionId: tutorialSection.sectionId,
        section: tutorialSection,
      ));
    }
    
    if (practicalSection != null) {
      tempSelectedSections.add(SelectedSection(
        courseCode: replacementCourse.courseCode,
        sectionId: practicalSection.sectionId,
        section: practicalSection,
      ));
    }

    final clashes = ClashDetector.detectClashes(tempSelectedSections, widget.availableCourses);
    final errorClashes = clashes.where((clash) => clash.severity == ClashSeverity.error).toList();
    
    return ClashCheckResult(
      hasClashes: errorClashes.isNotEmpty,
      clashWarnings: errorClashes,
    );
  }

  void _showClashDialog(Course replacementCourse, List<ClashWarning> clashes) {
    AppDialog.adaptive(
      context: context,
      title: 'Clash Detected',
      icon: Icons.warning,
      iconColor: Theme.of(context).colorScheme.error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Replacing ${_selectedCourse!.courseCode} with ${replacementCourse.courseCode} would cause the following clashes:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ...clashes.map((clash) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    clash.message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
      actions: [
        AppButton(
          label: 'Continue Browsing',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Quick Replace',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [PageInfoHelper.infoButton(context, PageInfoHelper.quickReplace)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Replace Course'), icon: Icon(Icons.swap_horiz, size: 18)),
                    ButtonSegment(value: 1, label: Text('Section Shuffle'), icon: Icon(Icons.shuffle, size: 18)),
                  ],
                  selected: {_selectedTab},
                  onSelectionChanged: (set) => setState(() => _selectedTab = set.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: scheme.primaryContainer,
                    selectedForegroundColor: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _selectedTab == 0 ? _buildReplaceCourseTab() : _buildSectionShuffleTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplaceCourseTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildCourseSelection(),
        if (_selectedCourse != null) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: _buildCompactCourseDetails(_selectedCourse!),
          ),
        ],
        _buildSearchParameters(),
        if (_selectedCourse != null) ...[
          if (_similarCourses.isNotEmpty || _isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Similar Courses (${_filteredCourses.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (_similarCourses.isNotEmpty && !_isLoading) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: TextFormField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          hintText: 'Search in results...',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          suffixIcon: _searchText.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _searchText = '';
                                      _searchController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchText = value;
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: _similarCourses.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ready to find courses',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Find Similar Courses" when ready',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Finding similar courses...'),
                          ],
                        ),
                      )
                    : _buildCompactSimilarCoursesList(),
          ),
        ] else ...[
          Expanded(
            child: _buildEmptyState(),
          ),
        ],
      ],
    );
  }

  Widget _buildCourseSelection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.swap_horiz,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Course to Replace',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Custom styled dropdown with better theming
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Theme.of(context).colorScheme.surface,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: DropdownButtonFormField<Course>(
                initialValue: _selectedCourse,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  hintText: 'Choose a course from your timetable...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.book_outlined, 
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                isExpanded: true,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                selectedItemBuilder: (context) {
                  return _selectedCourses.map((course) {
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            course.courseCode,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            course.courseTitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                items: _selectedCourses.map((course) {
                  return DropdownMenuItem(
                    value: course,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              course.courseCode,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              course.courseTitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (course) {
                  setState(() {
                    _selectedCourse = course;
                    _similarCourses.clear();
                    _searchText = '';
                    _searchController.clear();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Select a course from your timetable',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Find time-similar alternatives to replace it with',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCourseDetails(Course course) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              course.courseCode,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                course.courseTitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildCompactScheduleInfo(course),
      ],
    );
  }

  Widget _buildCompactScheduleInfo(Course course) {
    final List<Widget> items = [];

    // Lectures
    final lectures = course.sections.where((s) => s.type == SectionType.L).toList();
    if (lectures.isNotEmpty) {
      items.add(_buildCompactSection('L', lectures.first));
    }

    // Tutorials
    final tutorials = course.sections.where((s) => s.type == SectionType.T).toList();
    if (tutorials.isNotEmpty) {
      items.add(_buildCompactSection('T', tutorials.first));
    }

    // Practicals
    final practicals = course.sections.where((s) => s.type == SectionType.P).toList();
    if (practicals.isNotEmpty) {
      items.add(_buildCompactSection('P', practicals.first));
    }

    // Exams
    if (course.midSemExam != null || course.endSemExam != null) {
      final examTexts = <String>[];
      if (course.midSemExam != null) {
        examTexts.add('MidSem: ${course.midSemExam!.date.day}/${course.midSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.midSemExam!.timeSlot, campus: CampusService.campusId)}');
      }
      if (course.endSemExam != null) {
        examTexts.add('EndSem: ${course.endSemExam!.date.day}/${course.endSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.endSemExam!.timeSlot, campus: CampusService.campusId)}');
      }
      items.add(
        Row(
          children: [
            Icon(Icons.quiz, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                examTexts.join(', '),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: item,
      )).toList(),
    );
  }

  Widget _buildCompactSection(String type, Section section) {
    IconData icon;
    switch (type) {
      case 'L':
        icon = Icons.school;
        break;
      case 'T':
        icon = Icons.groups;
        break;
      case 'P':
        icon = Icons.science;
        break;
      default:
        icon = Icons.book;
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${section.sectionId}: ${TimeSlotInfo.getFormattedSchedule(section.schedule)}',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }



  Widget _buildCompactSimilarCoursesList() {
    if (_filteredCourses.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.search_off,
        title: 'No similar courses found',
        subtitle: 'Try adjusting your search or filters',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _filteredCourses.length,
      itemBuilder: (context, index) {
        final comparison = _filteredCourses[index];
        return _buildCompactCourseCard(comparison);
      },
    );
  }

  Widget _buildCompactCourseCard(CourseComparison comparison) {
    final course = comparison.course;
    final score = comparison.similarityScore;
    final canReplace =
        course.sections.isNotEmpty &&
        (widget.onSectionShuffle != null ||
            _canReplaceCourses(_selectedCourse!, course));
    final isPlanning =
        _isPlanningReplacement && _planningReplacementCode == course.courseCode;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: InkWell(
        onTap: canReplace ? () => _performReplace(course) : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: canReplace ? 1.0 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  course.courseCode,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color:
                                        canReplace
                                            ? null
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (!_isLoadingCategories)
                                  _buildCategoryBadge(
                                    _getCourseCategory(course.courseCode),
                                  ),
                              ],
                            ),
                          ),
                          if (!canReplace)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppDesign.warning(
                                  context,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppDesign.warning(context),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Mixed Sections',
                                style: TextStyle(
                                  fontSize: ResponsiveService.clampedFontSize(
                                    context,
                                    9,
                                  ),
                                  fontWeight: FontWeight.w600,
                                  color: AppDesign.warning(context),
                                ),
                              ),
                            ),
                          if (canReplace)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getSimilarityColor(
                                  score,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _getSimilarityColor(score),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${(score * 100).round()}%',
                                style: TextStyle(
                                  fontSize: ResponsiveService.clampedFontSize(
                                    context,
                                    10,
                                  ),
                                  fontWeight: FontWeight.w600,
                                  color: _getSimilarityColor(score),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        course.courseTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              canReplace
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: 0.7)
                                  : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildCompactScheduleInfo(course),
                    ],
                  ),
                ),
                if (isPlanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    canReplace ? Icons.arrow_forward : Icons.block,
                    size: 16,
                    color:
                        canReplace
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getSimilarityColor(double score) {
    if (score >= 0.8) return AppDesign.success(context);
    if (score >= 0.6) return AppDesign.warning(context);
    if (score >= 0.4) return Theme.of(context).colorScheme.error;
    return AppDesign.danger(context);
  }

  Widget _buildCategoryBadge(CourseCategory category) {
    Color badgeColor;
    String categoryText;
    
    switch (category) {
      case CourseCategory.huel:
        badgeColor = Theme.of(context).colorScheme.tertiary;
        categoryText = 'HUEL';
        break;
      case CourseCategory.del:
        badgeColor = AppDesign.info(context);
        categoryText = 'DEL';
        break;
      case CourseCategory.other:
        badgeColor = AppDesign.muted(context);
        categoryText = 'OTHER';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor, width: 0.5),
      ),
      child: Text(
        categoryText,
        style: TextStyle(
          fontSize: ResponsiveService.clampedFontSize(context, 8),
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }

  Widget _buildSearchParameters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible Header
          InkWell(
            onTap: () {
              setState(() {
                _isSearchParamsExpanded = !_isSearchParamsExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _isSearchParamsExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Search Parameters',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedCategories.isNotEmpty)
                    Text(
                      '${_selectedCategories.length} selected',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _isSearchParamsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          
          // Expandable Content
          if (_isSearchParamsExpanded) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Course Category Selection
                  Text(
                    'Course Categories',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySelection(),
                  
                  const SizedBox(height: 16),
                  
                  // DEL-specific parameters (shown only if DEL is selected)
                  if (_selectedCategories.contains(CourseCategory.del))
                    _buildDelParametersSection(),
                  
                  const SizedBox(height: 16),
                  
                  // Find Courses Button
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        FilledButton.icon(
                          onPressed: _canSearch() 
                              ? () => _findSimilarCourses()
                              : null,
                          icon: _isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.search, size: 20),
                          label: Text(
                            _isLoading ? 'Finding Courses...' : 'Find Similar Courses',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            minimumSize: const Size(double.infinity, 44),
                          ),
                        ),
                        
                        // Validation messages
                        if (!_canSearch())
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _getValidationMessage(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build category selection chips
  Widget _buildCategorySelection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: CourseCategory.values.map((category) {
        final isSelected = _selectedCategories.contains(category);
        final categoryName = _getCategoryDisplayName(category);
        
        return FilterChip(
          selected: isSelected,
          label: Text(
            categoryName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected 
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          onSelected: (selected) async {
            setState(() {
              if (selected) {
                _selectedCategories.add(category);
              } else {
                _selectedCategories.remove(category);
                // Clear DEL courses when DEL category is deselected
                if (category == CourseCategory.del) {
                  _delCourses.clear();
                }
              }
            });
            
            // Load DEL courses only when DEL category is selected AND we have branch/semester
            if (category == CourseCategory.del && selected) {
              await _loadDelCourses();
              setState(() {});
            }
          },
          selectedColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          side: BorderSide(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        );
      }).toList(),
    );
  }

  // Build DEL parameters section  
  Widget _buildDelParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppDesign.info(context).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppDesign.info(context).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: AppDesign.info(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'DEL Parameters',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppDesign.info(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Primary Branch and Semester
              Text(
                'Primary Branch & Semester',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _primaryBranch,
                        decoration: InputDecoration(
                          labelText: 'Branch',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: _availableBranches.map((branch) {
                          return DropdownMenuItem(
                            value: branch.name,
                            child: Text(
                              branch.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          setState(() {
                            _primaryBranch = value;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _primarySemester,
                        decoration: InputDecoration(
                          labelText: 'Semester',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: _semesterOptions.map((semester) {
                          return DropdownMenuItem(
                            value: semester,
                            child: Text(
                              semester,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          setState(() {
                            _primarySemester = value;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Secondary Branch and Semester
              Text(
                'Secondary Branch & Semester',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _secondaryBranch,
                        decoration: InputDecoration(
                          labelText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'Branch',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          ..._availableBranches.map((branch) {
                            return DropdownMenuItem(
                              value: branch.name,
                              child: Text(
                                branch.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) async {
                          setState(() {
                            _secondaryBranch = value;
                            if (value == null) _secondarySemester = null;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _secondarySemester,
                        decoration: InputDecoration(
                          labelText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'Semester',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          ..._semesterOptions.map((semester) {
                            return DropdownMenuItem(
                              value: semester,
                              child: Text(
                                semester,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: _secondaryBranch != null ? (value) async {
                          setState(() {
                            _secondarySemester = value;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        } : null,
                      ),
                    ),
                  ),
                ],
              ),
              
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─── Section Shuffle Tab ───

  Widget _buildSectionShuffleTab() {
    final scheme = Theme.of(context).colorScheme;
    final coursesInTimetable = _getCoursesInTimetable();

    return Column(
      children: [
        const SizedBox(height: 16),
        // Course picker
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String>(
            initialValue: _shuffleCourse?.courseCode,
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Course to shuffle',
              hint: 'Pick a course from your timetable',
            ),
            items:
                coursesInTimetable
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.courseCode,
                        child: Text(
                          '${c.courseCode} — ${c.courseTitle}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (code) {
              if (code == null) return;
              final course = coursesInTimetable.firstWhere(
                (c) => c.courseCode == code,
              );
              setState(() {
                _shuffleCourse = course;
                _closedSectionIds = {};
                _shuffleResults = [];
                _lockedRepairCourses.clear();
                _hasSearchedRepairs = false;
              });
            },
          ),
        ),

        if (_shuffleCourse != null) ...[
          const SizedBox(height: 12),
          // Section chips — mark closed
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildClosedSectionPicker(scheme),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildRepairPriorities(scheme),
          ),

          const SizedBox(height: 12),
          // Find alternatives button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _closedSectionIds.isEmpty || _isShuffling
                        ? null
                        : _runShuffle,
                icon:
                    _isShuffling
                        ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                        : const Icon(Icons.shuffle, size: 18),
                label: Text(
                  _isShuffling ? 'Searching...' : 'Find Alternatives',
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),
        // Results
        Expanded(
          child:
              _shuffleResults.isEmpty
                  ? EmptyStateWidget(
                    icon:
                        _shuffleCourse == null
                            ? Icons.touch_app_outlined
                            : Icons.find_replace,
                    title:
                        _shuffleCourse == null
                            ? 'Select a course to get started'
                            : _closedSectionIds.isEmpty
                            ? 'Mark closed sections, then tap Find Alternatives'
                            : _hasSearchedRepairs
                            ? 'No clash-free repair found with these protections'
                            : 'No results yet',
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _shuffleResults.length,
                    itemBuilder:
                        (context, index) => _buildShuffleResultCard(
                          _shuffleResults[index],
                          scheme,
                        ),
                  ),
        ),
      ],
    );
  }

  List<Course> _getCoursesInTimetable() {
    final codes = widget.selectedSections.map((s) => s.courseCode).toSet();
    return widget.availableCourses
        .where((c) => codes.contains(c.courseCode))
        .toList();
  }

  Widget _buildClosedSectionPicker(ColorScheme scheme) {
    final course = _shuffleCourse!;
    final currentSections =
        widget.selectedSections
            .where((s) => s.courseCode == course.courseCode)
            .toList();

    // Group all sections by type
    final sectionsByType = <SectionType, List<Section>>{};
    for (final s in course.sections) {
      sectionsByType.putIfAbsent(s.type, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mark closed sections:',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        for (final type in sectionsByType.keys) ...[
          Text(
            type == SectionType.L
                ? 'Lecture'
                : type == SectionType.T
                ? 'Tutorial'
                : 'Practical',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children:
                sectionsByType[type]!.map((section) {
                  final isCurrent = currentSections.any(
                    (s) => s.sectionId == section.sectionId,
                  );
                  final isClosed = _closedSectionIds.contains(
                    section.sectionId,
                  );
                  return FilterChip(
                    label: Text(
                      '${section.sectionId}${isCurrent ? ' (current)' : ''}',
                      style: TextStyle(fontSize: 12),
                    ),
                    selected: isClosed,
                    selectedColor: scheme.error.withValues(alpha: 0.2),
                    checkmarkColor: scheme.error,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _closedSectionIds.add(section.sectionId);
                        } else {
                          _closedSectionIds.remove(section.sectionId);
                        }
                        _shuffleResults = [];
                        _hasSearchedRepairs = false;
                      });
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildRepairPriorities(ColorScheme scheme) {
    final movableCourses =
        _getCoursesInTimetable()
            .where((course) => course.courseCode != _shuffleCourse?.courseCode)
            .toList();

    void invalidateResults(VoidCallback update) {
      setState(() {
        update();
        _shuffleResults = [];
        _hasSearchedRepairs = false;
      });
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        leading: const Icon(Icons.shield_outlined, size: 19),
        title: const Text(
          'Repair priorities',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _lockedRepairCourses.isEmpty
              ? 'Minimise disruption automatically'
              : '${_lockedRepairCourses.length} protected '
                  '${_lockedRepairCourses.length == 1 ? 'course' : 'courses'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('Prefer preserving free days'),
            value: _preserveFreeDays,
            onChanged:
                (value) => invalidateResults(() => _preserveFreeDays = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('Prefer the same instructors'),
            value: _preserveInstructors,
            onChanged:
                (value) =>
                    invalidateResults(() => _preserveInstructors = value),
          ),
          if (movableCourses.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Text(
                  'Do not move these courses',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final course in movableCourses)
                    FilterChip(
                      label: Text(course.courseCode),
                      selected: _lockedRepairCourses.contains(
                        course.courseCode,
                      ),
                      onSelected:
                          (selected) => invalidateResults(() {
                            if (selected) {
                              _lockedRepairCourses.add(course.courseCode);
                            } else {
                              _lockedRepairCourses.remove(course.courseCode);
                            }
                          }),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _runShuffle() {
    setState(() {
      _isShuffling = true;
      _shuffleResults = [];
    });

    // Run async to not block UI
    Future(() {
      final results = _computeShuffleResults();
      if (mounted) {
        setState(() {
          _shuffleResults = results;
          _isShuffling = false;
          _hasSearchedRepairs = true;
        });
      }
    });
  }

  List<TimetableRepairPlan> _computeShuffleResults() =>
      TimetableRepairService.planSectionRepair(
        currentSections: widget.selectedSections,
        availableCourses: widget.availableCourses,
        courseCode: _shuffleCourse!.courseCode,
        unavailableSectionIds: _closedSectionIds,
        preferences: _repairPreferences,
      );

  Widget _buildShuffleResultCard(
    TimetableRepairPlan result,
    ColorScheme scheme,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isDirect
                      ? Icons.check_circle_outline
                      : Icons.auto_fix_high_outlined,
                  size: 18,
                  color:
                      result.isDirect
                          ? AppDesign.success(context)
                          : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.isDirect
                        ? 'Direct fit — no other courses move'
                        : result.impactLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final change in result.changes.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• ${change.summary}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            if (result.changes.length > 4)
              Text(
                '+ ${result.changes.length - 4} more',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => _showRepairPreview(result),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Preview changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper class for clash checking results
class ClashCheckResult {
  final bool hasClashes;
  final List<ClashWarning> clashWarnings;

  ClashCheckResult({
    required this.hasClashes,
    required this.clashWarnings,
  });
}