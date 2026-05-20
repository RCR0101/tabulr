import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/course_announcement_service.dart';
import '../utils/design_constants.dart';
import 'app_drawer.dart';

class AppSidebar extends StatefulWidget {
  final DrawerScreen currentScreen;
  final ValueChanged<DrawerScreen> onScreenSelected;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  const AppSidebar({
    super.key,
    required this.currentScreen,
    required this.onScreenSelected,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final AuthService _auth = AuthService();
  int? _hoveredIndex;

  List<_SidebarItem> _buildItems() {
    final items = <_SidebarItem>[
      _SidebarItem(
        screen: DrawerScreen.timetables,
        icon: Icons.schedule,
        label: 'TT Builder',
      ),
    ];

    if (_auth.isAuthenticated) {
      items.add(_SidebarItem(
        screen: DrawerScreen.calendar,
        icon: Icons.calendar_month,
        label: 'Calendar',
      ));
    }

    if (_auth.isAuthenticated) {
      items.add(_SidebarItem(
        screen: DrawerScreen.cgpaCalculator,
        icon: Icons.calculate,
        label: 'CGPA',
      ));
    }

    items.add(_SidebarItem(
      screen: DrawerScreen.examSeating,
      icon: Icons.event_seat,
      label: 'Exam Seating',
    ));

    if (_auth.isAuthenticated) {
      items.add(_SidebarItem(
        screen: DrawerScreen.acadDrives,
        icon: Icons.folder_shared,
        label: 'Acad Drives',
      ));
      items.add(_SidebarItem(
        screen: DrawerScreen.profChambers,
        icon: Icons.person,
        label: 'Prof Chambers',
      ));
    }

    if (_auth.isAuthenticated &&
        CourseAnnouncementService().isHyderabadUser()) {
      items.add(_SidebarItem(
        screen: DrawerScreen.announcements,
        icon: Icons.campaign,
        label: 'Announcements',
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _buildItems();

    return AnimatedContainer(
      duration: AppDesign.animDurationNormal,
      curve: AppDesign.animCurve,
      width: widget.collapsed
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
            // Header
            _buildHeader(context, scheme),

            // Menu items
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
                    context, scheme, item, isSelected, isHovered, index,
                  );
                },
              ),
            ),

            // Footer — collapse toggle
            _buildFooter(context, scheme),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.collapsed ? AppDesign.spacingSm : AppDesign.spacingMd,
        vertical: AppDesign.spacingMd,
      ),
      child: widget.collapsed
          ? Center(
              child: Container(
                padding: const EdgeInsets.all(AppDesign.spacingSm),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Icon(
                  Icons.school,
                  size: 22,
                  color: scheme.primary,
                ),
              ),
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDesign.spacingSm),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: AppDesign.borderRadiusSm,
                  ),
                  child: Icon(
                    Icons.school,
                    size: 22,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: AppDesign.spacingSm + 4),
                Text(
                  'Tabulr',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ColorScheme scheme,
    _SidebarItem item,
    bool isSelected,
    bool isHovered,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingXxs),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTap: () => widget.onScreenSelected(item.screen),
          child: AnimatedContainer(
            duration: AppDesign.animDurationFast,
            curve: AppDesign.animCurve,
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed
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
            child: widget.collapsed
                ? Tooltip(
                    message: item.label,
                    preferBelow: false,
                    child: Center(
                      child: Icon(
                        item.icon,
                        size: 22,
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 20,
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: AppDesign.spacingSm + 4),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingSm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: widget.collapsed
          ? IconButton(
              onPressed: widget.onToggleCollapse,
              icon: const Icon(Icons.chevron_right, size: 20),
              tooltip: 'Expand sidebar',
            )
          : Row(
              children: [
                const SizedBox(width: AppDesign.spacingSm),
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: AppDesign.spacingSm),
                Expanded(
                  child: Text(
                    'Made with ❤️ for students',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.4),
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
    );
  }
}

class _SidebarItem {
  final DrawerScreen screen;
  final IconData icon;
  final String label;

  const _SidebarItem({
    required this.screen,
    required this.icon,
    required this.label,
  });
}
