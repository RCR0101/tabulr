import 'package:flutter/material.dart';
import '../services/data/admin_service.dart';
import '../services/data/auth_service.dart';
import '../services/ui/tutorial_service.dart';
import '../utils/design_constants.dart';
import '../screens/credits_screen.dart';
import '../screens/profile_screen.dart';
import 'app_destinations.dart';

class AppSidebar extends StatefulWidget {
  final DrawerScreen currentScreen;
  final ValueChanged<DrawerScreen> onScreenSelected;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onShowCommandPalette;

  const AppSidebar({
    super.key,
    required this.currentScreen,
    required this.onScreenSelected,
    required this.collapsed,
    required this.onToggleCollapse,
    this.onShowCommandPalette,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final AuthService _auth = AuthService();
  final AdminService _adminService = AdminService();
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _adminService.addListener(_onAdminChanged);
  }

  @override
  void dispose() {
    _adminService.removeListener(_onAdminChanged);
    super.dispose();
  }

  void _onAdminChanged() {
    if (mounted) setState(() {});
  }

  /// Straight from [AppDestinations] — the sidebar no longer keeps its own
  /// copy of the navigation surface, so it can't drift from the command
  /// palette the way it did when Minors and Academic FAQ landed here only.
  List<AppDestination> _buildItems() => AppDestinations.visible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _buildItems();
    final collapsed = widget.collapsed;

    return AnimatedContainer(
      key: TutorialKeys.sidebarNav,
      duration: AppDesign.animDurationNormal,
      curve: AppDesign.animCurve,
      clipBehavior: Clip.hardEdge,
      width: collapsed
          ? AppDesign.sidebarCollapsedWidth
          : AppDesign.sidebarWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, scheme, collapsed),
              if (widget.onShowCommandPalette != null)
                _buildSearchButton(context, scheme, collapsed),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDesign.spacingSm,
                    horizontal: AppDesign.spacingSm,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = item.screen == widget.currentScreen;
                    final isHovered = _hoveredIndex == index;
                    return _buildItem(
                      context, scheme, item, isSelected, isHovered, index, collapsed,
                    );
                  },
                ),
              ),
              _buildFooter(context, scheme, collapsed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme, bool collapsed) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? AppDesign.spacingSm : AppDesign.spacingMd,
        vertical: AppDesign.spacingMd,
      ),
      child: Row(
        mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppDesign.borderRadiusSm,
            child: Image.asset(
              'images/logo_nobg.png',
              width: 36,
              height: 36,
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: AppDesign.spacingSm + 4),
            AnimatedOpacity(
              opacity: collapsed ? 0.0 : 1.0,
              duration: AppDesign.animDurationFast,
              child: Text(
                'Tabulr',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchButton(
      BuildContext context, ColorScheme scheme, bool collapsed) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final shortcut = isMac ? '⌘K' : 'Ctrl K';

    final button = InkWell(
      onTap: widget.onShowCommandPalette,
      borderRadius: AppDesign.borderRadiusSm,
      child: AnimatedContainer(
        duration: AppDesign.animDurationFast,
        curve: AppDesign.animCurve,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? AppDesign.spacingSm : AppDesign.spacingSm + 4,
          vertical: AppDesign.spacingSm + 2,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: AppDesign.borderRadiusSm,
          border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
        ),
        child: collapsed
            ? Center(
                child: Icon(Icons.search,
                    size: 20, color: scheme.onSurface.withValues(alpha: 0.6)),
              )
            : Row(
                children: [
                  Icon(Icons.search,
                      size: 18, color: scheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: AppDesign.spacingSm + 4),
                  Expanded(
                    child: Text(
                      'Search…',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      shortcut,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? AppDesign.spacingSm : AppDesign.spacingSm + 4,
        0,
        collapsed ? AppDesign.spacingSm : AppDesign.spacingSm + 4,
        AppDesign.spacingSm,
      ),
      child: Tooltip(
        message: collapsed ? 'Search  ·  $shortcut' : '',
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: button,
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ColorScheme scheme,
    AppDestination item,
    bool isSelected,
    bool isHovered,
    int index,
    bool collapsed,
  ) {
    final icon = Icon(
      item.icon,
      size: collapsed ? 22 : 20,
      color: isSelected
          ? scheme.primary
          : scheme.onSurface.withValues(alpha: 0.7),
    );

    final content = collapsed
        ? Center(child: icon)
        : Row(
            children: [
              icon,
              const SizedBox(width: AppDesign.spacingSm + 4),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? scheme.primary : scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingXxs),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: Tooltip(
          message: collapsed ? item.label : '',
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 400),
          child: Semantics(
            label: item.label,
            button: true,
            selected: isSelected,
            child: GestureDetector(
            onTap: () => widget.onScreenSelected(item.screen),
            child: AnimatedContainer(
              duration: AppDesign.animDurationFast,
              curve: AppDesign.animCurve,
              padding: EdgeInsets.symmetric(
                horizontal: collapsed
                    ? AppDesign.spacingSm
                    : AppDesign.spacingSm + 4,
                vertical: AppDesign.spacingSm + 2,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : isHovered
                        ? scheme.onSurface.withValues(alpha: 0.06)
                        : Colors.transparent,
                borderRadius: AppDesign.borderRadiusSm,
              ),
              child: content,
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme scheme, bool collapsed) {
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingSm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_auth.isAuthenticated)
            _profileFooterButton(context, scheme, collapsed),
          collapsed
          ? (widget.onToggleCollapse != null
              ? Center(
                  child: IconButton(
                    onPressed: widget.onToggleCollapse,
                    icon: const Icon(Icons.chevron_right, size: 20),
                    tooltip: 'Expand sidebar',
                  ),
                )
              : const SizedBox.shrink())
          : Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: AppDesign.borderRadiusSm,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreditsScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppDesign.spacingSm,
                          vertical: AppDesign.spacingXs + 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: scheme.onSurface.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: AppDesign.spacingSm),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Made with ',
                                  style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.4)),
                                ),
                                Icon(Icons.favorite, size: 11, color: Colors.red.withValues(alpha: 0.6)),
                                Text(
                                  ' for students',
                                  style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onToggleCollapse,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  tooltip: 'Collapse sidebar',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _profileFooterButton(
      BuildContext context, ColorScheme scheme, bool collapsed) {
    void open() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );

    if (collapsed) {
      return Center(
        child: IconButton(
          onPressed: open,
          icon: const Icon(Icons.badge_outlined, size: 20),
          tooltip: 'Profile',
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return InkWell(
      borderRadius: AppDesign.borderRadiusSm,
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.spacingSm, vertical: AppDesign.spacingSm),
        child: Row(
          children: [
            Icon(Icons.badge_outlined,
                size: 18, color: scheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: AppDesign.spacingSm + 4),
            Text(
              'Profile',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
