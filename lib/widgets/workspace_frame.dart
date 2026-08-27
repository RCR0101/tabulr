import 'package:flutter/material.dart';
import '../services/ui/responsive_service.dart';
import 'app_sidebar.dart';
import 'app_workspaces.dart';

/// Navigation chrome shared by every workspace, with feature bodies kept lazy
/// by the shell. No nested Navigator: editor leave guards stay on the root.
class WorkspaceFrame extends StatelessWidget {
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

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final info in workspaces)
                  if (!AppWorkspaces.primary.take(4).contains(info.workspace))
                    ListTile(
                      leading: Icon(info.icon),
                      title: Text(info.label),
                      selected: info.workspace == workspace.workspace,
                      onTap: () {
                        Navigator.pop(ctx);
                        onWorkspaceSelected(info.workspace);
                      },
                    ),
                const Divider(),
                if (onProfile != null)
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Profile'),
                    onTap: () {
                      Navigator.pop(ctx);
                      onProfile!();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onTheme();
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
    final primary = workspaces
        .where((w) => AppWorkspaces.primary.take(4).contains(w.workspace))
        .toList();
    final primaryIndex = primary.indexWhere(
      (w) => w.workspace == workspace.workspace,
    );
    final content = Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 28,
            mobile ? 6 : 20,
            mobile ? 8 : 28,
            0,
          ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workspace.label,
                          style:
                              (mobile
                                      ? Theme.of(context).textTheme.titleLarge
                                      : Theme.of(
                                          context,
                                        ).textTheme.headlineMedium)
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -.6,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (mobile)
                    IconButton(
                      onPressed: onSearch,
                      icon: const Icon(Icons.search_rounded, size: 21),
                      tooltip: 'Search anything',
                    ),
                  if (mobile)
                    IconButton(
                      onPressed: () => _showMore(context),
                      icon: const Icon(Icons.more_horiz),
                      tooltip: 'Help and more',
                    ),
                ],
              ),
              if (entries.length > 1)
                WorkspaceTabs(
                  entries: entries,
                  selectedId: selectedId,
                  onSelected: onEntrySelected,
                )
              else
                const SizedBox(height: 14),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
    return Scaffold(
      body: mobile
          ? SafeArea(bottom: false, child: content)
          : Row(
              children: [
                AppSidebar(
                  currentWorkspace: workspace.workspace,
                  workspaces: workspaces,
                  onWorkspaceSelected: onWorkspaceSelected,
                  collapsed: tablet || collapsed,
                  onToggleCollapse: tablet ? null : onToggleCollapse,
                  onShowCommandPalette: onSearch,
                  onShowProfile: onProfile,
                  onShowTheme: onTheme,
                ),
                Expanded(child: content),
              ],
            ),
      bottomNavigationBar: mobile
          ? NavigationBar(
              height: 68,
              elevation: 0,
              backgroundColor: scheme.surface,
              indicatorColor: scheme.primaryContainer,
              selectedIndex: primaryIndex < 0 ? primary.length : primaryIndex,
              onDestinationSelected: (index) => index == primary.length
                  ? _showMore(context)
                  : onWorkspaceSelected(primary[index].workspace),
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
    );
  }
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in widget.entries)
            Semantics(
              selected: entry.id == widget.selectedId,
              button: true,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                key: entry.id == widget.selectedId
                    ? _selectedKey
                    : ValueKey(entry.id),
                margin: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: entry.id == widget.selectedId
                          ? scheme.primary
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    foregroundColor: entry.id == widget.selectedId
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    shape: const RoundedRectangleBorder(),
                  ),
                  onPressed: () => widget.onSelected(entry),
                  child: Text(entry.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
