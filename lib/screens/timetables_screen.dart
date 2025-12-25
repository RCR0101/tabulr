import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../services/campus_service.dart';
import '../services/course_data_service.dart';
import '../services/user_settings_service.dart';
import '../services/responsive_service.dart';
import '../models/user_settings.dart';
import '../widgets/theme_selector_widget.dart';
import '../widgets/campus_selector_widget.dart';
import 'home_screen.dart';
import 'course_guide_screen.dart';
import 'timetable_comparison_screen.dart';
import 'humanities_electives_screen.dart';
import 'discipline_electives_screen.dart';
import 'professors_screen.dart';
import 'prerequisites_screen.dart';
import 'cgpa_calculator_screen.dart';
import 'acad_drives_screen.dart';

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
    // Initialize user settings first
    await _userSettingsService.initializeSettings();
    // Then load timetables
    await _loadTimetables();
  }

  @override
  void dispose() {
    _userSettingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
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

  Future<String?> _showCreateTimetableDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create New Timetable'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Timetable Name',
                hintText: 'Enter a name for your timetable',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  Future<void> _renameTimetable(Timetable timetable) async {
    final controller = TextEditingController(text: timetable.name);
    final newName = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename Timetable'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Timetable Name'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text('Rename'),
              ),
            ],
          ),
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
    final controller = TextEditingController(text: '${timetable.name} (Copy)');
    final newName = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Duplicate Timetable'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'New Timetable Name'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text('Duplicate'),
              ),
            ],
          ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Timetable'),
            content: Text(
              'Are you sure you want to delete "${timetable.name}"? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
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
      MaterialPageRoute(
        builder: (context) => TimetableEditorScreen(timetableId: timetable.id),
      ),
    ).then((result) {
      // Only refresh if there were changes (optional optimization)
      // For now, we'll keep the refresh but consider reducing frequency
      if (result != null) {
        _loadTimetables();
      }
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                const Text('Clear All Timetables'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete all ${_sortedTimetables.length} timetables?',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'This action cannot be undone.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _clearAllTimetables();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Clear All'),
              ),
            ],
          ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All timetables have been cleared'),
            backgroundColor: Colors.green,
          ),
        );
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
    print('Applying sort: $sortOrder, timetables count: ${_timetables.length}');

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
    print('Current sort order: $currentSort');

    if (!mounted) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.sort,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Sort Timetables'),
              ],
            ),
            content: Container(
              width: ResponsiveService.getValue(
                context,
                mobile: MediaQuery.of(context).size.width * 0.9,
                tablet: 400,
                desktop: 480,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: ResponsiveService.getValue(
                      context,
                      mobile: 8,
                      tablet: 8,
                      desktop: 8,
                    ),
                    runSpacing: ResponsiveService.getValue(
                      context,
                      mobile: 8,
                      tablet: 8,
                      desktop: 8,
                    ),
                    alignment: WrapAlignment.spaceEvenly,
                    children:
                        TimetableListSortOrder.values.map((sortOrder) {
                          final isSelected = currentSort == sortOrder;
                          return SizedBox(
                            width: ResponsiveService.getValue(
                              context,
                              mobile:
                                  (MediaQuery.of(context).size.width * 0.9 -
                                      24) /
                                  2,
                              tablet: 180,
                              desktop: 220,
                            ),
                            child: Material(
                              color:
                                  isSelected
                                      ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  print('Sort option tapped: $sortOrder');
                                  final navigator = Navigator.of(context);
                                  try {
                                    await _userSettingsService.updateSortOrder(
                                      sortOrder,
                                    );
                                    navigator.pop();
                                  } catch (e) {
                                    print('Error updating sort order: $e');
                                  }
                                },
                                child: Container(
                                  constraints: BoxConstraints(
                                    minHeight:
                                        ResponsiveService.getTouchTargetSize(
                                          context,
                                        ),
                                  ),
                                  padding: ResponsiveService.getAdaptivePadding(
                                    context,
                                    EdgeInsets.all(
                                      ResponsiveService.isMobile(context)
                                          ? 8
                                          : 12,
                                    ),
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .outline
                                                  .withOpacity(0.3),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(
                                          ResponsiveService.isMobile(context)
                                              ? 8
                                              : 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              isSelected
                                                  ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          _getSortIcon(sortOrder),
                                          size:
                                              ResponsiveService.isMobile(
                                                    context,
                                                  )
                                                  ? 18
                                                  : 18,
                                          color:
                                              isSelected
                                                  ? Theme.of(
                                                    context,
                                                  ).colorScheme.onPrimary
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                        ),
                                      ),
                                      SizedBox(
                                        height:
                                            ResponsiveService.isMobile(context)
                                                ? 6
                                                : 8,
                                      ),
                                      Text(
                                        _getSortOrderName(sortOrder),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight:
                                              isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                          fontSize:
                                              ResponsiveService.isMobile(
                                                    context,
                                                  )
                                                  ? 10
                                                  : 12,
                                          color:
                                              isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onPrimaryContainer
                                                  : Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(height: 4),
                                        Icon(
                                          Icons.check_circle,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                          size:
                                              ResponsiveService.isMobile(
                                                    context,
                                                  )
                                                  ? 14
                                                  : 16,
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
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
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

  String _getSortOrderDescription(TimetableListSortOrder sortOrder) {
    switch (sortOrder) {
      case TimetableListSortOrder.dateCreatedAsc:
      case TimetableListSortOrder.dateCreatedDesc:
        return 'Sort by creation date';
      case TimetableListSortOrder.dateModifiedAsc:
      case TimetableListSortOrder.dateModifiedDesc:
        return 'Sort by last modification';
      case TimetableListSortOrder.alphabeticalAsc:
      case TimetableListSortOrder.alphabeticalDesc:
        return 'Sort alphabetically by name';
      case TimetableListSortOrder.custom:
        return 'Drag to reorder manually';
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
    // Replace with your GitHub repository URL
    const String githubUrl = 'https://github.com/RCR0101/timetable_maker';

    try {
      // For web, open in new tab
      if (kIsWeb) {
        html.window.open(githubUrl, '_blank');
      } else {
        // For mobile, you'd need url_launcher package
        // await launchUrl(Uri.parse(githubUrl));
        print('Open GitHub: $githubUrl');
      }
    } catch (e) {
      print('Error opening GitHub: $e');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _authService.signOut();
        // Navigation will be handled by AuthWrapper
      } catch (e) {
        _showErrorDialog('Error signing out: $e');
      }
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(24),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.school,
                      size: ResponsiveService.getAdaptiveIconSize(context, 32),
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  SizedBox(
                    height: ResponsiveService.getAdaptiveSpacing(context, 12),
                  ),
                  Text(
                    'Tabulr',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: ListView(
                padding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(vertical: 16),
                ),
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.schedule,
                      color: Theme.of(context).colorScheme.primary,
                      size: ResponsiveService.getAdaptiveIconSize(
                        context,
                        24,
                      ),
                    ),
                    tileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    title: Text(
                      'TT Builder',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: ResponsiveService.getAdaptiveFontSize(
                          context,
                          16,
                        ),
                      ),
                    ),
                    subtitle: Text(
                      'Create timetables',
                      style: TextStyle(
                        fontSize: ResponsiveService.getAdaptiveFontSize(
                          context,
                          12,
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    trailing: null,
                    onTap: () {
                      Navigator.pop(context);
                      // Already on timetables screen, just close drawer
                    },
                  ),

                  const Divider(),

                  // Show CGPA Calculator only if user is signed in
                  if (_authService.isAuthenticated)
                    ListTile(
                      leading: Icon(
                        Icons.calculate,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: ResponsiveService.getAdaptiveIconSize(
                          context,
                          24,
                        ),
                      ),
                      title: Text(
                        'CGPA Calculator',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: ResponsiveService.getAdaptiveFontSize(
                            context,
                            16,
                          ),
                        ),
                      ),
                      subtitle: Text(
                        'Track your academic performance',
                        style: TextStyle(
                          fontSize: ResponsiveService.getAdaptiveFontSize(
                            context,
                            12,
                          ),
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      trailing: null,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CGPACalculatorScreen(),
                          ),
                        );
                      },
                    ),
                  if (_authService.isAuthenticated)
                    ListTile(
                      leading: Icon(
                        Icons.folder_shared,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: ResponsiveService.getAdaptiveIconSize(
                          context,
                          24,
                        ),
                      ),
                      title: Text(
                        'Academic Drives',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: ResponsiveService.getAdaptiveFontSize(
                            context,
                            16,
                          ),
                        ),
                      ),
                      subtitle: Text(
                        'Browse & share academic resources',
                        style: TextStyle(
                          fontSize: ResponsiveService.getAdaptiveFontSize(
                            context,
                            12,
                          ),
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      trailing: null,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AcadDrivesScreen(),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(16),
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: ResponsiveService.getAdaptiveIconSize(context, 16),
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  SizedBox(
                    width: ResponsiveService.getAdaptiveSpacing(context, 8),
                  ),
                  Expanded(
                    child: Text(
                      'Made with ❤️ for students',
                      style: TextStyle(
                        fontSize: ResponsiveService.getAdaptiveFontSize(
                          context,
                          12,
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      drawer: _buildDrawer(),
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
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'images/full_logo_bg.png',
                          height: 50,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.sort,
              size: ResponsiveService.getAdaptiveIconSize(context, 24),
            ),
            onPressed: _showSortDialog,
            tooltip: 'Sort Timetables',
            iconSize: ResponsiveService.getValue(
              context,
              mobile: 40.0,
              tablet: 48.0,
              desktop: 48.0,
            ),
            padding: ResponsiveService.getAdaptivePadding(
              context,
              EdgeInsets.all(
                ResponsiveService.getValue(
                  context,
                  mobile: 8.0,
                  tablet: 8.0,
                  desktop: 8.0,
                ),
              ),
            ),
          ),
          if (!ResponsiveService.isMobile(context))
            CampusSelectorWidget(
              onCampusChanged: (campus) {
                // Clear course cache when campus changes
                CourseDataService().clearCache();
                ToastService.showInfo(
                  'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
                );
              },
            ),
          SizedBox(
            width: ResponsiveService.getValue(
              context,
              mobile: 4,
              tablet: 8,
              desktop: 8,
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.apps,
              size: ResponsiveService.getAdaptiveIconSize(context, 24),
            ),
            tooltip: 'More Options',
            iconSize: ResponsiveService.getValue(
              context,
              mobile: 40.0,
              tablet: 48.0,
              desktop: 48.0,
            ),
            padding: ResponsiveService.getAdaptivePadding(
              context,
              EdgeInsets.all(
                ResponsiveService.getValue(
                  context,
                  mobile: 8.0,
                  tablet: 8.0,
                  desktop: 8.0,
                ),
              ),
            ),
            onSelected: (value) {
              switch (value) {
                case 'course_guide':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CourseGuideScreen(),
                    ),
                  );
                  break;
                case 'prerequisites':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PrerequisitesScreen(),
                    ),
                  );
                  break;
                case 'professors':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfessorsScreen(),
                    ),
                  );
                  break;
                case 'discipline_electives':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DisciplineElectivesScreen(),
                    ),
                  );
                  break;
                case 'humanities_electives':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HumanitiesElectivesScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  // Campus selector for mobile
                  if (ResponsiveService.isMobile(context))
                    PopupMenuItem(
                      enabled: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Campus',
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            CampusSelectorWidget(
                              onCampusChanged: (campus) {
                                Navigator.pop(context);
                                CourseDataService().clearCache();
                                ToastService.showInfo(
                                  'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (ResponsiveService.isMobile(context))
                    const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'course_guide',
                    child: ListTile(
                      leading: Icon(Icons.menu_book),
                      title: Text('Course Guide'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'prerequisites',
                    child: ListTile(
                      leading: Icon(Icons.account_tree),
                      title: Text('Prerequisites'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'professors',
                    child: ListTile(
                      leading: Icon(Icons.person),
                      title: Text('Professors'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'discipline_electives',
                    child: ListTile(
                      leading: Icon(Icons.school),
                      title: Text('Discipline Electives'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'humanities_electives',
                    child: ListTile(
                      leading: Icon(Icons.library_books),
                      title: Text('Humanities Electives'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
          ),
          const ThemeToggleButton(),
          IconButton(
            icon: Icon(
              Icons.star_border,
              size: ResponsiveService.getAdaptiveIconSize(context, 24),
            ),
            onPressed: () => _openGitHub(),
            tooltip: 'Star on GitHub',
            iconSize: ResponsiveService.getTouchTargetSize(context),
            padding: EdgeInsets.all(
              ResponsiveService.getValue(
                context,
                mobile: 12.0,
                tablet: 8.0,
                desktop: 8.0,
              ),
            ),
          ),
          // User info and logout
          if (_authService.isAuthenticated)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  _logout();
                }
              },
              itemBuilder:
                  (context) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _authService.userName ?? 'User',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _authService.userEmail ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.logout),
                        title: Text('Sign Out'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage:
                          _authService.userPhotoUrl != null
                              ? NetworkImage(_authService.userPhotoUrl!)
                              : null,
                      child:
                          _authService.userPhotoUrl == null
                              ? const Icon(Icons.person, size: 16)
                              : null,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  _logout();
                }
              },
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(
                      enabled: false,
                      child: ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('Guest User'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.logout),
                        title: Text('Sign Out'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          SizedBox(
            width: ResponsiveService.getValue(
              context,
              mobile: 4,
              tablet: 8,
              desktop: 8,
            ),
          ),
        ],
      ),
      body:
          _sortedTimetables.isEmpty
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 8),
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
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sortedTimetables.length,
                      onReorder: _onReorder,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, index) {
                        final timetable = _sortedTimetables[index];
                        final isCustomSort =
                            _userSettingsService.sortOrder ==
                            TimetableListSortOrder.custom;
                        return Card(
                          key: ValueKey(timetable.id),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCustomSort)
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(
                                      Icons.drag_handle,
                                      color: Colors.grey,
                                    ),
                                  )
                                else
                                  Icon(
                                    _getSortIcon(
                                      _userSettingsService.sortOrder,
                                    ),
                                    color: Colors.grey,
                                  ),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    timetable.name.isNotEmpty
                                        ? timetable.name[0].toUpperCase()
                                        : 'T',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              timetable.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${timetable.selectedSections.map((s) => s.courseCode).toSet().length} courses selected',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Created: ${_formatDate(timetable.createdAt)}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
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
                              itemBuilder:
                                  (context) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: ListTile(
                                        leading: Icon(Icons.edit),
                                        title: Text('Rename'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'duplicate',
                                      child: ListTile(
                                        leading: Icon(Icons.copy),
                                        title: Text('Duplicate'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    if (_sortedTimetables.length > 1)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          title: Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                  ],
                            ),
                            onTap: () => _openTimetable(timetable),
                          ),
                        );
                      },
                    ),
                  ),
                  // Clear All button at bottom
                  if (_sortedTimetables.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Disclaimer: This software may make mistakes or suggest classes you might not be eligible for. Please double-check all course selections with your academic advisor.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ResponsiveService.buildResponsive(
        context,
        mobile: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TimetableComparisonScreen(),
                  ),
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
            FloatingActionButton.extended(
              onPressed: _createNewTimetable,
              icon: const Icon(Icons.add),
              label: const Text('New Timetable'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              heroTag: "add",
            ),
          ],
        ),
        desktop: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TimetableComparisonScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.compare),
              label: const Text('Compare'),
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onSecondaryContainer,
              heroTag: "compare",
            ),
            const SizedBox(width: 16),
            FloatingActionButton.extended(
              onPressed: _createNewTimetable,
              icon: const Icon(Icons.add),
              label: const Text('New Timetable'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              heroTag: "add",
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
      print('Loading timetable with ID: ${widget.timetableId}');
      final timetable = await _timetableService.getTimetableById(
        widget.timetableId,
      );
      if (timetable != null) {
        print('Timetable loaded successfully: ${timetable.name}');
        setState(() {
          _timetable = timetable;
          _isLoading = false;
        });
      } else {
        print('Timetable not found, going back');
        if (mounted) {
          Navigator.pop(context);
          ToastService.showError('Timetable not found');
        }
      }
    } catch (e) {
      print('Error loading timetable: $e');
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
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Unsaved Changes'),
                content: const Text(
                  'You have unsaved changes that will be lost. Are you sure you want to go back?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Stay'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Leave'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_timetable == null) {
      return const Scaffold(body: Center(child: Text('Timetable not found')));
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
