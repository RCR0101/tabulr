import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../services/core/timetable_service.dart';
import '../services/ui/toast_service.dart';
import '../services/ui/secure_logger.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/common/empty_state_widget.dart';
import '../widgets/common/app_dialog.dart';
import 'home_screen.dart';

class TimetableEditorScreen extends StatefulWidget {
  final String timetableId;
  final Timetable? initialTimetable;

  const TimetableEditorScreen({
    super.key,
    required this.timetableId,
    this.initialTimetable,
  });

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
    if (widget.initialTimetable != null) {
      _timetable = widget.initialTimetable;
      _isLoading = false;
      _refreshCoursesInBackground();
    } else {
      _loadTimetable();
    }
  }

  Future<void> _refreshCoursesInBackground() async {
    try {
      final fresh = await _timetableService.getTimetableById(widget.timetableId);
      if (fresh != null && mounted) {
        setState(() => _timetable = fresh);
      }
    } catch (e) {
      SecureLogger.warning('TIMETABLES', 'Background course refresh failed', {'error': e.toString()});
    }
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
      child: HomeScreenWithTimetable(
        timetable: _timetable!,
        onUnsavedChangesChanged: _onUnsavedChangesChanged,
      ),
    );
  }
}
