import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../services/campus_service.dart';
import '../services/course_data_service.dart';
import '../widgets/theme_selector_widget.dart';
import '../widgets/campus_selector_widget.dart';
import 'home_screen.dart';
import 'course_guide_screen.dart';
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
  List<Timetable> _timetables = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimetables();
  }

  Future<void> _loadTimetables() async {
    try {
      final timetables = await _timetableService.getAllTimetables();
      setState(() {
        _timetables = timetables;
        _isLoading = false;
      });
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
      } catch (e) {
        _showErrorDialog('Error renaming timetable: $e');
      }
    }
  }

  Future<void> _deleteTimetable(Timetable timetable) async {
    if (_timetables.length <= 1) {
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
      } catch (e) {
        _showErrorDialog('Error deleting timetable: $e');
      }
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _timetables.removeAt(oldIndex);
      _timetables.insert(newIndex, item);
    });
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
      body:
          _timetables.isEmpty
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
              : ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _timetables.length,
                onReorder: _onReorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final timetable = _timetables[index];
                  return Card(
                    key: ValueKey(timetable.id),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(
                              Icons.drag_handle,
                              color: Colors.grey,
                            ),
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
                              if (_timetables.length > 1)
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewTimetable,
        icon: const Icon(Icons.add),
        label: const Text('New Timetable'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
