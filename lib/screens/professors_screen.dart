import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/professor_service.dart';
import '../services/responsive_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_drawer.dart';

class ProfessorsScreen extends StatefulWidget {
  const ProfessorsScreen({super.key});

  @override
  State<ProfessorsScreen> createState() => _ProfessorsScreenState();
}

class _ProfessorsScreenState extends State<ProfessorsScreen> {
  final ProfessorService _professorService = ProfessorService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadProfessors();
    
    // Listen to search changes
    _searchController.addListener(() {
      _professorService.searchProfessors(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProfessors() async {
    await _professorService.loadProfessors();
  }

  void _clearSearch() {
    _searchController.clear();
    _professorService.clearSearch();
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        currentScreen: DrawerScreen.profChambers,
        authService: _authService,
      ),
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Prof Chambers'),
            Text(
              'Credits: Pratyush Nair',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (kIsWeb)
            IconButton(
              onPressed: _professorService.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }


  Widget _buildSearchBar() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Search Professors',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_professorService.professors.length} professors found',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search by professor name or chamber (e.g., "John" or "A101")',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) => setState(() {}),
                    onSubmitted: (value) => _searchFocusNode.unfocus(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showSortDialog,
                  icon: const Icon(Icons.sort),
                  label: const Text('Sort'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListenableBuilder(
      listenable: _professorService,
      builder: (context, _) {
        if (_professorService.isLoading) {
          return _buildLoadingView();
        }

        if (_professorService.error != null) {
          return _buildErrorView();
        }

        if (_professorService.professors.isEmpty) {
          return _buildEmptyView();
        }

        return _buildProfessorList();
      },
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading professors...',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading professors',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _professorService.error ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadProfessors,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final hasSearch = _professorService.searchQuery.isNotEmpty;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.school_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch 
                ? 'No professors found'
                : 'No professors available',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch 
                ? 'Try searching with different keywords'
                : 'Professor data is not available yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Search'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfessorList() {
    final professors = _professorService.professors;
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Professors',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${professors.length} results',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: professors.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildProfessorCard(professors[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessorCard(Professor professor) {
    final isOccupied = professor.isCurrentlyOccupied();
    final currentClass = professor.getCurrentClass();
    final hasSchedule = professor.schedule.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            professor.name.isNotEmpty
                ? professor.name[0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          professor.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              professor.chamber,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: professor.chamber == 'Unavailable'
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
            ),
            if (isOccupied && currentClass != null) ...[
              const SizedBox(height: 4),
              Text(
                'In: ${currentClass.courseCode} @ ${currentClass.room}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error.withOpacity(0.8),
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ],
        ),
        trailing: hasSchedule
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusBadge(isOccupied, currentClass),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: 'View schedule',
                    onPressed: () => _showScheduleDialog(professor),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildStatusBadge(bool isOccupied, ProfessorScheduleEntry? currentClass) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOccupied
            ? Theme.of(context).colorScheme.error.withOpacity(0.1)
            : Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOccupied
              ? Theme.of(context).colorScheme.error.withOpacity(0.3)
              : Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Text(
        isOccupied ? 'Occupied' : 'Free',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isOccupied
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showScheduleDialog(Professor professor) {
    final scheduleByDay = professor.getScheduleByDay();
    final dayOrder = ['M', 'T', 'W', 'Th', 'F', 'S'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.calendar_month,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        professor.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            professor.chamber,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ),
        content: scheduleByDay.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No schedule data available',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: dayOrder
                      .where((day) => scheduleByDay.containsKey(day))
                      .map((day) => _buildDaySchedule(day, scheduleByDay[day]!))
                      .toList(),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySchedule(String day, List<ProfessorScheduleEntry> entries) {
    final dayNames = {
      'M': 'Monday',
      'T': 'Tuesday',
      'W': 'Wednesday',
      'Th': 'Thursday',
      'F': 'Friday',
      'S': 'Saturday',
    };

    final dayColors = {
      'M': Colors.blue,
      'T': Colors.green,
      'W': Colors.orange,
      'Th': Colors.purple,
      'F': Colors.teal,
      'S': Colors.pink,
    };

    final dayColor = dayColors[day] ?? Theme.of(context).colorScheme.primary;

    // Group entries by time slot
    final groupedByTime = <String, List<ProfessorScheduleEntry>>{};
    for (final entry in entries) {
      final timeKey = entry.hourRangeString;
      groupedByTime.putIfAbsent(timeKey, () => []);
      groupedByTime[timeKey]!.add(entry);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: dayColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              dayNames[day] ?? day,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: dayColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Classes for this day grouped by time
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: groupedByTime.entries
                .map((e) => _buildTimeSlotChip(e.key, e.value, dayColor))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotChip(String timeSlot, List<ProfessorScheduleEntry> entries, Color accentColor) {
    final time = _formatTimeCompact(timeSlot);

    // Combine course codes and rooms
    final courses = entries.map((e) {
      if (e.room.isNotEmpty) {
        return '${e.courseCode} @ ${e.room}';
      }
      return e.courseCode;
    }).join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 4),
          Text(
            time,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            courses,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }

  String _formatTimeCompact(String hourRange) {
    // Convert "8:00-9:50 AM" to "8-9:50"
    return hourRange
        .replaceAll(' AM', '')
        .replaceAll(' PM', '')
        .replaceAll(':00', '');
  }

  void _showSortDialog() {
    final currentSort = _professorService.sortType;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.sort,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Sort Professors'),
          ],
        ),
        content: Container(
          width: ResponsiveService.getValue(context, mobile: MediaQuery.of(context).size.width * 0.9, tablet: 400, desktop: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: ResponsiveService.getValue(context, mobile: 8, tablet: 8, desktop: 8),
                runSpacing: ResponsiveService.getValue(context, mobile: 8, tablet: 8, desktop: 8),
                alignment: WrapAlignment.spaceEvenly,
                children: ProfessorSortType.values.map((sortType) {
                  final isSelected = currentSort == sortType;
                  return Container(
                    width: ResponsiveService.getValue(context, mobile: (MediaQuery.of(context).size.width * 0.9 - 24) / 2, tablet: 180, desktop: 220),
                    child: Material(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          _professorService.setSortType(sortType);
                          Navigator.pop(context);
                        },
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: ResponsiveService.getTouchTargetSize(context),
                          ),
                          padding: ResponsiveService.getAdaptivePadding(context, EdgeInsets.all(ResponsiveService.isMobile(context) ? 8 : 12)),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.all(ResponsiveService.isMobile(context) ? 8 : 8),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _getSortIcon(sortType),
                                  size: ResponsiveService.isMobile(context) ? 18 : 18,
                                  color: isSelected 
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(height: ResponsiveService.isMobile(context) ? 6 : 8),
                              Text(
                                _getSortOrderName(sortType),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: ResponsiveService.isMobile(context) ? 10 : 12,
                                  color: isSelected 
                                      ? Theme.of(context).colorScheme.onPrimaryContainer
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(height: 4),
                                Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: ResponsiveService.isMobile(context) ? 14 : 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getSortOrderName(ProfessorSortType sortType) {
    switch (sortType) {
      case ProfessorSortType.nameAsc:
        return 'Name (A-Z)';
      case ProfessorSortType.nameDesc:
        return 'Name (Z-A)';
      case ProfessorSortType.chamberAsc:
        return 'Chamber (A-Z)';
      case ProfessorSortType.chamberDesc:
        return 'Chamber (Z-A)';
    }
  }

  IconData _getSortIcon(ProfessorSortType sortType) {
    switch (sortType) {
      case ProfessorSortType.nameAsc:
      case ProfessorSortType.nameDesc:
        return Icons.person;
      case ProfessorSortType.chamberAsc:
      case ProfessorSortType.chamberDesc:
        return Icons.room;
    }
  }

}