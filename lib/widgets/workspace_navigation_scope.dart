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
              preferredSize: Size.fromHeight(
                WorkspaceTabs.preferredHeight * tabVisibility,
              ),
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
    this.inset = 16,
  });

  final List<WorkspaceEntry> entries;
  final String selectedId;
  final ValueChanged<WorkspaceEntry> onSelected;

  static const double preferredHeight = 52;

  /// Page margin the strip lines up on. Defaults to the mobile content margin.
  final double inset;

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
        Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration:
              MediaQuery.disableAnimationsOf(target)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: WorkspaceTabs.preferredHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: widget.inset),
        child: Row(
          children: [
            for (final entry in widget.entries)
              _WorkspaceTab(
                key:
                    entry.id == widget.selectedId
                        ? _selectedKey
                        : ValueKey(entry.id),
                label: entry.label,
                selected: entry.id == widget.selectedId,
                reduceMotion: reduceMotion,
                onTap: () => widget.onSelected(entry),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    super.key,
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: scheme.primary.withValues(alpha: 0.05),
          focusColor: scheme.primary.withValues(alpha: 0.08),
          splashColor: scheme.primary.withValues(alpha: 0.08),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: WorkspaceTabs.preferredHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(label, maxLines: 1),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 3,
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      height: 2,
                      color: selected ? scheme.primary : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
