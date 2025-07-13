import 'package:flutter/material.dart';
import '../models/course.dart';

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
            Row(
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
                  icon: Icon(_showAdvancedFilters ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _showAdvancedFilters = !_showAdvancedFilters;
                    });
                  },
                  tooltip: 'Advanced Filters',
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clearFilters,
                  tooltip: 'Clear Filters',
                ),
              ],
            ),
            if (_showAdvancedFilters) ...[
              const SizedBox(height: 16),
              const Text(
                'Advanced Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              
              // Course Code and Instructor filters
              Row(
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2025, 1, 1),
                          lastDate: DateTime(2025, 12, 31),
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
                          firstDate: DateTime(2025, 1, 1),
                          lastDate: DateTime(2025, 12, 31),
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
              const SizedBox(height: 12),
              
              // Days filter
              const Text('Filter by Days:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: DayOfWeek.values.map((day) {
                  return FilterChip(
                    label: Text(day.name),
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