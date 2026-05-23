import 'package:flutter/material.dart';
import '../services/course_guide_service.dart';
import '../services/courses_master_service.dart';
import '../services/branch_structure_service.dart';
import '../services/responsive_service.dart';
import '../utils/branch_constants.dart' as constants;

class CourseGuideWidget extends StatefulWidget {
  const CourseGuideWidget({super.key});

  @override
  State<CourseGuideWidget> createState() => _CourseGuideWidgetState();
}

class _CourseGuideWidgetState extends State<CourseGuideWidget> {
  final CourseGuideService _courseGuideService = CourseGuideService();
  final BranchStructureService _branchService = BranchStructureService();

  List<String> _availableBranches = [];
  String? _selectedPrimaryBranch;
  String? _selectedSecondaryBranch;
  String? _selectedSemester;

  Map<String, List<CourseGuideEntry>> _cdcData = {};
  bool _isLoading = true;
  bool _isSearching = false;
  String? _error;
  String? _validationError;

  final List<String> _semesterOptions = [
    '1-1', '1-2', '2-1', '2-2', '3-1', '3-2', '4-1', '4-2',
  ];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await _branchService.getAvailableBranches();
      setState(() {
        _availableBranches = branches;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load branches: $e';
        _isLoading = false;
      });
    }
  }

  bool get _hasDualBranch =>
      _selectedPrimaryBranch != null && _selectedSecondaryBranch != null;

  bool get _isValidDualBranch {
    if (!_hasDualBranch) return true;
    return constants.isMscBranch(_selectedPrimaryBranch!) &&
        constants.isBeBranch(_selectedSecondaryBranch!);
  }

  Future<void> _loadCDCs() async {
    if (_selectedPrimaryBranch == null) {
      setState(() => _validationError = 'Please select a branch');
      return;
    }

    if (_hasDualBranch && !_isValidDualBranch) {
      setState(() => _validationError =
          'For dual degree, primary must be MSc (B*) and secondary must be BE (A*)');
      return;
    }

    setState(() {
      _isSearching = true;
      _validationError = null;
      _error = null;
      _cdcData = {};
    });

    try {
      Map<String, List<CourseGuideEntry>> data;

      if (_hasDualBranch) {
        data = await _courseGuideService.getMergedCDCs(
          _selectedPrimaryBranch!,
          _selectedSecondaryBranch!,
          semester: _selectedSemester,
        );
      } else {
        data = await _courseGuideService.getCDCsForBranch(
          _selectedPrimaryBranch!,
          semester: _selectedSemester,
        );
      }

      setState(() {
        _cdcData = data;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load CDCs: $e';
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading Course Guide...'),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null && _cdcData.isEmpty && _availableBranches.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadBranches, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildBranchSelector(),
          if (_error != null && _cdcData.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Course Guide',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchSelector() {
    final isMobile = ResponsiveService.isMobile(context);
    final labelFontSize = ResponsiveService.getAdaptiveFontSize(context, 14);
    final iconSize = ResponsiveService.getAdaptiveIconSize(context, 16);
    final touchTarget = ResponsiveService.getTouchTargetSize(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Semester (optional)
          Text('Semester (optional)',
              style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedSemester,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('All Semesters')),
              ..._semesterOptions.map((s) => DropdownMenuItem(value: s, child: Text('Semester $s'))),
            ],
            onChanged: (v) => setState(() => _selectedSemester = v),
            isExpanded: true,
          ),
          const SizedBox(height: 16),

          // Primary branch
          Text('Branch *',
              style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedPrimaryBranch,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            items: _availableBranches.map((code) {
              final name = constants.branchCodeToName[code] ?? code;
              return DropdownMenuItem(value: code, child: Text('$code - $name'));
            }).toList(),
            onChanged: (v) {
              setState(() {
                _selectedPrimaryBranch = v;
                _validationError = null;
                if (_selectedSecondaryBranch == v) _selectedSecondaryBranch = null;
              });
            },
            isExpanded: true,
            hint: const Text('Select branch'),
          ),
          const SizedBox(height: 16),

          // Secondary branch (optional)
          Row(
            children: [
              Text('Secondary Branch (optional)',
                  style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (_selectedSecondaryBranch != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selectedSecondaryBranch = null;
                    _validationError = null;
                  }),
                  icon: Icon(Icons.clear, size: iconSize),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size(0, touchTarget),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedSecondaryBranch,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            items: _availableBranches
                .where((c) => c != _selectedPrimaryBranch)
                .map((code) {
              final name = constants.branchCodeToName[code] ?? code;
              return DropdownMenuItem(value: code, child: Text('$code - $name'));
            }).toList(),
            onChanged: (v) {
              setState(() {
                _selectedSecondaryBranch = v;
                _validationError = null;
              });
            },
            isExpanded: true,
            hint: const Text('Select secondary branch'),
          ),

          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _validationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          ],

          const SizedBox(height: 16),

          // Search button
          SizedBox(
            width: isMobile ? double.infinity : null,
            child: FilledButton.icon(
              onPressed: (_selectedPrimaryBranch == null || _isSearching) ? null : _loadCDCs,
              style: FilledButton.styleFrom(
                minimumSize: Size(isMobile ? double.infinity : 160, touchTarget),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: _isSearching
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_isSearching ? 'Loading...' : 'View CDCs'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_cdcData.isEmpty) {
      return Center(
        child: Text(
          _selectedPrimaryBranch == null
              ? 'Select a branch to view CDCs'
              : 'Press "View CDCs" to load data',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final sortedSemesters = _cdcData.keys.toList()..sort();

    if (sortedSemesters.isEmpty) {
      return const Center(child: Text('No CDCs found for the selected criteria'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSemesters.length,
      itemBuilder: (context, index) {
        final semester = sortedSemesters[index];
        final courses = _cdcData[semester]!;
        return _buildSemesterCard(semester, courses);
      },
    );
  }

  Widget _buildSemesterCard(String semester, List<CourseGuideEntry> courses) {
    final scheme = Theme.of(context).colorScheme;
    final parts = semester.split('-');
    final label = parts.length == 2 ? 'Year ${parts[0]} · Semester ${parts[1]}' : semester;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: ExpansionTile(
        initiallyExpanded: _selectedSemester != null,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            semester,
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(
          '${courses.length} course${courses.length != 1 ? 's' : ''}',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildCoursesTable(courses),
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesTable(List<CourseGuideEntry> courses) {
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
      },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              children: [
                _buildTableHeader('Code'),
                _buildTableHeader('Course Name'),
                _buildTableHeader('Cr'),
                _buildTableHeader('Type'),
              ],
            ),
            ...courses.map((course) {
              final resolvedName = course.name.isNotEmpty
                  ? course.name
                  : CoursesMasterService().getTitle(course.code);
              return TableRow(
                children: [
                  _buildTableCell(course.code, isCode: true),
                  _buildTableCell(resolvedName),
                  _buildTableCell(course.credits % 1 == 0 ? course.credits.toInt().toString() : course.credits.toString(), isCenter: true),
                  _buildTableCell(course.type, isType: true),
                ],
              );
            }),
          ],
        );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isCode = false, bool isCenter = false, bool isType = false}) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: isCode ? 'monospace' : null,
              fontWeight: isCode ? FontWeight.w500 : null,
              color: isType ? Theme.of(context).colorScheme.tertiary : null,
            ),
        textAlign: isCenter ? TextAlign.center : TextAlign.start,
      ),
    );
  }
}
