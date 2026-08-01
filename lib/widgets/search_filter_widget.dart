import 'package:flutter/material.dart';
import '../utils/debouncer.dart';
import 'common/app_search_field.dart';
import '../models/course.dart';
import '../models/elective_pool.dart';
import '../services/data/config_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/design_constants.dart';

class SearchFilterWidget extends StatefulWidget {
  final Function(String query, Map<String, dynamic> filters) onSearchChanged;

  /// Whether the elective-type chips have anything to filter against. The pools
  /// are derived from the student's branch, so a consumer that cannot resolve
  /// one leaves them out rather than showing chips that select nothing.
  final bool hasBranch;

  const SearchFilterWidget({
    super.key,
    required this.onSearchChanged,
    this.hasBranch = false,
  });

  @override
  State<SearchFilterWidget> createState() => _SearchFilterWidgetState();
}

class _SearchFilterWidgetState extends State<SearchFilterWidget> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _instructorController = TextEditingController();
  final TextEditingController _courseCodeController = TextEditingController();
  DateTime? _selectedMidSemDate;
  DateTime? _selectedEndSemDate;
  int? _minCredits;
  int? _maxCredits;
  final List<DayOfWeek> _selectedDays = [];
  final List<int> _selectedHours = [];

  /// Elective pools to narrow to. Empty means no pool filter; several means
  /// their union, like the day and hour chips above.
  final Set<ElectivePool> _selectedPools = {};
  bool _showAdvancedFilters = false;

  /// Whether to include courses the timetable lists with no sections at all.
  ///
  /// Off by default: a course with no sections cannot be added to anything, so
  /// it is noise in a list whose purpose is picking sections. They exist
  /// because the booklet prints a course in both semester tables and the copy
  /// for the term it is not offered in carries no rows — see dedupe_by_doc_id
  /// in functions-python/main.py. Kept behind a switch rather than dropped
  /// outright, because "is this course running at all?" is a real question.
  bool _includeSectionless = false;
  final _debounce = Debouncer(duration: const Duration(milliseconds: 250));

  void _updateSearchDebounced() {
    _debounce.run(_updateSearch);
  }

  void _updateSearch() {
    final filters = <String, dynamic>{
      'instructor': _instructorController.text,
      'courseCode': _courseCodeController.text,
      'midSemDate': _selectedMidSemDate,
      'endSemDate': _selectedEndSemDate,
      'minCredits': _minCredits,
      'maxCredits': _maxCredits,
      'days': _selectedDays,
      'hours': _selectedHours,
      'includeSectionless': _includeSectionless,
      'electivePools': _selectedPools,
    };

    widget.onSearchChanged(_searchController.text, filters);
  }

  /// Picks a mid-sem or compre date, restricted to that exam window.
  ///
  /// No exam is scheduled outside its window, so opening on the whole calendar
  /// year meant paging past ten empty months to reach the one week that can
  /// match. Cancelling still clears the filter, which is how it has always
  /// worked. [ConfigService] dates are admin-set, so this follows a rescheduled
  /// exam week without a release.
  Future<void> _pickExamDate({required bool midSem}) async {
    final config = ConfigService();
    final first = midSem ? config.midsemStart : config.endsemStart;
    final last = midSem ? config.midsemEnd : config.endsemEnd;
    final current = midSem ? _selectedMidSemDate : _selectedEndSemDate;
    final date = await showDatePicker(
      context: context,
      // A previously picked date can fall outside the window if the admin has
      // moved it since; showDatePicker asserts on that, so fall back.
      initialDate: (current != null &&
              !current.isBefore(first) &&
              !current.isAfter(last))
          ? current
          : first,
      firstDate: first,
      lastDate: last,
    );
    if (!mounted) return;
    setState(() {
      if (midSem) {
        _selectedMidSemDate = date;
      } else {
        _selectedEndSemDate = date;
      }
    });
    _updateSearch();
  }

  /// Whether anything is set that Clear would actually undo.
  bool get _hasActiveFilters =>
      _searchController.text.isNotEmpty ||
      _instructorController.text.isNotEmpty ||
      _courseCodeController.text.isNotEmpty ||
      _selectedMidSemDate != null ||
      _selectedEndSemDate != null ||
      _minCredits != null ||
      _maxCredits != null ||
      _selectedDays.isNotEmpty ||
      _selectedHours.isNotEmpty ||
      _selectedPools.isNotEmpty ||
      _includeSectionless;

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _instructorController.clear();
      _courseCodeController.clear();
      _selectedMidSemDate = null;
      _selectedEndSemDate = null;
      _minCredits = null;
      _maxCredits = null;
      _selectedDays.clear();
      _selectedHours.clear();
      _selectedPools.clear();
      _includeSectionless = false;
    });
    _updateSearch();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: isMobile && _showAdvancedFilters ? MediaQuery.sizeOf(context).height * 0.4 : double.infinity,
      ),
      child: SingleChildScrollView(
      child: Container(
      // Flat on a phone. The caller already pads this into a column, so the
      // floating card put a shadowed edge across the screen a few pixels under
      // the buttons — a box inside a box, reading as a rendering artefact
      // rather than as structure.
      margin: isMobile ? EdgeInsets.zero : const EdgeInsets.all(8),
      padding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isMobile ? Colors.transparent : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isMobile
            ? null
            : [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      // ListTiles paint ink/background on the nearest Material; provide a
      // transparent one above the decorated box so they stay visible.
      child: Material(
        color: Colors.transparent,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            ResponsiveService.buildResponsive(
              context,
              mobile: Column(
                children: [
                  // Search field for mobile - full width
                  Semantics(
                    label: 'Search Courses',
                    textField: true,
                    child: AppSearchField(
                      controller: _searchController,
                      hint: 'Search courses, instructors...',
                      onChanged: (_) => _updateSearchDebounced(),
                      onClear: () {
                        _searchController.clear();
                        _updateSearch();
                      },
                    ),
                  ),
                  SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
                  // Both were filled buttons, which made narrowing a search the
                  // loudest thing on the screen — louder than the action the
                  // screen exists for. Text buttons: available, not shouted.
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showAdvancedFilters = !_showAdvancedFilters;
                          });
                        },
                        icon: Icon(
                          _showAdvancedFilters ? Icons.expand_less : Icons.tune,
                          size: 18,
                        ),
                        label: Text(
                          _showAdvancedFilters ? 'Hide filters' : 'Filters',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const Spacer(),
                      // Only meaningful once something is set, and a permanent
                      // Clear beside an untouched form is just noise.
                      if (_hasActiveFilters)
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear',
                              style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              desktop: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Search Courses',
                    textField: true,
                    child: AppSearchField(
                      controller: _searchController,
                      hint: 'Search courses, instructors...',
                      onChanged: (_) => _updateSearchDebounced(),
                      onClear: () {
                        _searchController.clear();
                        _updateSearch();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _showAdvancedFilters ? Icons.expand_less : Icons.expand_more,
                    size: ResponsiveService.getAdaptiveIconSize(context, 24),
                  ),
                  onPressed: () {
                    setState(() {
                      _showAdvancedFilters = !_showAdvancedFilters;
                    });
                  },
                  tooltip: 'Advanced Filters',
                  iconSize: ResponsiveService.getTouchTargetSize(context),
                  padding: EdgeInsets.all(ResponsiveService.getValue(context, mobile: 12.0, tablet: 8.0, desktop: 8.0)),
                ),
                IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: ResponsiveService.getAdaptiveIconSize(context, 24),
                  ),
                  onPressed: _clearFilters,
                  tooltip: 'Clear Filters',
                  iconSize: ResponsiveService.getTouchTargetSize(context),
                  padding: EdgeInsets.all(ResponsiveService.getValue(context, mobile: 12.0, tablet: 8.0, desktop: 8.0)),
                ),
              ],
            ),
            ),
            AnimatedCrossFade(
              duration: AppDesign.animDurationNormal,
              crossFadeState: _showAdvancedFilters
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              sizeCurve: AppDesign.animCurve,
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const SizedBox(height: 16),
              const Text(
                'Advanced Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              CheckboxListTile(
                value: _includeSectionless,
                onChanged: (v) {
                  setState(() => _includeSectionless = v ?? false);
                  _updateSearch();
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Show courses with no sections',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Listed for the year but no sections found',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),

              // Course Code and Instructor filters
              ResponsiveService.buildResponsive(
                context,
                mobile: Column(
                  children: [
                    TextField(
                      controller: _courseCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Course Code',
                        hintText: 'e.g., CS F211, MATH F211',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updateSearchDebounced(),
                    ),
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
                    TextField(
                      controller: _instructorController,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Instructor',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updateSearchDebounced(),
                    ),
                  ],
                ),
                desktop: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _courseCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Filter by Course Code',
                          hintText: 'e.g., CS F211, MATH F211',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _updateSearchDebounced(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _instructorController,
                        decoration: const InputDecoration(
                          labelText: 'Filter by Instructor',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _updateSearchDebounced(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Credits filter
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Min Credits',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _minCredits = int.tryParse(value);
                        });
                        _updateSearch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Max Credits',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _maxCredits = int.tryParse(value);
                        });
                        _updateSearch();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Exam date filters
              ResponsiveService.buildResponsive(
                context,
                mobile: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _pickExamDate(midSem: true),
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_selectedMidSemDate == null
                            ? 'Select MidSem Date'
                            : 'MidSem: ${_selectedMidSemDate!.day}/${_selectedMidSemDate!.month}'),
                      ),
                    ),
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _pickExamDate(midSem: false),
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_selectedEndSemDate == null
                            ? 'Select EndSem Date'
                            : 'EndSem: ${_selectedEndSemDate!.day}/${_selectedEndSemDate!.month}'),
                      ),
                    ),
                  ],
                ),
                desktop: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _pickExamDate(midSem: true),
                        child: Text(_selectedMidSemDate == null
                            ? 'MidSem Date'
                            : 'MidSem: ${_selectedMidSemDate!.day}/${_selectedMidSemDate!.month}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _pickExamDate(midSem: false),
                        child: Text(_selectedEndSemDate == null
                            ? 'EndSem Date'
                            : 'EndSem: ${_selectedEndSemDate!.day}/${_selectedEndSemDate!.month}'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Elective pool filter. Hidden when the profile names no branch:
              // the pools are branch-relative, so with nothing to subtract there
              // is no honest answer and an empty chip row beats a wrong one.
              if (widget.hasBranch) ...[
                Text(
                  'Filter by Elective Type:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                  ),
                ),
                SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
                Wrap(
                  spacing: ResponsiveService.getAdaptiveSpacing(context, 8),
                  runSpacing: ResponsiveService.getAdaptiveSpacing(context, 4),
                  children: ElectivePool.values.map((pool) {
                    return FilterChip(
                      avatar: Icon(
                        pool.icon,
                        size: ResponsiveService.getAdaptiveFontSize(context, 15),
                      ),
                      // Short form, spelt out: "DEL" alone is jargon to a
                      // first-year, and the row has space for four more words.
                      label: Text(
                        '${pool.short} · ${pool.label}',
                        style: TextStyle(
                          fontSize:
                              ResponsiveService.getAdaptiveFontSize(context, 12),
                        ),
                      ),
                      selected: _selectedPools.contains(pool),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedPools.add(pool);
                          } else {
                            _selectedPools.remove(pool);
                          }
                        });
                        _updateSearch();
                      },
                      padding: ResponsiveService.getAdaptivePadding(
                        context,
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(
                    height: ResponsiveService.getAdaptiveSpacing(context, 12)),
              ],

              // Days filter
              Text(
                'Filter by Days:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
              Wrap(
                spacing: ResponsiveService.getAdaptiveSpacing(context, 8),
                runSpacing: ResponsiveService.getAdaptiveSpacing(context, 4),
                children: DayOfWeek.values.map((day) {
                  return FilterChip(
                    label: Text(
                      day.name,
                      style: TextStyle(
                        fontSize: ResponsiveService.getAdaptiveFontSize(context, 12),
                      ),
                    ),
                    selected: _selectedDays.contains(day),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDays.add(day);
                        } else {
                          _selectedDays.remove(day);
                        }
                      });
                      _updateSearch();
                    },
                    padding: ResponsiveService.getAdaptivePadding(
                      context,
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),

              // Hours filter
              Text(
                'Filter by Hours:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
              Wrap(
                spacing: ResponsiveService.getAdaptiveSpacing(context, 8),
                runSpacing: ResponsiveService.getAdaptiveSpacing(context, 4),
                children: TimeSlotInfo.hourSlotNames.entries.map((entry) {
                  final hour = entry.key;
                  final timeLabel = entry.value;
                  final startTime = timeLabel.split('-')[0].trim();
                  return FilterChip(
                    label: Text(
                      '$hour — $startTime',
                      style: TextStyle(
                        fontSize: ResponsiveService.getAdaptiveFontSize(context, 11),
                      ),
                    ),
                    selected: _selectedHours.contains(hour),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedHours.add(hour);
                        } else {
                          _selectedHours.remove(hour);
                        }
                      });
                      _updateSearch();
                    },
                    padding: ResponsiveService.getAdaptivePadding(
                      context,
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  );
                }).toList(),
              ),
                ],
              ),
            ),
        ],
      ),
      ),
    ),
    ),
    );
  }

  @override
  void dispose() {
    _debounce.dispose();
    _searchController.dispose();
    _instructorController.dispose();
    _courseCodeController.dispose();
    super.dispose();
  }
}