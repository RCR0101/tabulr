import 'package:flutter/material.dart';
import '../../models/timetable_constraints.dart';
import '../../services/ui/responsive_service.dart';

class InstructorRankingDialog extends StatefulWidget {
  final Map<String, Map<String, List<String>>> courseSectionInstructors;
  final Map<String, InstructorRankings> currentRankings;

  const InstructorRankingDialog({
    super.key,
    required this.courseSectionInstructors,
    required this.currentRankings,
  });

  @override
  State<InstructorRankingDialog> createState() => _InstructorRankingDialogState();
}

class _InstructorRankingDialogState extends State<InstructorRankingDialog>
    with TickerProviderStateMixin {
  late Map<String, InstructorRankings> _rankings;
  late TabController _tabController;
  late List<String> _courseList;

  @override
  void initState() {
    super.initState();
    _rankings = Map.from(widget.currentRankings);
    _courseList = widget.courseSectionInstructors.keys.toList()..sort();
    _tabController = TabController(length: _courseList.length, vsync: this);

    for (final courseCode in widget.courseSectionInstructors.keys) {
      if (!_rankings.containsKey(courseCode)) {
        _rankings[courseCode] = InstructorRankings();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rank Instructors by Preference'),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? double.infinity : 650,
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          children: [
            Text(
              'Drag to reorder instructors from most preferred (top) to least preferred (bottom)',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorWeight: 2,
                tabs: _courseList.map((courseCode) {
                  return Tab(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        courseCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _courseList.map((courseCode) {
                  final instructorsByType = widget.courseSectionInstructors[courseCode]!;

                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            courseCode,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (instructorsByType['L']!.isNotEmpty)
                            _buildSectionTypeRanking(courseCode, 'Lecture', 'L', instructorsByType['L']!),
                          if (instructorsByType['P']!.isNotEmpty)
                            _buildSectionTypeRanking(courseCode, 'Practical', 'P', instructorsByType['P']!),
                          if (instructorsByType['T']!.isNotEmpty)
                            _buildSectionTypeRanking(courseCode, 'Tutorial', 'T', instructorsByType['T']!),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _rankings),
          child: const Text('Save Rankings'),
        ),
      ],
    );
  }

  void _writeBackRanking(String courseCode, String typeKey, List<String> list) {
    switch (typeKey) {
      case 'L':
        _rankings[courseCode] = _rankings[courseCode]!.copyWith(lectureInstructors: list);
        break;
      case 'P':
        _rankings[courseCode] = _rankings[courseCode]!.copyWith(practicalInstructors: list);
        break;
      case 'T':
        _rankings[courseCode] = _rankings[courseCode]!.copyWith(tutorialInstructors: list);
        break;
    }
  }

  /// One-tap alternative to dragging: promote an instructor to rank #1 (most
  /// preferred) for this course + section type.
  void _pinToTop(String courseCode, String typeKey, List<String> ranked, int index) {
    setState(() {
      final instructor = ranked.removeAt(index);
      ranked.insert(0, instructor);
      _writeBackRanking(courseCode, typeKey, ranked);
    });
  }

  Widget _buildSectionTypeRanking(String courseCode, String typeName, String typeKey, List<String> availableInstructors) {
    final currentRankings = _rankings[courseCode]!;
    List<String> rankedInstructors;

    switch (typeKey) {
      case 'L':
        rankedInstructors = List.from(currentRankings.lectureInstructors);
        break;
      case 'P':
        rankedInstructors = List.from(currentRankings.practicalInstructors);
        break;
      case 'T':
        rankedInstructors = List.from(currentRankings.tutorialInstructors);
        break;
      default:
        rankedInstructors = [];
    }

    for (final instructor in availableInstructors) {
      if (!rankedInstructors.contains(instructor)) {
        rankedInstructors.add(instructor);
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    typeKey,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$typeName Instructors',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rankedInstructors.length} instructor${rankedInstructors.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
              // ListTiles paint ink/background on the nearest Material; provide a
              // transparent one above the decorated box so they stay visible.
              child: Material(
                color: Colors.transparent,
                child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rankedInstructors.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final instructor = rankedInstructors.removeAt(oldIndex);
                    rankedInstructors.insert(newIndex, instructor);
                    _writeBackRanking(courseCode, typeKey, rankedInstructors);
                  });
                },
                itemBuilder: (context, index) {
                  final instructor = rankedInstructors[index];
                  final position = index + 1;
                  final isTopRank = position <= 3;

                  return Padding(
                    key: ValueKey('$courseCode-$typeKey-$instructor'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    // Color/shape live on the ListTile (tileColor + shape) rather
                    // than a wrapping decorated Container, so the tile's ink and
                    // background stay visible.
                    child: ListTile(
                      tileColor: isTopRank
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: isTopRank
                            ? BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))
                            : BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isTopRank
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            position.toString(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        instructor,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isTopRank ? FontWeight.w600 : FontWeight.normal,
                          color: isTopRank
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      subtitle: isTopRank ? Text(
                        position == 1 ? 'Most preferred' :
                        position == 2 ? '2nd preference' :
                        '3rd preference',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: position == 1 ? 'Pinned as most preferred' : 'Pin as most preferred',
                            onPressed: position == 1
                                ? null
                                : () => _pinToTop(courseCode, typeKey, rankedInstructors, index),
                            icon: Icon(
                              position == 1 ? Icons.push_pin : Icons.push_pin_outlined,
                              size: 18,
                              color: position == 1
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          Icon(
                            Icons.drag_handle,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
