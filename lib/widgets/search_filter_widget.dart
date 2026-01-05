import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/responsive_service.dart';

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
  List<DayOfWeek> _selectedDays = [];
  bool _showAdvancedFilters = false;

  void _updateSearch() {
    final filters = <String, dynamic>{
      'instructor': _instructorController.text,
      'courseCode': _courseCodeController.text,
      'midSemDate': _selectedMidSemDate,
      'endSemDate': _selectedEndSemDate,
      'minCredits': _minCredits,
      'maxCredits': _maxCredits,
      'days': _selectedDays,
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
    });
    _updateSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            ResponsiveService.buildResponsive(
              context,
              mobile: Column(
                children: [
                  // Search field for mobile - full width
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search courses, instructors...',
                      hintText: 'e.g., CS F211, Data Structures',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                              _updateSearch();
                            },
                          )
                        : null,
                    ),
                    onChanged: (_) => _updateSearch(),
                  ),
                  SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
                  // Action buttons row for mobile
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
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
                      ElevatedButton.icon(
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
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search courses, instructors...',
                      hintText: 'e.g., CS F211, Data Structures',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                              _updateSearch();
                            },
                          )
                        : null,
                    ),
                    onChanged: (_) => _updateSearch(),
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
            if (_showAdvancedFilters) ...[
              const SizedBox(height: 16),
              const Text(
                'Advanced Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              
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
                      onChanged: (_) => _updateSearch(),
                    ),
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
                    TextField(
                      controller: _instructorController,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Instructor',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updateSearch(),
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
                        onChanged: (_) => _updateSearch(),
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
                        onChanged: (_) => _updateSearch(),
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
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
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
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
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
                      child: ElevatedButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
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
                      child: ElevatedButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
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
            ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _instructorController.dispose();
    super.dispose();
  }
}