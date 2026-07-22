import 'package:flutter/material.dart';
import '../utils/debouncer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:url_launcher/url_launcher.dart';

import '../models/academic_record.dart';
import '../models/timetable_selection_link.dart';
import '../services/data/professor_service.dart';
import '../widgets/common/shimmer_loading.dart';
import '../services/ui/responsive_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/app_tappable.dart';
import '../utils/page_info_helper.dart';
import '../services/ui/tutorial_service.dart';


class ProfessorsScreen extends StatefulWidget {
  /// Set when opened from the editor, which turns the "teaches" chips in a
  /// professor's detail dialog into one-tap adds for that exact section — the
  /// professor being the thing students actually pick a section on.
  final TimetableSelectionLink? selectionLink;

  const ProfessorsScreen({super.key, this.selectionLink});

  @override
  State<ProfessorsScreen> createState() => _ProfessorsScreenState();
}

class _ProfessorsScreenState extends State<ProfessorsScreen> {
  final ProfessorService _professorService = ProfessorService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _searchDebounce = Debouncer(duration: const Duration(milliseconds: 250));

  @override
  void initState() {
    super.initState();
    _loadProfessors();

    _searchController.addListener(() {
      _searchDebounce.run(() {
        _professorService.searchProfessors(_searchController.text);
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
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
      appBar: AppDesign.appBar(
        context,
        title: 'Prof Chambers',
        actions: [
          PageInfoHelper.infoButton(context, PageInfoHelper.profChambers, key: TutorialKeys.infoProfChambers),
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
                Text(
                  'Search Professors',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${_professorService.professors.length})',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Search Professors',
                    textField: true,
                    child: AppSearchField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hint: 'Search by professor name or chamber (e.g., "John" or "A101")',
                      onChanged: (value) => setState(() {}),
                      onSubmitted: (value) => _searchFocusNode.unfocus(),
                      onClear: _clearSearch,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
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
        Widget child;
        if (_professorService.isLoading) {
          child = _buildLoadingView();
        } else if (_professorService.error != null) {
          child = _buildErrorView();
        } else if (_professorService.professors.isEmpty) {
          child = _buildEmptyView();
        } else {
          child = _buildProfessorList();
        }

        return AnimatedSwitcher(
          duration: AppDesign.animDurationNormal,
          child: KeyedSubtree(
            key: ValueKey(_professorService.isLoading ? 'loading' : 'content'),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildLoadingView() {
    return const CourseListSkeleton();
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
          FilledButton.icon(
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
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch
                ? 'No professors found'
                : 'No professors available',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try searching with different keywords'
                : 'Professor data is not available yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Results',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${professors.length})',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadProfessors,
              child: ListView.separated(
                scrollCacheExtent: ScrollCacheExtent.pixels(800),
                padding: const EdgeInsets.all(16),
                itemCount: professors.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return _buildProfessorCard(professors[index]);
                },
              ),
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
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Text(
          professor.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              professor.chamber,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: professor.chamber == 'Unavailable'
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            if (isOccupied && currentClass != null) ...[
              const SizedBox(height: 4),
              Text(
                'In: ${currentClass.courseCode} @ ${currentClass.room}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
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
            ? Theme.of(context).colorScheme.error.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOccupied
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
    showDialog(
      context: context,
      builder: (context) => _ProfessorDetailDialog(
        professor: professor,
        selectionLink: widget.selectionLink,
      ),
    );
  }


  void _showSortDialog() {
    final currentSort = _professorService.sortType;

    AppDialog.adaptive(
      context: context,
      title: 'Sort Professors',
      icon: Icons.sort,
      content: SizedBox(
        width: ResponsiveService.getValue(context, mobile: MediaQuery.sizeOf(context).width * 0.9, tablet: 400, desktop: 480),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: ResponsiveService.getValue(context, mobile: 8, tablet: 8, desktop: 8),
                runSpacing: ResponsiveService.getValue(context, mobile: 8, tablet: 8, desktop: 8),
                alignment: WrapAlignment.spaceEvenly,
                children: ProfessorSortType.values.map((sortType) {
                  final isSelected = currentSort == sortType;
                  return SizedBox(
                    width: ResponsiveService.getValue(context, mobile: (MediaQuery.sizeOf(context).width * 0.9 - 24) / 2, tablet: 180, desktop: 220),
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
                                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
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
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.pop(context),
        ),
      ],
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

class _ProfessorDetailDialog extends StatelessWidget {
  final Professor professor;
  final TimetableSelectionLink? selectionLink;

  const _ProfessorDetailDialog({
    required this.professor,
    this.selectionLink,
  });

  @override
  Widget build(BuildContext context) {
    final hasContact = professor.email != null || professor.contact != null;

    return DefaultTabController(
      length: hasContact ? 2 : 1,
      child: AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveService.isMobile(context) ? 16 : (MediaQuery.sizeOf(context).width - 480) / 2,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                    Icons.person,
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
            if (hasContact)
              TabBar(
                tabs: const [
                  Tab(text: 'Schedule'),
                  Tab(text: 'Contact'),
                ],
                labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            if (!hasContact)
              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ),
        content: SizedBox(
          width: ResponsiveService.isMobile(context) ? MediaQuery.sizeOf(context).width * 0.85 : 440,
          height: 300,
          child: hasContact
              ? TabBarView(
                  children: [
                    _buildScheduleTab(context),
                    _buildContactTab(context),
                  ],
                )
              : _buildScheduleTab(context),
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

  Widget _buildScheduleTab(BuildContext context) {
    final scheduleByDay = professor.getScheduleByDay();
    final dayOrder = ['M', 'T', 'W', 'Th', 'F', 'S'];

    if (scheduleByDay.isEmpty) {
      return Center(
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
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTaughtSections(context),
          ...dayOrder
              .where((day) => scheduleByDay.containsKey(day))
              .map((day) => _buildDaySchedule(context, day, scheduleByDay[day]!)),
        ],
      ),
    );
  }

  Widget _buildContactTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          if (professor.email != null)
            _buildContactTile(
              context,
              icon: Icons.email_outlined,
              label: 'Email',
              value: professor.email!,
              onTap: () => launchUrl(Uri.parse('mailto:${professor.email}')),
            ),
          if (professor.email != null && professor.contact != null)
            const SizedBox(height: 12),
          if (professor.contact != null)
            _buildContactTile(
              context,
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: professor.contact!,
              onTap: () => launchUrl(Uri.parse('tel:${professor.contact}')),
            ),
        ],
      ),
    );
  }

  Widget _buildContactTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  /// The professor's distinct course sections, pulled out of the day grid where
  /// each one repeats across every day it meets.
  ///
  /// Worth its own row even unlinked — "what does this professor teach" is
  /// otherwise something you have to reconstruct by reading the whole grid.
  /// When linked, each chip adds that exact section to the open timetable.
  Widget _buildTaughtSections(BuildContext context) {
    final seen = <String>{};
    final sections = <ProfessorScheduleEntry>[];
    for (final entry in professor.schedule) {
      if (seen.add('${entry.courseCode}|${entry.sectionId}')) {
        sections.add(entry);
      }
    }
    if (sections.isEmpty) return const SizedBox.shrink();

    final link = selectionLink;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            link == null ? 'TEACHES' : 'TEACHES — TAP TO ADD',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.primary,
                ),
          ),
          const SizedBox(height: 6),
          // This dialog is stateless, so without listening to the link a tapped
          // chip would keep saying "add" until the dialog is reopened.
          if (link == null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in sections)
                  _buildTaughtChip(context, entry, null),
              ],
            )
          else
            ListenableBuilder(
              listenable: link.revision,
              builder: (context, _) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in sections)
                    _buildTaughtChip(context, entry, link),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaughtChip(
    BuildContext context,
    ProfessorScheduleEntry entry,
    TimetableSelectionLink? link,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final label = '${entry.courseCode} ${entry.sectionId}';

    // Only offer the add when the open timetable actually carries this course;
    // a chip that fails on tap is worse than a plain one.
    final addable = link != null &&
        link.availableCourses.any((c) =>
            AcademicRecord.normalizeCode(c.courseCode) ==
            AcademicRecord.normalizeCode(entry.courseCode));

    final selected = link != null &&
        link.selectedSections.any((s) =>
            s.courseCode == entry.courseCode && s.sectionId == entry.sectionId);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (addable) ...[
            Icon(
              selected ? Icons.check_circle : Icons.add_circle_outline,
              size: 13,
              color: scheme.primary,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: selected ? scheme.primary : null,
                ),
          ),
        ],
      ),
    );

    if (!addable) return chip;

    return AppTappable(
      onTap: () => link.onSectionToggle(
        entry.courseCode,
        entry.sectionId,
        selected,
      ),
      child: chip,
    );
  }

  Widget _buildDaySchedule(BuildContext context, String day, List<ProfessorScheduleEntry> entries) {
    final dayNames = {
      'M': 'Monday',
      'T': 'Tuesday',
      'W': 'Wednesday',
      'Th': 'Thursday',
      'F': 'Friday',
      'S': 'Saturday',
    };

    final dayColors = {
      'M': AppDesign.info(context),
      'T': AppDesign.success(context),
      'W': AppDesign.warning(context),
      'Th': Theme.of(context).colorScheme.tertiary,
      'F': Colors.teal,
      'S': Colors.pink,
    };

    final dayColor = dayColors[day] ?? Theme.of(context).colorScheme.primary;

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
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: groupedByTime.entries
                .map((e) => _buildTimeSlotChip(context, e.key, e.value, dayColor))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotChip(BuildContext context, String timeSlot, List<ProfessorScheduleEntry> entries, Color accentColor) {
    final time = timeSlot
        .replaceAll(' AM', '')
        .replaceAll(' PM', '')
        .replaceAll(':00', '');

    final courses = entries.map((e) {
      if (e.room.isNotEmpty) return '${e.courseCode} @ ${e.room}';
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
}