import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../services/ui/responsive_service.dart';
import 'app_sidebar.dart';
import 'app_workspaces.dart';
import 'workspace_navigation_scope.dart';

/// Navigation chrome shared by every workspace, with feature bodies kept lazy
/// by the shell. No nested Navigator: editor leave guards stay on the root.
class WorkspaceFrame extends StatefulWidget {
  const WorkspaceFrame({
    super.key,
    required this.workspace,
    required this.workspaces,
    required this.entries,
    required this.selectedId,
    required this.onWorkspaceSelected,
    required this.onEntrySelected,
    required this.onSearch,
    required this.onTheme,
    required this.onProfile,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.child,
  });

  final WorkspaceInfo workspace;
  final List<WorkspaceInfo> workspaces;
  final List<WorkspaceEntry> entries;
  final String selectedId;
  final ValueChanged<AppWorkspace> onWorkspaceSelected;
  final ValueChanged<WorkspaceEntry> onEntrySelected;
  final VoidCallback onSearch;
  final VoidCallback onTheme;
  final VoidCallback? onProfile;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final Widget child;

  @override
  State<WorkspaceFrame> createState() => _WorkspaceFrameState();
}

class _WorkspaceFrameState extends State<WorkspaceFrame> {
  bool _tabsVisible = true;

  @override
  void didUpdateWidget(WorkspaceFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.workspace.workspace != widget.workspace.workspace) {
      _showTabs();
    }
  }

  void _showTabs() {
    if (!_tabsVisible && mounted) setState(() => _tabsVisible = true);
  }

  void _hideTabs() {
    if (_tabsVisible && mounted) setState(() => _tabsVisible = false);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.pixels <= 8) {
      _showTabs();
    } else if (notification is ScrollUpdateNotification &&
        notification.scrollDelta != null) {
      if (notification.scrollDelta! > 2) {
        _hideTabs();
      } else if (notification.scrollDelta! < -2) {
        _showTabs();
      }
    } else if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.forward:
          _showTabs();
        case ScrollDirection.reverse:
          _hideTabs();
        case ScrollDirection.idle:
          break;
      }
    }
    return false;
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .8,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final info in widget.workspaces)
                      if (!AppWorkspaces.primary
                          .take(4)
                          .contains(info.workspace))
                        ListTile(
                          leading: Icon(info.icon),
                          title: Text(info.label),
                          selected:
                              info.workspace == widget.workspace.workspace,
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onWorkspaceSelected(info.workspace);
                          },
                        ),
                    const Divider(),
                    if (widget.onProfile != null)
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Profile'),
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onProfile!();
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Appearance'),
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onTheme();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ResponsiveService.isMobile(context);
    final tablet = ResponsiveService.isTablet(context);
    final scheme = Theme.of(context).colorScheme;
    final primary =
        widget.workspaces
            .where((w) => AppWorkspaces.primary.take(4).contains(w.workspace))
            .toList();
    final primaryIndex = primary.indexWhere(
      (w) => w.workspace == widget.workspace.workspace,
    );
    final desktopContent = Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: .14)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.workspace.label,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.6,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.entries.length > 1)
                WorkspaceTabs(
                  entries: widget.entries,
                  selectedId: widget.selectedId,
                  onSelected: widget.onEntrySelected,
                )
              else
                const SizedBox(height: 14),
            ],
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: keyboardVisible || !_tabsVisible ? 0 : 1),
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder:
          (context, tabVisibility, _) => WorkspaceNavigationScope(
            mobile: mobile,
            entries: widget.entries,
            selectedId: widget.selectedId,
            onEntrySelected: widget.onEntrySelected,
            onSearch: widget.onSearch,
            tabVisibility: tabVisibility,
            child: Scaffold(
              body:
                  mobile
                      ? _WorkspaceScrollBody(
                        onNotification: _handleScrollNotification,
                        child: widget.child,
                      )
                      : Row(
                        children: [
                          AppSidebar(
                            currentWorkspace: widget.workspace.workspace,
                            workspaces: widget.workspaces,
                            onWorkspaceSelected: widget.onWorkspaceSelected,
                            collapsed: tablet || widget.collapsed,
                            onToggleCollapse:
                                tablet ? null : widget.onToggleCollapse,
                            onShowCommandPalette: widget.onSearch,
                            onShowProfile: widget.onProfile,
                            onShowTheme: widget.onTheme,
                          ),
                          Expanded(child: desktopContent),
                        ],
                      ),
              bottomNavigationBar:
                  mobile
                      ? NavigationBar(
                        height: 68,
                        elevation: 0,
                        backgroundColor: scheme.surface,
                        indicatorColor: scheme.primaryContainer,
                        selectedIndex:
                            primaryIndex < 0 ? primary.length : primaryIndex,
                        onDestinationSelected:
                            (index) =>
                                index == primary.length
                                    ? _showMore(context)
                                    : widget.onWorkspaceSelected(
                                      primary[index].workspace,
                                    ),
                        destinations: [
                          for (final info in primary)
                            NavigationDestination(
                              icon: Icon(info.icon),
                              label: info.label,
                            ),
                          const NavigationDestination(
                            icon: Icon(Icons.grid_view_rounded),
                            label: 'More',
                          ),
                        ],
                      )
                      : null,
            ),
          ),
    );
  }
}

class _WorkspaceScrollBody extends StatefulWidget {
  const _WorkspaceScrollBody({
    required this.onNotification,
    required this.child,
  });

  final ValueChanged<ScrollNotification> onNotification;
  final Widget child;

  @override
  State<_WorkspaceScrollBody> createState() => _WorkspaceScrollBodyState();
}

class _WorkspaceScrollBodyState extends State<_WorkspaceScrollBody> {
  ScrollNotificationObserverState? _observer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextObserver = ScrollNotificationObserver.maybeOf(context);
    if (identical(nextObserver, _observer)) return;
    _observer?.removeListener(_onNotification);
    _observer = nextObserver?..addListener(_onNotification);
  }

  void _onNotification(ScrollNotification notification) {
    widget.onNotification(notification);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onNotification);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
