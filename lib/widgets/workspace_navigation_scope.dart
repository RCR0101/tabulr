import 'package:flutter/material.dart';

import 'app_workspaces.dart';

/// Supplies workspace navigation to feature app bars without coupling feature
/// screens to the outer shell.
class WorkspaceNavigationScope extends InheritedWidget {
  const WorkspaceNavigationScope({
    super.key,
    required this.mobile,
    required this.entries,
    required this.selectedId,
    required this.onEntrySelected,
    required this.onSearch,
    required this.tabVisibility,
    required super.child,
  });

  final bool mobile;
  final List<WorkspaceEntry> entries;
  final String selectedId;
  final ValueChanged<WorkspaceEntry> onEntrySelected;
  final VoidCallback onSearch;
  final double tabVisibility;

  static WorkspaceNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceNavigationScope>();

  PreferredSizeWidget? combineAppBarBottom(PreferredSizeWidget? pageBottom) {
    final workspaceBottom =
        mobile && entries.length > 1
            ? PreferredSize(
              preferredSize: Size.fromHeight(48 * tabVisibility),
              child: ClipRect(
                child: Align(
                  heightFactor: tabVisibility,
                  alignment: Alignment.bottomCenter,
                  child: WorkspaceTabs(
                    entries: entries,
                    selectedId: selectedId,
                    onSelected: onEntrySelected,
                  ),
                ),
              ),
            )
            : null;
    if (workspaceBottom == null) return pageBottom;
    if (pageBottom == null) return workspaceBottom;
    return PreferredSize(
      preferredSize: Size.fromHeight(
        workspaceBottom.preferredSize.height + pageBottom.preferredSize.height,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [workspaceBottom, pageBottom],
      ),
    );
  }

  @override
  bool updateShouldNotify(WorkspaceNavigationScope oldWidget) =>
      mobile != oldWidget.mobile ||
      selectedId != oldWidget.selectedId ||
      entries != oldWidget.entries ||
      onEntrySelected != oldWidget.onEntrySelected ||
      onSearch != oldWidget.onSearch ||
      tabVisibility != oldWidget.tabVisibility;
}

class WorkspaceTabs extends StatefulWidget {
  const WorkspaceTabs({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.onSelected,
  });

  final List<WorkspaceEntry> entries;
  final String selectedId;
  final ValueChanged<WorkspaceEntry> onSelected;

  @override
  State<WorkspaceTabs> createState() => _WorkspaceTabsState();
}

class _WorkspaceTabsState extends State<WorkspaceTabs> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(WorkspaceTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) _revealSelection();
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectedKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surfaceContainerLowest),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
        child: Row(
          children: [
            for (final entry in widget.entries)
              Semantics(
                selected: entry.id == widget.selectedId,
                button: true,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton(
                    // One pill does fill, hover and ripple: a square ripple over
                    // a rounded fill was the shape that read as boxy.
                    key:
                        entry.id == widget.selectedId
                            ? _selectedKey
                            : ValueKey(entry.id),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor:
                          entry.id == widget.selectedId
                              ? scheme.primaryContainer.withValues(alpha: .62)
                              : Colors.transparent,
                      foregroundColor:
                          entry.id == widget.selectedId
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                      shape: const StadiumBorder(),
                      animationDuration:
                          MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                    ),
                    onPressed: () => widget.onSelected(entry),
                    child: Text(entry.label),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
