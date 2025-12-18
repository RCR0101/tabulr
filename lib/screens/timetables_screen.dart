import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../services/campus_service.dart';
import '../services/course_data_service.dart';
import '../services/user_settings_service.dart';
import '../models/user_settings.dart';
import '../widgets/theme_selector_widget.dart';
import '../widgets/campus_selector_widget.dart';
import 'home_screen.dart';
import 'course_guide_screen.dart';
import 'timetable_comparison_screen.dart';
import 'humanities_electives_screen.dart';
import 'discipline_electives_screen.dart';

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
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning,
              color: Theme.of(context).colorScheme.error,
            ),
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
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
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
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case TimetableListSortOrder.alphabeticalDesc:
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
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
      builder: (context) => AlertDialog(
        title: const Text('Sort Timetables'),
        content: SizedBox(
          width: double.minPositive,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: TimetableListSortOrder.values.map((sortOrder) {
              final isSelected = currentSort == sortOrder;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(
                  _getSortOrderName(sortOrder),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                subtitle: Text(_getSortOrderDescription(sortOrder)),
                onTap: () async {
                  print('Sort option tapped: $sortOrder');
                  final navigator = Navigator.of(context);
                  try {
                    await _userSettingsService.updateSortOrder(sortOrder);
                    navigator.pop();
                  } catch (e) {
                    print('Error updating sort order: $e');
                  }
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
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
            icon: const Icon(Icons.sort),
            onPressed: _showSortDialog,
            tooltip: 'Sort Timetables',
          ),
          CampusSelectorWidget(
            onCampusChanged: (campus) {
              // Clear course cache when campus changes
              CourseDataService().clearCache();
              ToastService.showInfo(
                'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.menu_book),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CourseGuideScreen(),
                ),
              );
            },
            tooltip: 'Course Guide',
          ),
          IconButton(
            icon: const Icon(Icons.school),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DisciplineElectivesScreen(),
                ),
              );
            },
            tooltip: 'Discipline Electives',
          ),
          IconButton(
            icon: const Icon(Icons.library_books),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanitiesElectivesScreen(),
                ),
              );
            },
            tooltip: 'Humanities Electives',
          ),
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(Icons.star_border),
            onPressed: () => _openGitHub(),
            tooltip: 'Star on GitHub',
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
          const SizedBox(width: 8),
        ],
      ),
      body: _sortedTimetables.isEmpty
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
                  final isCustomSort = _userSettingsService.sortOrder == TimetableListSortOrder.custom;
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
                              _getSortIcon(_userSettingsService.sortOrder),
                              color: Colors.grey,
                            ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(
                              timetable.name.isNotEmpty
                                  ? timetable.name[0].toUpperCase()
                                  : 'T',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Created: ${_formatDate(timetable.createdAt)}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
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
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showClearAllDialog,
                            icon: Icon(
                              Icons.clear_all,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            label: Text(
                              'Clear All Timetables',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
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
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
      floatingActionButton: Row(
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
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            heroTag: "compare", // Required when multiple FABs are present
          ),
          const SizedBox(width: 16),
          FloatingActionButton.extended(
            onPressed: _createNewTimetable,
            icon: const Icon(Icons.add),
            label: const Text('New Timetable'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            heroTag: "add", // Required when multiple FABs are present
          ),
        ],
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
