import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../utils/web_utils.dart' as web_utils;
import '../models/timetable.dart';
import '../utils/page_transitions.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/disclaimer_widget.dart';
import '../services/core/timetable_service.dart';
import '../services/data/auth_service.dart';
import '../services/ui/toast_service.dart';
import '../services/data/campus_service.dart';
import '../services/data/course_data_service.dart';
import '../services/data/user_settings_service.dart';
import '../services/ui/responsive_service.dart';
import '../models/user_settings.dart';
import '../utils/design_constants.dart';
import '../widgets/theme_selector_widget.dart';
import '../widgets/campus_selector_widget.dart';


import '../widgets/error_dialog.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../widgets/share_timetable_dialog.dart';
import 'home_screen.dart';
import 'course_guide_screen.dart';
import 'timetable_comparison_screen.dart';
import 'humanities_electives_screen.dart';
import 'discipline_electives_screen.dart';
import 'prerequisites_screen.dart';

class TimetablesScreen extends StatefulWidget {
  const TimetablesScreen({super.key});

  @override
  State<TimetablesScreen> createState() => _TimetablesScreenState();
}

class _TimetablesScreenState extends State<TimetablesScreen> {
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  final UserSettingsService _userSettingsService = UserSettingsService();
  List<Timetable> _timetables = [];
  List<Timetable> _sortedTimetables = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _userSettingsService.addListener(_onSettingsChanged);
    _authService.authStateChanges.listen((_) {
      if (mounted) {
        setState(() {}); // Rebuild to update drawer visibility
      }
    });
    _initializeAndLoadData();
  }

  Future<void> _initializeAndLoadData() async {
    await Future.wait([
      _userSettingsService.initializeSettings(),
      _loadTimetables(),
    ]);
  }

  @override
  void dispose() {
    _userSettingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  TimetableListSortOrder? _lastSortOrder;
  List<String>? _lastCustomOrder;

  void _onSettingsChanged() {
    if (!mounted) return;
    final currentSort = _userSettingsService.sortOrder;
    final currentCustom = _userSettingsService.customTimetableOrder;
    if (currentSort != _lastSortOrder || currentCustom != _lastCustomOrder) {
      _lastSortOrder = currentSort;
      _lastCustomOrder = currentCustom;
      _applySorting();
    }
  }

  Future<void> _loadTimetables() async {
    try {
      final timetables = await _timetableService.getAllTimetables();
      setState(() {
        _timetables = timetables;
        _isLoading = false;
      });
      _applySorting();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Error loading timetables: $e');
    }
  }

  Future<void> _createNewTimetable() async {
    final name = await _showCreateTimetableDialog();
    if (name != null && name.isNotEmpty) {
      try {
        final newTimetable = await _timetableService.createNewTimetable(name);
        setState(() {
          _timetables.add(newTimetable);
        });
        _applySorting();
        _openTimetable(newTimetable);
      } catch (e) {
        _showErrorDialog('Error creating timetable: $e');
      }
    }
  }

  Future<void> _importFromShareCode() async {
    final result = await ImportTimetableDialog.show(context);
    if (result == null || !mounted) return;
    try {
      final newTimetable = await _timetableService.createNewTimetable(result.name);
      for (final section in result.sections) {
        _timetableService.addSectionWithoutSaving(
          section.courseCode,
          section.sectionId,
          newTimetable,
        );
      }
      await _timetableService.saveTimetable(newTimetable);
      setState(() {
        _timetables.add(newTimetable);
      });
      _applySorting();
      if (mounted) {
        ToastService.showSuccess('Imported "${result.name}" from ${result.ownerName}');
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Error importing timetable: $e');
    }
  }

  Future<String?> _showCreateTimetableDialog() async {
    return AppDialog.input(
      context: context,
      title: 'Create New Timetable',
      hint: 'Enter a name for your timetable',
      confirmLabel: 'Create',
    );
  }

  Future<void> _renameTimetable(Timetable timetable) async {
    final newName = await AppDialog.input(
      context: context,
      title: 'Rename Timetable',
      initialValue: timetable.name,
      hint: 'Timetable Name',
      confirmLabel: 'Rename',
    );

    if (newName != null && newName.isNotEmpty && newName != timetable.name) {
      try {
        await _timetableService.updateTimetableName(timetable.id, newName);
        // Update local state instead of reloading from Firestore
        setState(() {
          final index = _timetables.indexWhere((t) => t.id == timetable.id);
          if (index != -1) {
            _timetables[index] = Timetable(
              id: timetable.id,
              name: newName,
              createdAt: timetable.createdAt,
              updatedAt: DateTime.now(),
              campus: timetable.campus,
              availableCourses: timetable.availableCourses,
              selectedSections: timetable.selectedSections,
              clashWarnings: timetable.clashWarnings,
            );
          }
        });
        _applySorting();
      } catch (e) {
        _showErrorDialog('Error renaming timetable: $e');
      }
    }
  }

  Future<void> _duplicateTimetable(Timetable timetable) async {
    final newName = await AppDialog.input(
      context: context,
      title: 'Duplicate Timetable',
      initialValue: '${timetable.name} (Copy)',
      hint: 'New Timetable Name',
      confirmLabel: 'Duplicate',
    );

    if (newName != null && newName.isNotEmpty) {
      try {
        final duplicatedTimetable = await _timetableService.duplicateTimetable(timetable, newName);
        
        setState(() {
          _timetables.add(duplicatedTimetable);
        });
        _applySorting();
      } catch (e) {
        _showErrorDialog('Error duplicating timetable: $e');
      }
    }
  }

  Future<void> _deleteTimetable(Timetable timetable) async {
    if (_sortedTimetables.length <= 1) {
      _showErrorDialog('Cannot delete the last timetable');
      return;
    }

    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Delete Timetable',
      message: 'Are you sure you want to delete "${timetable.name}"? This action cannot be undone.',
      confirmLabel: 'Delete',
      isDangerous: true,
    );

    if (confirmed) {
      try {
        await _timetableService.deleteTimetable(timetable.id);
        setState(() {
          _timetables.removeWhere((t) => t.id == timetable.id);
        });
        // Remove from user settings as well
        await _userSettingsService.removeTimetableSettings(timetable.id);
        _applySorting();
      } catch (e) {
        _showErrorDialog('Error deleting timetable: $e');
      }
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    // Only allow reordering if custom sort is enabled
    if (_userSettingsService.sortOrder != TimetableListSortOrder.custom) {
      return;
    }

    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _sortedTimetables.removeAt(oldIndex);
      _sortedTimetables.insert(newIndex, item);
    });

    // Update custom sort order in settings
    final newOrder = _sortedTimetables.map((t) => t.id).toList();
    _userSettingsService.updateCustomTimetableOrder(newOrder);
  }

  void _openTimetable(Timetable timetable) {
    Navigator.push(
      context,
      FadeSlidePageRoute(page: TimetableEditorScreen(timetableId: timetable.id)),
    ).then((result) {
      // Only refresh if there were changes (optional optimization)
      // For now, we'll keep the refresh but consider reducing frequency
      if (result != null) {
        _loadTimetables();
      }
    });
  }

  void _showErrorDialog(String message) {
    ErrorDialog.show(context, message);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showClearAllDialog() async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Clear All Timetables',
      message: 'Are you sure you want to delete all ${_sortedTimetables.length} timetables? This action cannot be undone.',
      confirmLabel: 'Clear All',
      isDangerous: true,
    );

    if (confirmed) {
      _clearAllTimetables();
    }
  }

  Future<void> _clearAllTimetables() async {
    try {
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      // Delete all timetables
      for (var timetable in _sortedTimetables) {
        await _timetableService.deleteTimetable(timetable.id);
        // Also remove from user settings if using custom order
        await _userSettingsService.removeTimetableSettings(timetable.id);
      }

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Reload timetables
      await _loadTimetables();

      // Show success message
      if (mounted) {
        ToastService.showSuccess('All timetables have been cleared');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
      }

      _showErrorDialog('Error clearing timetables: $e');
    }
  }

  void _applySorting() {
    final sortOrder = _userSettingsService.sortOrder;
    final customOrder = _userSettingsService.customTimetableOrder;
    List<Timetable> sorted = List.from(_timetables);

    switch (sortOrder) {
      case TimetableListSortOrder.dateCreatedAsc:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case TimetableListSortOrder.dateCreatedDesc:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case TimetableListSortOrder.dateModifiedAsc:
        sorted.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case TimetableListSortOrder.dateModifiedDesc:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case TimetableListSortOrder.alphabeticalAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case TimetableListSortOrder.alphabeticalDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case TimetableListSortOrder.custom:
        if (customOrder.isNotEmpty) {
          sorted.sort((a, b) {
            final indexA = customOrder.indexOf(a.id);
            final indexB = customOrder.indexOf(b.id);
            // If item not in custom order, put it at the end
            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            return indexA.compareTo(indexB);
          });
        }
        break;
    }

    setState(() {
      _sortedTimetables = sorted;
    });
  }

  Future<void> _showSortDialog() async {
    // Ensure user settings are initialized
    if (_userSettingsService.userSettings == null) {
      await _userSettingsService.initializeSettings();
    }

    final currentSort = _userSettingsService.sortOrder;

    if (!mounted) return;

    final scheme = Theme.of(context).colorScheme;
    AppDialog.adaptive(
      context: context,
      title: 'Sort Timetables',
      icon: Icons.sort,
      content: SizedBox(
        width: 340,
        child: Column(
              mainAxisSize: MainAxisSize.min,
              children: TimetableListSortOrder.values.map((sortOrder) {
                final isSelected = currentSort == sortOrder;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: isSelected
                        ? scheme.primaryContainer.withValues(alpha: 0.5)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        await _userSettingsService.updateSortOrder(sortOrder);
                        navigator.pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              _getSortIcon(sortOrder),
                              size: 20,
                              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _getSortOrderName(sortOrder),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected ? scheme.primary : scheme.onSurface,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_rounded, size: 20, color: scheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  String _getSortOrderName(TimetableListSortOrder sortOrder) {
    switch (sortOrder) {
      case TimetableListSortOrder.dateCreatedAsc:
        return 'Date Created (Oldest First)';
      case TimetableListSortOrder.dateCreatedDesc:
        return 'Date Created (Newest First)';
      case TimetableListSortOrder.dateModifiedAsc:
        return 'Date Modified (Oldest First)';
      case TimetableListSortOrder.dateModifiedDesc:
        return 'Date Modified (Newest First)';
      case TimetableListSortOrder.alphabeticalAsc:
        return 'Name (A-Z)';
      case TimetableListSortOrder.alphabeticalDesc:
        return 'Name (Z-A)';
      case TimetableListSortOrder.custom:
        return 'Custom Order';
    }
  }

  IconData _getSortIcon(TimetableListSortOrder sortOrder) {
    switch (sortOrder) {
      case TimetableListSortOrder.dateCreatedAsc:
      case TimetableListSortOrder.dateCreatedDesc:
        return Icons.schedule;
      case TimetableListSortOrder.dateModifiedAsc:
      case TimetableListSortOrder.dateModifiedDesc:
        return Icons.history;
      case TimetableListSortOrder.alphabeticalAsc:
      case TimetableListSortOrder.alphabeticalDesc:
        return Icons.sort_by_alpha;
      case TimetableListSortOrder.custom:
        return Icons.drag_handle;
    }
  }

  Future<void> _openGitHub() async {
    const String githubUrl = 'https://github.com/RCR0101/timetable_maker';

    try {
      if (kIsWeb) {
        web_utils.openUrl(githubUrl);
      } else {
        await launchUrl(Uri.parse(githubUrl));
      }
    } catch (e) {
      // ignored
    }
  }

  Future<void> _logout() async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      isDangerous: true,
    );

    if (confirmed) {
      try {
        await _authService.signOut();
        // Navigation will be handled by AuthWrapper
      } catch (e) {
        _showErrorDialog('Error signing out: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: TimetableListSkeleton());
    }

    return Scaffold(
      appBar: AppBar(
        title:
            ResponsiveService.isMobile(context)
                ? null
                : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: AppDesign.borderRadiusSm,
                        child: Image.asset(
                          'images/full_logo_bg.png',
                          height: 50,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
        actions: [
          if (!ResponsiveService.isMobile(context))
            CampusSelectorWidget(
              onCampusChanged: (campus) {
                CourseDataService().clearCache();
                ToastService.showInfo(
                  'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
                );
              },
            ),
          const SizedBox(width: AppDesign.spacingXs),
          PopupMenuButton<String>(
            icon: const Icon(Icons.apps, size: 22),
            tooltip: 'Tools',
            onSelected: (value) {
              switch (value) {
                case 'course_guide':
                  Navigator.push(context, FadeSlidePageRoute(page: const CourseGuideScreen()));
                  break;
                case 'prerequisites':
                  Navigator.push(context, FadeSlidePageRoute(page: const PrerequisitesScreen()));
                  break;
                case 'discipline_electives':
                  Navigator.push(context, FadeSlidePageRoute(page: const DisciplineElectivesScreen()));
                  break;
                case 'humanities_electives':
                  Navigator.push(context, FadeSlidePageRoute(page: const HumanitiesElectivesScreen()));
                  break;
                case 'github':
                  _openGitHub();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (ResponsiveService.isMobile(context)) ...[
                PopupMenuItem(
                  enabled: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Campus', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                          fontWeight: FontWeight.w600,
                        )),
                        const SizedBox(height: AppDesign.spacingXs),
                        CampusSelectorWidget(
                          onCampusChanged: (campus) {
                            Navigator.pop(context);
                            CourseDataService().clearCache();
                            ToastService.showInfo('Switched to ${CampusService.getCampusDisplayName(campus)} campus');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(
                value: 'course_guide',
                child: ListTile(leading: Icon(Icons.menu_book), title: Text('Course Guide'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'prerequisites',
                child: ListTile(leading: Icon(Icons.account_tree), title: Text('Prerequisites'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'discipline_electives',
                child: ListTile(leading: Icon(Icons.school), title: Text('Discipline Electives'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'humanities_electives',
                child: ListTile(leading: Icon(Icons.library_books), title: Text('Humanities Electives'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'github',
                child: ListTile(leading: Icon(Icons.star_border), title: Text('Star on GitHub'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
          const ThemeToggleButton(),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => [
              if (_authService.isAuthenticated) ...[
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_authService.userName ?? 'User', style: Theme.of(context).textTheme.titleSmall),
                      Text(_authService.userEmail ?? '', style: Theme.of(context).textTheme.bodySmall),
                      const Divider(),
                    ],
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  enabled: false,
                  child: ListTile(leading: Icon(Icons.person_outline), title: Text('Guest User'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Sign Out'), contentPadding: EdgeInsets.zero),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _authService.isAuthenticated
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: _authService.userPhotoUrl != null ? _authService.userPhotoImage : null,
                          child: _authService.userPhotoUrl == null ? const Icon(Icons.person, size: 16) : null,
                        ),
                        const SizedBox(width: AppDesign.spacingXs),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 22),
                        SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: AppDesign.spacingXs),
        ],
      ),
      body: Column(
        children: [
          // Top announcement widget
          const TopAnnouncementWidget(),
          
          // Main content
          Expanded(
            child: _sortedTimetables.isEmpty
                ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppDesign.spacingMd),
                    Text(
                      'No timetables yet',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: AppDesign.spacingSm),
                    Text(
                      'Create your first timetable to get started',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              )
                : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                        onTap: _showSortDialog,
                        borderRadius: AppDesign.borderRadiusSm,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getSortIcon(_userSettingsService.sortOrder),
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getSortOrderName(_userSettingsService.sortOrder),
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                                ),
                              ),
                              const SizedBox(width: AppDesign.spacingXs),
                              Icon(
                                Icons.unfold_more,
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ),
                    Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(AppDesign.spacingMd),
                      itemCount: _sortedTimetables.length,
                      onReorder: _onReorder,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, index) {
                        final timetable = _sortedTimetables[index];
                        final isCustomSort =
                            _userSettingsService.sortOrder ==
                            TimetableListSortOrder.custom;
                        final courseCodes = timetable.selectedSections.map((s) => s.courseCode).toSet().toList();
                        double totalCredits = 0;
                        for (final code in courseCodes) {
                          final course = timetable.availableCourses.where((c) => c.courseCode == code).firstOrNull;
                          if (course != null) totalCredits += course.totalCredits;
                        }
                        totalCredits += timetable.projectCount * 3;
                        final scheme = Theme.of(context).colorScheme;
                        return Card(
                          key: ValueKey(timetable.id),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: AppDesign.borderRadiusMd,
                            onTap: () => _openTimetable(timetable),
                            child: Padding(
                              padding: const EdgeInsets.all(AppDesign.spacingMd),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isCustomSort) ...[
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Icon(Icons.drag_handle, color: AppDesign.muted(context)),
                                        ),
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: Text(
                                          timetable.name,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                      ),
                                      if (totalCredits > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: scheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${totalCredits % 1 == 0 ? totalCredits.toInt() : totalCredits.toStringAsFixed(1)} cr',
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
                                          ),
                                        ),
                                      const SizedBox(width: AppDesign.spacingSm),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'rename':
                                              _renameTimetable(timetable);
                                              break;
                                            case 'duplicate':
                                              _duplicateTimetable(timetable);
                                              break;
                                            case 'delete':
                                              _deleteTimetable(timetable);
                                              break;
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'rename',
                                            child: ListTile(leading: Icon(Icons.edit), title: Text('Rename'), contentPadding: EdgeInsets.zero),
                                          ),
                                          const PopupMenuItem(
                                            value: 'duplicate',
                                            child: ListTile(leading: Icon(Icons.copy), title: Text('Duplicate'), contentPadding: EdgeInsets.zero),
                                          ),
                                          if (_sortedTimetables.length > 1)
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: ListTile(
                                                leading: Icon(Icons.delete, color: AppDesign.danger(context)),
                                                title: Text('Delete', style: TextStyle(color: AppDesign.danger(context))),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (courseCodes.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: courseCodes.map((code) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(code, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.8))),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  const SizedBox(height: AppDesign.spacingSm),
                                  Row(
                                    children: [
                                      Text(
                                        '${courseCodes.length} course${courseCodes.length != 1 ? 's' : ''}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium)),
                                      ),
                                      if (timetable.projectCount > 0) ...[
                                        Text(' · ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow))),
                                        Text('${timetable.projectCount} project${timetable.projectCount != 1 ? 's' : ''}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
                                      ],
                                      const Spacer(),
                                      Text(
                                        _formatDate(timetable.updatedAt),
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Clear All button at bottom
                  if (_sortedTimetables.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppDesign.spacingMd),
                      child:
                          ResponsiveService.isMobile(context)
                              ? Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    ResponsiveService.triggerHeavyFeedback(
                                      context,
                                    );
                                    _showClearAllDialog();
                                  },
                                  icon: Icon(
                                    Icons.clear_all,
                                    size: ResponsiveService.getAdaptiveIconSize(
                                      context,
                                      18,
                                    ),
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  label: Text(
                                    'Clear All',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    minimumSize: Size(
                                      0,
                                      ResponsiveService.getTouchTargetSize(
                                        context,
                                      ),
                                    ),
                                    padding:
                                        ResponsiveService.getAdaptivePadding(
                                          context,
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                        ),
                                  ),
                                ),
                              )
                              : Center(
                                child: TextButton.icon(
                                  onPressed: _showClearAllDialog,
                                  icon: Icon(
                                    Icons.clear_all,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  label: Text(
                                    'Clear All',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                    ),
                  ],
                ),
          ),
        ],
      ),
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      floatingActionButton: ResponsiveService.buildResponsive(
        context,
        mobile: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              onPressed: _importFromShareCode,
              tooltip: 'Import from Code',
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              heroTag: "import_code",
              child: const Icon(Icons.download),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  FadeSlidePageRoute(page: const TimetableComparisonScreen()),
                );
              },
              tooltip: 'Compare Timetables',
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onSecondaryContainer,
              heroTag: "compare",
              child: const Icon(Icons.compare),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),
            Semantics(
              label: 'Create Timetable',
              button: true,
              child: FloatingActionButton.extended(
                onPressed: _createNewTimetable,
                icon: const Icon(Icons.add),
                label: const Text('New Timetable'),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                heroTag: "add",
              ),
            ),
          ],
        ),
        desktop: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              onPressed: _importFromShareCode,
              icon: const Icon(Icons.download),
              label: const Text('Import Code'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              heroTag: "import_code",
            ),
            const SizedBox(width: 12),
            FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  FadeSlidePageRoute(page: const TimetableComparisonScreen()),
                );
              },
              icon: const Icon(Icons.compare),
              label: const Text('Compare'),
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onSecondaryContainer,
              heroTag: "compare",
            ),
            const SizedBox(width: AppDesign.spacingMd),
            Semantics(
              label: 'Create Timetable',
              button: true,
              child: FloatingActionButton.extended(
                onPressed: _createNewTimetable,
                icon: const Icon(Icons.add),
                label: const Text('New Timetable'),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                heroTag: "add",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimetableEditorScreen extends StatefulWidget {
  final String timetableId;

  const TimetableEditorScreen({super.key, required this.timetableId});

  @override
  State<TimetableEditorScreen> createState() => _TimetableEditorScreenState();
}

class _TimetableEditorScreenState extends State<TimetableEditorScreen> {
  final TimetableService _timetableService = TimetableService();
  Timetable? _timetable;
  bool _isLoading = true;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadTimetable();
  }

  Future<void> _loadTimetable() async {
    try {
      final timetable = await _timetableService.getTimetableById(
        widget.timetableId,
      );
      if (timetable != null) {
        setState(() {
          _timetable = timetable;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          Navigator.pop(context);
          ToastService.showError('Timetable not found');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ToastService.showError('Error loading timetable: $e');
      }
    }
  }

  void _onUnsavedChangesChanged(bool hasChanges) {
    setState(() {
      _hasUnsavedChanges = hasChanges;
    });
  }

  Future<bool> _showUnsavedChangesDialog() async {
    return await AppDialog.confirm(
      context: context,
      title: 'Unsaved Changes',
      message: 'You have unsaved changes that will be lost. Are you sure you want to go back?',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
      isDangerous: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: TimetableListSkeleton());
    }

    if (_timetable == null) {
      return Scaffold(
        body: EmptyStateWidget(
          icon: Icons.search_off,
          title: 'Timetable not found',
          subtitle: 'It may have been deleted or moved.',
          actionLabel: 'Go Back',
          actionIcon: Icons.arrow_back,
          onAction: () => Navigator.of(context).pop(),
        ),
      );
    }

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // Only show dialog if there are actual unsaved changes
        if (_hasUnsavedChanges) {
          final navigator = Navigator.of(context);
          final shouldPop = await _showUnsavedChangesDialog();
          if (shouldPop && navigator.canPop()) {
            navigator.pop();
          }
        }
      },
      child: TimetableHomeScreen(
        timetable: _timetable!,
        onUnsavedChangesChanged: _onUnsavedChangesChanged,
      ),
    );
  }
}

class TimetableHomeScreen extends StatefulWidget {
  final Timetable timetable;
  final Function(bool)? onUnsavedChangesChanged;

  const TimetableHomeScreen({
    super.key,
    required this.timetable,
    this.onUnsavedChangesChanged,
  });

  @override
  State<TimetableHomeScreen> createState() => _TimetableHomeScreenState();
}

class _TimetableHomeScreenState extends State<TimetableHomeScreen> {
  late Timetable _timetable;

  @override
  void initState() {
    super.initState();
    _timetable = widget.timetable;
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreenWithTimetable(
      timetable: _timetable,
      onUnsavedChangesChanged: widget.onUnsavedChangesChanged,
    );
  }
}
