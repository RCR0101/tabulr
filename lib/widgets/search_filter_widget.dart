import 'package:flutter/material.dart';
import '../utils/debouncer.dart';
import 'common/app_search_field.dart';
import '../models/course.dart';
import '../services/ui/responsive_service.dart';
import '../utils/design_constants.dart';

class SearchFilterWidget extends StatefulWidget {
  final Function(String query, Map<String, dynamic> filters) onSearchChanged;

  const SearchFilterWidget({
    super.key,
    required this.onSearchChanged,
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
    };

    widget.onSearchChanged(_searchController.text, filters);
  }

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
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
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
                  // Action buttons row for mobile
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAdvancedFilters = !_showAdvancedFilters;
                            });
                          },
                          icon: Icon(
                            _showAdvancedFilters ? Icons.expand_less : Icons.expand_more,
                            size: ResponsiveService.getAdaptiveIconSize(context, 20),
                          ),
                          label: Text(
                            _showAdvancedFilters ? 'Hide Filters' : 'Show Filters',
                            style: TextStyle(fontSize: ResponsiveService.getAdaptiveFontSize(context, 14)),
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
                      FilledButton.icon(
                        onPressed: _clearFilters,
                        icon: Icon(
                          Icons.clear,
                          size: ResponsiveService.getAdaptiveIconSize(context, 20),
                        ),
                        label: Text(
                          'Clear',
                          style: TextStyle(fontSize: ResponsiveService.getAdaptiveFontSize(context, 14)),
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
                  'Listed for the year but not running this semester',
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
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
                          if (!mounted) return;
                          setState(() {
                            _selectedMidSemDate = date;
                          });
                          _updateSearch();
                        },
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
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
                          if (!mounted) return;
                          setState(() {
                            _selectedEndSemDate = date;
                          });
                          _updateSearch();
                        },
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
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
                          if (!mounted) return;
                          setState(() {
                            _selectedMidSemDate = date;
                          });
                          _updateSearch();
                        },
                        child: Text(_selectedMidSemDate == null
                            ? 'MidSem Date'
                            : 'MidSem: ${_selectedMidSemDate!.day}/${_selectedMidSemDate!.month}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
                          if (!mounted) return;
                          setState(() {
                            _selectedEndSemDate = date;
                          });
                          _updateSearch();
                        },
                        child: Text(_selectedEndSemDate == null
                            ? 'EndSem Date'
                            : 'EndSem: ${_selectedEndSemDate!.day}/${_selectedEndSemDate!.month}'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

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