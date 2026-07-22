import 'package:flutter/material.dart';
import '../widgets/common/app_search_field.dart';
import '../models/academic_record.dart';
import '../models/prerequisite.dart';
import '../models/prerequisite_status.dart';
import '../repositories/prerequisites_repository.dart';
import '../services/data/academic_record_service.dart';
import '../services/data/courses_master_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/course_record_badge.dart';
import '../widgets/common/shimmer_loading.dart';

class PrerequisitesScreen extends StatefulWidget {
  const PrerequisitesScreen({super.key});

  @override
  State<PrerequisitesScreen> createState() => _PrerequisitesScreenState();
}

class _PrerequisitesScreenState extends State<PrerequisitesScreen> {
  final PrerequisitesRepository _repository = PrerequisitesRepository();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<CoursePrerequisites> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _isLoadingInitial = true;
  CoursePrerequisites? _selectedCourse;

  /// Loaded alongside the catalogue rather than gating it — with no CGPA record
  /// the screen simply behaves as it always did.
  AcademicRecord _record = AcademicRecord.empty;

  @override
  void initState() {
    super.initState();
    _loadInitialCourses();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final record = await AcademicRecordService().load();
    if (mounted) setState(() => _record = record);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialCourses() async {
    setState(() {
      _isLoadingInitial = true;
    });

    try {
      final courses = await _repository.getAllCourses(limit: 200);
      setState(() {
        _searchResults = courses;
        _isLoadingInitial = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingInitial = false;
      });
      if (mounted) {
        ToastService.showError('Error loading courses: $e');
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      // Reload initial list when search is cleared
      _loadInitialCourses();
      setState(() {
        _hasSearched = false;
        _selectedCourse = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final results = await _repository.searchCourses(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ToastService.showError('Error searching: $e');
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _loadInitialCourses();
    setState(() {
      _hasSearched = false;
      _selectedCourse = null;
    });
    _searchFocusNode.unfocus();
  }

  void _selectCourse(CoursePrerequisites course) {
    setState(() {
      _selectedCourse = course;
    });
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Course Prerequisites'),
      body: Column(
        children: [
          _buildSearchBar(theme, colorScheme),
          Expanded(
            child: _buildContent(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search for a Course',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          AppSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hint: 'Search by course code, name, or department (e.g., CS F111, CS, Biology)',
            onChanged: (value) {
              setState(() {}); // To update results
              if (value.isNotEmpty) {
                _performSearch(value);
              } else {
                _clearSearch();
              }
            },
            onSubmitted: _performSearch,
            onClear: _clearSearch,
          ),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Searching...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    if (_selectedCourse != null) {
      return _buildCourseDetails(theme, colorScheme, _selectedCourse!);
    }

    if (_isLoadingInitial) {
      return const PrerequisitesSkeleton();
    }

    if (_isSearching) {
      return const PrerequisitesSkeleton(count: 3);
    }

    if (_searchResults.isEmpty && _hasSearched) {
      return _buildNoResults(theme, colorScheme);
    }

    return _buildSearchResults(theme, colorScheme);
  }

  Widget _buildNoResults(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No courses found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with:\n• Course code (e.g., CS F111)\n• Department (e.g., CS, BIO)\n• Course name (e.g., Programming)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme, ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: _loadInitialCourses,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final course = _searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selectCourse(course),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: course.hasPrerequisites
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      course.hasPrerequisites
                          ? Icons.link
                          : Icons.check_circle_outline,
                      color: course.hasPrerequisites
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.courseCode,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CoursesMasterService().getTitle(course.courseCode),
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              course.hasPrerequisites
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 14,
                              color: course.hasPrerequisites
                                  ? AppDesign.success(context)
                                  : AppDesign.muted(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              course.hasPrerequisites
                                  ? '${course.prereqs.length} prerequisite(s)'
                                  : 'No prerequisites',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
    );
  }

  Widget _buildCourseDetails(
    ThemeData theme,
    ColorScheme colorScheme,
    CoursePrerequisites course,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedCourse = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to search results'),
          ),
          const SizedBox(height: 16),

          // Course header
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      course.courseCode,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    CoursesMasterService().getTitle(course.courseCode),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Prerequisites section
          Text(
            'Prerequisites',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _buildEligibilityBanner(theme, colorScheme, course),

          // All/One requirement indicator
          if (course.hasPrerequisites && course.allOne != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.secondary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    course.allOne?.toLowerCase() == 'all'
                        ? Icons.check_circle_outline
                        : Icons.alt_route,
                    color: colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      course.allOne?.toLowerCase() == 'all'
                          ? 'All of the following courses must be completed'
                          : 'At least one of the following courses must be completed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (course.hasPrerequisites)
            ...course.prereqs.map((prereq) => _buildPrerequisiteCard(
                  theme,
                  colorScheme,
                  prereq,
                ))
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: AppDesign.success(context),
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No Prerequisites',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This course has no prerequisite requirements',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One-line verdict against the student's own record. Absent entirely when
  /// there's nothing to say — no record, or no prerequisites to check — so the
  /// screen doesn't grow a permanent empty strip.
  Widget _buildEligibilityBanner(
    ThemeData theme,
    ColorScheme colorScheme,
    CoursePrerequisites course,
  ) {
    final status = PrerequisiteStatus.of(course, _record);
    final met = status.isMet;
    if (met == null) return const SizedBox.shrink();

    final missing = status.outstanding.map((p) => p.courseCode).join(', ');
    final color = met ? AppDesign.success(context) : colorScheme.error;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(met ? Icons.task_alt : Icons.pending_outlined,
                  size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  met
                      ? "You've met the prerequisites for this course."
                      : 'You still need $missing.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (status.concurrent.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Can be taken alongside: '
              '${status.concurrent.map((p) => p.courseCode).join(', ')}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (status.unclear.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Check for yourself: the requirement type is unrecorded for '
              '${status.unclear.map((p) => p.courseCode).join(', ')}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Based on the grades in your CGPA calculator.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrerequisiteCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Prerequisite prereq,
  ) {
    final prereqCode = prereq.courseCode;
    final prereqTitle = CoursesMasterService().getTitle(prereq.courseCode);

    final typeLower = prereq.type.toLowerCase();
    final isPrerequisite = typeLower == 'pre';
    final isCorequisite = typeLower == 'co/pre';
    final isUnclear = typeLower == 'nan';

    // Select color and icon based on type
    Color containerColor;
    Color textColor;
    IconData iconData;
    String typeLabel;
    String description;

    if (isPrerequisite) {
      containerColor = colorScheme.primaryContainer;
      textColor = colorScheme.onPrimaryContainer;
      iconData = Icons.arrow_back;
      typeLabel = 'PREREQUISITE';
      description = 'Must be completed before taking this course';
    } else if (isCorequisite) {
      containerColor = colorScheme.tertiaryContainer;
      textColor = colorScheme.onTertiaryContainer;
      iconData = Icons.people;
      typeLabel = 'CO/PREREQUISITE';
      description = 'Can be taken alongside or before this course';
    } else if (isUnclear) {
      containerColor = colorScheme.errorContainer;
      textColor = colorScheme.onErrorContainer;
      iconData = Icons.help_outline;
      typeLabel = 'DETAILS UNCLEAR';
      description = 'Check ERP for more details';
    } else {
      // Default fallback
      containerColor = colorScheme.surfaceContainerHighest;
      textColor = colorScheme.onSurface;
      iconData = Icons.info_outline;
      typeLabel = prereq.type.toUpperCase();
      description = 'See course requirements';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: containerColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                iconData,
                color: textColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: containerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      CourseRecordBadge(record: _record, courseCode: prereqCode),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prereqCode,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  if (prereqTitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      prereqTitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isUnclear
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontStyle: isUnclear ? FontStyle.normal : FontStyle.italic,
                      fontWeight: isUnclear ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
