import 'package:flutter/material.dart';
import '../services/ui/tutorial_service.dart';
import '../utils/design_constants.dart';
import 'app_workspaces.dart';

/// Shared desktop/tablet rail. It deliberately knows nothing about Firebase.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentWorkspace,
    required this.workspaces,
    required this.onWorkspaceSelected,
    required this.collapsed,
    this.onToggleCollapse,
    required this.onShowCommandPalette,
    required this.onShowProfile,
    required this.onShowTheme,
  });

  final AppWorkspace currentWorkspace;
  final List<WorkspaceInfo> workspaces;
  final ValueChanged<AppWorkspace> onWorkspaceSelected;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback onShowCommandPalette;
  final VoidCallback? onShowProfile;
  final VoidCallback onShowTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppDesign.animDurationNormal;
    return AnimatedContainer(
      key: TutorialKeys.sidebarNav,
      duration: motion,
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.hardEdge,
      width: collapsed ? 76 : 232,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerLow,
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.045),
              scheme.surface,
            ),
          ],
        ),
        border: Border(
          right: BorderSide(color: scheme.outline.withValues(alpha: 0.12)),
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      collapsed ? 16 : 22,
                      28,
                      16,
                      28,
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          'images/logo_nobg.png',
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          semanticLabel: 'Tabulr logo',
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: motion,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder:
                                (child, animation) => FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    axis: Axis.horizontal,
                                    alignment: AlignmentDirectional.topStart,
                                    child: child,
                                  ),
                                ),
                            child:
                                collapsed
                                    ? const SizedBox.shrink(
                                      key: ValueKey('collapsed-brand'),
                                    )
                                    : Padding(
                                      key: const ValueKey('expanded-brand'),
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'tabulr',
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.headlineSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -1,
                                            ),
                                          ),
                                          Text(
                                            'ACADEMIC WORKSPACE',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: .6,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _item(
                      context,
                      Icons.search_rounded,
                      'Search anything',
                      onShowCommandPalette,
                      outlined: true,
                      shortcut: true,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSize(
                    duration: motion,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child:
                        collapsed
                            ? const SizedBox.shrink()
                            : Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'WORKSPACES',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.6,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        for (final info in workspaces)
                          if (AppWorkspaces.primary.contains(info.workspace))
                            _workspaceItem(context, info),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final info in workspaces)
                          if (!AppWorkspaces.primary.contains(info.workspace))
                            _workspaceItem(context, info),
                        const SizedBox(height: 8),
                        Divider(color: scheme.outline.withValues(alpha: 0.15)),
                        if (onShowProfile != null)
                          _item(
                            context,
                            Icons.badge_outlined,
                            'Profile',
                            onShowProfile!,
                          ),
                        _item(
                          context,
                          Icons.palette_outlined,
                          'Appearance',
                          onShowTheme,
                        ),
                        if (onToggleCollapse != null)
                          _item(
                            context,
                            collapsed
                                ? Icons.keyboard_double_arrow_right
                                : Icons.keyboard_double_arrow_left,
                            'Collapse sidebar',
                            onToggleCollapse!,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceItem(BuildContext context, WorkspaceInfo info) => _item(
    context,
    info.icon,
    info.label,
    () => onWorkspaceSelected(info.workspace),
    selected: currentWorkspace == info.workspace,
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool selected = false,
    bool outlined = false,
    bool shortcut = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    final motion =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppDesign.animDurationFast;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        selected: selected,
        button: true,
        child: Tooltip(
          message:
              shortcut
                  ? 'Search anything'
                  : collapsed
                  ? label
                  : '',
          child: TweenAnimationBuilder<Color?>(
            duration: motion,
            curve: Curves.easeOutCubic,
            tween: ColorTween(
              end: selected ? scheme.primary : Colors.transparent,
            ),
            builder:
                (context, color, child) => Material(
                  color: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side:
                        outlined
                            ? BorderSide(
                              color: scheme.outline.withValues(alpha: 0.2),
                            )
                            : BorderSide.none,
                  ),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 0 : 12,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment:
                              collapsed
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                          children: [
                            Icon(icon, size: 20, color: foreground),
                            if (!collapsed) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  shortcut ? 'Search' : label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                    color: foreground,
                                  ),
                                ),
                              ),
                              if (shortcut)
                                Text(
                                  Theme.of(context).platform ==
                                          TargetPlatform.macOS
                                      ? 'Cmd K'
                                      : 'Ctrl K',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              if (selected)
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: foreground,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
