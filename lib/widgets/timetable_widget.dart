import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../models/export_options.dart';
import '../models/timetable_display.dart';
import '../services/ui/responsive_service.dart';
import 'common/first_that_fits.dart';
import '../screens/quick_replace_screen.dart';
import '../utils/datetime_utils.dart';
import '../utils/page_transitions.dart';
import 'timetable/course_palette.dart';
import 'timetable/timetable_agenda.dart';
import 'timetable/timetable_blocks.dart';
import 'timetable/timetable_grid.dart';

export '../models/timetable_display.dart';

class TimetableWidget extends StatefulWidget {
  final List<TimetableSlot> timetableSlots;
  final List<String> incompleteSelectionWarnings;
  final VoidCallback? onClear;
  final Function(String courseCode, String sectionId)? onRemoveSection;
  final TimetableSize size;
  final Function(TimetableSize)? onSizeChanged;
  final TimetableLayout layout;
  final Function(TimetableLayout)? onLayoutChanged;
  final bool isForExport;
  final GlobalKey? tableKey;
  final bool hasUnsavedChanges;
  final bool isSaving;
  final VoidCallback? onSave;
  final VoidCallback? onAutoLoadCDCs;
  final ExportOptions? exportOptions;
  final List<Course>? availableCourses;
  final List<SelectedSection>? selectedSections;
  final Function(Course selectedCourse, Course replacementCourse)? onQuickReplace;
  final Function(List<SelectedSection> newSections)? onSectionShuffle;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onShowStats;

  const TimetableWidget({
    super.key,
    required this.timetableSlots,
    this.incompleteSelectionWarnings = const [],
    this.onClear,
    this.onRemoveSection,
    this.size = TimetableSize.medium,
    this.onSizeChanged,
    this.layout = TimetableLayout.vertical,
    this.onLayoutChanged,
    this.isForExport = false,
    this.tableKey,
    this.hasUnsavedChanges = false,
    this.isSaving = false,
    this.onSave,
    this.onAutoLoadCDCs,
    this.exportOptions,
    this.availableCourses,
    this.selectedSections,
    this.onQuickReplace,
    this.onSectionShuffle,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.onShowStats,
  });

  @override
  State<TimetableWidget> createState() => _TimetableWidgetState();
}

class _TimetableWidgetState extends State<TimetableWidget> {
  /// The grid crops to the hours and days that actually hold classes; this
  /// restores the full Monday–Saturday, 8 AM–7:50 PM week.
  bool _showAllHours = false;

  /// Remembered so the Fit button can toggle back to whatever density the user
  /// had chosen rather than to a hardcoded default.
  TimetableSize _lastFixedSize = TimetableSize.medium;

  @override
  void initState() {
    super.initState();
    if (widget.size != TimetableSize.fit) _lastFixedSize = widget.size;
  }

  @override
  void didUpdateWidget(TimetableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.size != TimetableSize.fit) _lastFixedSize = widget.size;
  }

  bool get _isMobile {
    if (widget.isForExport) return false;
    return ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);
  }

  bool get _canShowQuickReplace {
    return !widget.isForExport &&
        widget.onQuickReplace != null &&
        widget.availableCourses != null &&
        widget.selectedSections != null &&
        widget.selectedSections!.isNotEmpty;
  }

  /// Agenda has no rows or columns to size, so the density and hour controls
  /// are hidden rather than left inert.
  bool get _isAgenda =>
      widget.layout == TimetableLayout.agenda && !widget.isForExport;

  /// Export renders every field unless the export dialog says otherwise.
  Set<TimetableField> get _visibleFields {
    final options = widget.exportOptions;
    if (options == null) return TimetableField.values.toSet();
    return {
      if (options.showCourseCode) TimetableField.courseCode,
      if (options.showCourseTitle) TimetableField.courseTitle,
      if (options.showSectionId) TimetableField.sectionId,
      if (options.showInstructor) TimetableField.instructor,
      if (options.showRoom) TimetableField.room,
    };
  }

  /// Course codes in selection order — the order [CoursePalette] assigns
  /// accents in, so a course keeps its colour as others are added.
  Iterable<String> get _courseCodesInOrder {
    final seen = <String>[];
    for (final slot in widget.timetableSlots) {
      if (!seen.contains(slot.courseCode)) seen.add(slot.courseCode);
    }
    return seen;
  }

  void _showQuickReplaceDialog() {
    if (!_canShowQuickReplace) return;
    Navigator.push(
      context,
      FadeSlidePageRoute(
        page: QuickReplaceScreen(
          availableCourses: widget.availableCourses!,
          selectedSections: widget.selectedSections!,
          onReplace: widget.onQuickReplace!,
          onSectionShuffle: widget.onSectionShuffle,
        ),
      ),
    );
  }

  void _toggleFit() {
    final onSizeChanged = widget.onSizeChanged;
    if (onSizeChanged == null) return;
    ResponsiveService.triggerSelectionFeedback(context);
    onSizeChanged(
      widget.size == TimetableSize.fit ? _lastFixedSize : TimetableSize.fit,
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────

  /// Density, plus the "show all hours" escape hatch. Fit is listed first
  /// because seeing the whole week at once is the common request.
  Widget _buildDensityMenu(BuildContext context, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final sizes = _isMobile
        ? const [TimetableSize.fit, TimetableSize.compact, TimetableSize.medium]
        : TimetableSize.values;

    return PopupMenuButton<String>(
      enabled: widget.onSizeChanged != null,
      tooltip: 'Row density',
      onSelected: (value) {
        if (value == '_all_hours') {
          setState(() => _showAllHours = !_showAllHours);
          return;
        }
        final size = TimetableSize.values.firstWhere((s) => s.name == value);
        ResponsiveService.triggerSelectionFeedback(context);
        widget.onSizeChanged?.call(size);
      },
      itemBuilder: (context) => [
        for (final size in sizes)
          PopupMenuItem(
            value: size.name,
            height: ResponsiveService.getTouchTargetSize(context),
            child: Row(
              children: [
                Icon(
                  _sizeIcon(size),
                  size: 16,
                  color: size == widget.size ? scheme.primary : null,
                ),
                const SizedBox(width: 10),
                Text(
                  size.label,
                  style: TextStyle(
                    color: size == widget.size ? scheme.primary : null,
                    fontWeight: size == widget.size ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '_all_hours',
          height: ResponsiveService.getTouchTargetSize(context),
          child: Row(
            children: [
              Icon(
                _showAllHours ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
              ),
              const SizedBox(width: 10),
              const Text('Show full week'),
            ],
          ),
        ),
      ],
      child: _toolbarChip(
        context,
        compact: compact,
        icon: _sizeIcon(widget.size),
        trailing: Icons.arrow_drop_down,
      ),
    );
  }

  Widget _buildLayoutMenu(BuildContext context, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    // Hours-as-columns needs twelve columns; on a phone that is unusable, so
    // the agenda takes its place there.
    final layouts = _isMobile
        ? const [TimetableLayout.vertical, TimetableLayout.agenda]
        : TimetableLayout.values;

    return PopupMenuButton<TimetableLayout>(
      enabled: widget.onLayoutChanged != null,
      tooltip: 'Layout',
      onSelected: (layout) {
        ResponsiveService.triggerSelectionFeedback(context);
        widget.onLayoutChanged?.call(layout);
      },
      itemBuilder: (context) => [
        for (final layout in layouts)
          PopupMenuItem(
            value: layout,
            height: ResponsiveService.getTouchTargetSize(context),
            child: Row(
              children: [
                Icon(
                  _layoutIcon(layout),
                  size: 16,
                  color: layout == widget.layout ? scheme.primary : null,
                ),
                const SizedBox(width: 10),
                Text(
                  layout.label,
                  style: TextStyle(
                    color: layout == widget.layout ? scheme.primary : null,
                    fontWeight: layout == widget.layout ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: _toolbarChip(
        context,
        compact: compact,
        icon: _layoutIcon(widget.layout),
        trailing: Icons.arrow_drop_down,
      ),
    );
  }

  Widget _toolbarChip(
    BuildContext context, {
    required bool compact,
    required IconData icon,
    IconData? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(
        minHeight: ResponsiveService.getTouchTargetSize(context),
        minWidth: ResponsiveService.getTouchTargetSize(context),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
          ],
        ],
      ),
    );
  }

  /// The direct replacement for the old floating zoom stack: one button that
  /// puts the entire grid on screen and toggles back.
  Widget _buildFitButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFit = widget.size == TimetableSize.fit;
    return IconButton(
      onPressed: widget.onSizeChanged == null ? null : _toggleFit,
      icon: Icon(
        isFit ? Icons.close_fullscreen : Icons.fit_screen,
        size: ResponsiveService.getAdaptiveIconSize(context, 18),
      ),
      tooltip: isFit ? 'Back to ${_lastFixedSize.label}' : 'Fit whole week on screen',
      style: IconButton.styleFrom(
        backgroundColor: isFit ? scheme.primary.withValues(alpha: 0.12) : null,
        foregroundColor: isFit ? scheme.primary : null,
        side: BorderSide(
          color: isFit
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outline.withValues(alpha: 0.3),
        ),
        minimumSize: Size(
          ResponsiveService.getTouchTargetSize(context),
          ResponsiveService.getTouchTargetSize(context),
        ),
      ),
    );
  }

  static IconData _sizeIcon(TimetableSize size) => switch (size) {
    TimetableSize.compact => Icons.view_compact,
    TimetableSize.medium => Icons.view_module,
    TimetableSize.large => Icons.view_comfortable,
    TimetableSize.extraLarge => Icons.view_agenda,
    TimetableSize.fit => Icons.fit_screen,
  };

  static IconData _layoutIcon(TimetableLayout layout) => switch (layout) {
    TimetableLayout.vertical => Icons.calendar_view_week,
    TimetableLayout.horizontal => Icons.view_stream,
    TimetableLayout.agenda => Icons.view_list,
  };

  Widget _buildMobileSaveButton() {
    if (widget.isForExport || widget.onSave == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.hasUnsavedChanges && !widget.isSaving
              ? () {
                  ResponsiveService.triggerMediumFeedback(context);
                  widget.onSave!();
                }
              : null,
          icon: widget.isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(widget.hasUnsavedChanges ? Icons.save : Icons.check, size: 14),
          label: Text(
            widget.isSaving
                ? 'Saving...'
                : widget.hasUnsavedChanges
                    ? 'Save'
                    : 'Saved',
            style: const TextStyle(fontSize: 12),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: (widget.hasUnsavedChanges
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.tertiary)
                .withValues(alpha: 0.1),
            foregroundColor: widget.hasUnsavedChanges
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.tertiary,
            side: BorderSide(
              color: (widget.hasUnsavedChanges
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.tertiary)
                  .withValues(alpha: 0.3),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  /// Actions that collapse into a single button when the toolbar runs out of
  /// room. Used on mobile always, and on desktop whenever the timetable panel
  /// is narrower than the full set of labelled buttons needs.
  Widget _buildOverflowMenu() {
    if (widget.isForExport) return const SizedBox.shrink();
    final hasAutoLoad = widget.onAutoLoadCDCs != null;
    final hasReplace = _canShowQuickReplace;
    final hasClear = widget.timetableSlots.isNotEmpty && widget.onClear != null;
    final hasStats = widget.onShowStats != null && widget.timetableSlots.isNotEmpty;
    if (!hasAutoLoad && !hasReplace && !hasClear && !hasStats) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Timetable actions',
      onSelected: (value) {
        switch (value) {
          case 'auto_load':
            ResponsiveService.triggerLightFeedback(context);
            widget.onAutoLoadCDCs?.call();
            break;
          case 'replace':
            _showQuickReplaceDialog();
            break;
          case 'clear':
            ResponsiveService.triggerHeavyFeedback(context);
            widget.onClear?.call();
            break;
          case 'stats':
            widget.onShowStats?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (hasAutoLoad)
          const PopupMenuItem(
            value: 'auto_load',
            child: ListTile(
              leading: Icon(Icons.school),
              title: Text('Auto Load CDCs'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (hasReplace)
          const PopupMenuItem(
            value: 'replace',
            child: ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('Quick Replace'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (hasStats)
          const PopupMenuItem(
            value: 'stats',
            child: ListTile(
              leading: Icon(Icons.insights),
              title: Text('TT Stats'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (hasClear)
          PopupMenuItem(
            value: 'clear',
            child: ListTile(
              leading: Icon(Icons.clear_all, color: scheme.error),
              title: Text('Clear Timetable', style: TextStyle(color: scheme.error)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  /// The toolbar collapses in stages as the panel narrows. Which stage is used
  /// is decided by measuring the candidates rather than by hardcoded widths:
  /// the timetable panel is two thirds of the body, so a 1440 px window leaves
  /// it roughly 760 px, and the exact budget shifts with text scale, labels and
  /// which callbacks the caller wired up.
  Widget _buildAppBar() {
    if (widget.isForExport) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.all(_isMobile ? 6 : 8),
      child: _isMobile ? _buildMobileAppBar(context) : _buildDesktopAppBar(context),
    );
  }

  Widget _buildMobileAppBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _candidates([
          // Fit is the first thing to go: it is also the top entry of the
          // density menu, so nothing becomes unreachable.
          _mobileRow(showFit: true, showUndoRedo: true),
          _mobileRow(showFit: false, showUndoRedo: true),
          _mobileRow(showFit: false, showUndoRedo: false),
        ]),
        _buildMobileSaveButton(),
      ],
    );
  }

  /// Wraps each candidate in a keyed subtree. The key is what lets a test — or
  /// the widget inspector — tell which variant is actually on screen, since
  /// every candidate is built but only the chosen one is laid out.
  Widget _candidates(List<Widget> variants) {
    return FirstThatFits(
      candidates: [
        for (final (index, variant) in variants.indexed)
          KeyedSubtree(
            key: ValueKey('toolbar-variant-$index'),
            child: index == variants.length - 1
                // Last resort: scrolling beats an overflow stripe when even the
                // narrowest variant cannot fit.
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: variant,
                  )
                : variant,
          ),
      ],
    );
  }

  Widget _mobileRow({required bool showFit, required bool showUndoRedo}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onUndo != null && showUndoRedo) ...[
              IconButton(
                onPressed: widget.canUndo ? widget.onUndo : null,
                icon: const Icon(Icons.undo, size: 20),
                tooltip: 'Undo',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                onPressed: widget.canRedo ? widget.onRedo : null,
                icon: const Icon(Icons.redo, size: 20),
                tooltip: 'Redo',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isAgenda && showFit) ...[
              _buildFitButton(context),
              const SizedBox(width: 6),
            ],
            _buildLayoutMenu(context, compact: true),
            if (!_isAgenda) ...[
              const SizedBox(width: 6),
              _buildDensityMenu(context, compact: true),
            ],
            _buildOverflowMenu(),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopAppBar(BuildContext context) {
    return _candidates([
      _desktopRow(showTitle: true),
      _desktopRow(showTitle: false),
      _desktopRow(showTitle: false, expandActions: false),
      _desktopRow(showTitle: false, expandActions: false, compactChips: true),
      _desktopRow(
        showTitle: false,
        expandActions: false,
        compactChips: true,
        iconOnlySave: true,
      ),
      _desktopRow(
        showTitle: false,
        expandActions: false,
        compactChips: true,
        iconOnlySave: true,
        showUndoRedo: false,
      ),
    ]);
  }

  Widget _desktopRow({
    required bool showTitle,
    bool expandActions = true,
    bool compactChips = false,
    bool iconOnlySave = false,
    bool showUndoRedo = true,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      // Two groups rather than a Spacer, so the row's intrinsic width is just
      // the sum of its children and FirstThatFits can measure it.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTitle) ...[
              const Text(
                'Weekly Timetable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
            ],
            if (widget.onUndo != null && showUndoRedo) ...[
              IconButton(
                onPressed: widget.canUndo ? widget.onUndo : null,
                icon: Icon(Icons.undo, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                tooltip: 'Undo',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
              ),
              IconButton(
                onPressed: widget.canRedo ? widget.onRedo : null,
                icon: Icon(Icons.redo, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                tooltip: 'Redo',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
              ),
              const SizedBox(width: 12),
            ],
            if (!_isAgenda) ...[
              _buildFitButton(context),
              const SizedBox(width: 8),
            ],
            _buildLayoutMenu(context, compact: compactChips),
            if (!_isAgenda) ...[
              const SizedBox(width: 8),
              _buildDensityMenu(context, compact: compactChips),
            ],
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 16),
            if (expandActions && widget.onAutoLoadCDCs != null) ...[
              _toolbarAction(
                context,
                icon: Icons.school,
                label: 'Auto Load CDCs',
                color: scheme.secondary,
                onPressed: () {
                  ResponsiveService.triggerLightFeedback(context);
                  widget.onAutoLoadCDCs!();
                },
              ),
              const SizedBox(width: 8),
            ],
            // Save stays a button at every width: it is the only action whose
            // state is worth seeing without opening a menu.
            if (widget.onSave != null) ...[
              _toolbarAction(
                context,
                icon: widget.hasUnsavedChanges ? Icons.save : Icons.check,
                label: widget.isSaving
                    ? 'Saving...'
                    : widget.hasUnsavedChanges
                        ? 'Save'
                        : 'Saved',
                iconOnly: iconOnlySave,
                color: widget.hasUnsavedChanges ? scheme.primary : scheme.tertiary,
                isLoading: widget.isSaving,
                onPressed: widget.hasUnsavedChanges && !widget.isSaving
                    ? () {
                        ResponsiveService.triggerMediumFeedback(context);
                        widget.onSave!();
                      }
                    : null,
              ),
              const SizedBox(width: 8),
            ],
            if (expandActions) ...[
              if (_canShowQuickReplace) ...[
                _toolbarAction(
                  context,
                  icon: Icons.swap_horiz,
                  label: 'Quick Replace',
                  color: scheme.tertiary,
                  onPressed: _showQuickReplaceDialog,
                ),
                const SizedBox(width: 8),
              ],
              if (widget.onShowStats != null && widget.timetableSlots.isNotEmpty) ...[
                _toolbarAction(
                  context,
                  icon: Icons.insights,
                  label: 'TT Stats',
                  color: scheme.primary,
                  onPressed: widget.onShowStats!,
                ),
                const SizedBox(width: 8),
              ],
              if (widget.timetableSlots.isNotEmpty && widget.onClear != null)
                TextButton.icon(
                  onPressed: () {
                    ResponsiveService.triggerHeavyFeedback(context);
                    widget.onClear!();
                  },
                  icon: Icon(Icons.clear_all, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    minimumSize: Size(0, ResponsiveService.getTouchTargetSize(context)),
                  ),
                ),
            ] else
              _buildOverflowMenu(),
          ],
        ),
      ],
    );
  }

  Widget _toolbarAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool iconOnly = false,
  }) {
    final glyph = isLoading
        ? SizedBox(
            width: ResponsiveService.getAdaptiveIconSize(context, 16),
            height: ResponsiveService.getAdaptiveIconSize(context, 16),
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: ResponsiveService.getAdaptiveIconSize(context, 16));

    if (iconOnly) {
      return Tooltip(
        message: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.3)),
            elevation: 0,
            padding: EdgeInsets.zero,
            minimumSize: Size(
              ResponsiveService.getTouchTargetSize(context),
              ResponsiveService.getTouchTargetSize(context),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: glyph,
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: glyph,
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        elevation: 0,
        minimumSize: Size(0, ResponsiveService.getTouchTargetSize(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = CoursePalette.forCourses(context, _courseCodesInOrder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAppBar(),
        // On screen the grid fills the panel; for export it must size to its own
        // content so a long exam schedule is not clipped by the capture box.
        if (widget.isForExport)
          _buildExportSurface(context, palette)
        else
          Expanded(child: _buildScreenSurface(context, palette)),
      ],
    );
  }

  Widget _buildScreenSurface(BuildContext context, CoursePalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        // Deliberately faint: this sits inside the editor's Card, and a
        // full-strength outline a few pixels in from the card edge reads as a
        // mistake rather than as a frame.
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _isAgenda
          ? TimetableAgenda(
              slots: widget.timetableSlots,
              palette: palette,
              incompleteSelectionWarnings: widget.incompleteSelectionWarnings,
              onSlotTap: _showBlockDetail,
              onRemoveSection: widget.onRemoveSection,
            )
          : RepaintBoundary(
              key: widget.tableKey,
              child: TimetableGrid(
                slots: widget.timetableSlots,
                layout: widget.layout,
                size: widget.size,
                palette: palette,
                showAllHours: _showAllHours,
                visibleFields: _visibleFields,
                incompleteSelectionWarnings: widget.incompleteSelectionWarnings,
                onSlotTap: _showBlockDetail,
                onRemoveSection: widget.onRemoveSection,
              ),
            ),
    );
  }

  Widget _buildExportSurface(BuildContext context, CoursePalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: RepaintBoundary(
        key: widget.tableKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TimetableGrid(
                slots: widget.timetableSlots,
                // The agenda is a screen view; a captured PNG is always a grid.
                layout: widget.layout == TimetableLayout.agenda
                    ? TimetableLayout.vertical
                    : widget.layout,
                size: widget.size == TimetableSize.fit
                    ? TimetableSize.extraLarge
                    : widget.size,
                palette: palette,
                isForExport: true,
                // The PNG crops the same way the grid on screen does, so what
                // is shared matches what was designed. "Show full week" is a
                // viewing preference and does not reach this instance, which
                // the export builds fresh in an overlay.
                showAllHours: false,
                visibleFields: _visibleFields,
                incompleteSelectionWarnings: widget.incompleteSelectionWarnings,
              ),
            ),
            if (widget.exportOptions?.showExamDates == true)
              _buildExamDatesForExport(context, palette),
          ],
        ),
      ),
    );
  }

  // ── Detail sheet ──────────────────────────────────────────────────────────

  void _showBlockDetail(CourseBlock block) {
    final scheme = Theme.of(context).colorScheme;
    final palette = CoursePalette.forCourses(context, _courseCodesInOrder);
    final courseColor = palette.colorFor(block.slot.courseCode);

    // Every meeting of this section across the week, not just the one tapped.
    final meetings = <String>[];
    for (final slot in widget.timetableSlots) {
      if (slot.courseCode != block.slot.courseCode ||
          slot.sectionId != block.slot.sectionId) {
        continue;
      }
      final label =
          '${getDayName(slot.day, abbreviated: true)} ${TimeSlotInfo.getHourRangeName([...slot.hours])}';
      if (!meetings.contains(label)) meetings.add(label);
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: courseColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            block.slot.courseCode,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: courseColor,
                            ),
                          ),
                          Text(
                            block.slot.sectionId,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  block.slot.courseTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _detailRow(Icons.person_outline, block.slot.instructor, scheme),
                const SizedBox(height: 6),
                _detailRow(Icons.room_outlined, block.slot.room, scheme),
                const SizedBox(height: 6),
                _detailRow(Icons.schedule, meetings.join(', '), scheme),
                if (widget.onRemoveSection != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onRemoveSection!(
                          block.slot.courseCode,
                          block.slot.sectionId,
                        );
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Remove section'),
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, ColorScheme scheme) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  // ── Exam schedule (export only) ───────────────────────────────────────────

  Widget _buildExamDatesForExport(BuildContext context, CoursePalette palette) {
    final courses = widget.availableCourses ?? [];
    final sections = widget.selectedSections ?? [];
    if (courses.isEmpty || sections.isEmpty) return const SizedBox.shrink();

    final selectedCodes = sections.map((s) => s.courseCode).toSet();
    final examCourses = courses
        .where((c) =>
            selectedCodes.contains(c.courseCode) &&
            (c.midSemExam != null || c.endSemExam != null))
        .toList()
      ..sort((a, b) => a.courseCode.compareTo(b.courseCode));

    if (examCourses.isEmpty) return const SizedBox.shrink();

    String fmtDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    String fmtSlot(TimeSlot s) => s == TimeSlot.FN ? 'FN' : 'AN';

    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.3), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Exam Schedule',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Table(
            border: TableBorder.all(
              color: scheme.outline.withValues(alpha: 0.25),
              width: 1,
              borderRadius: BorderRadius.circular(8),
            ),
            columnWidths: const {
              0: FlexColumnWidth(2.5),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                children: [
                  for (final header in ['Course', 'Midsem', 'Compre'])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        header,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
              ...examCourses.map(
                (c) => TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.courseCode,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.colorFor(c.courseCode),
                            ),
                          ),
                          if (c.courseTitle.isNotEmpty)
                            Text(
                              c.courseTitle,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    _buildExamCell(context, c.midSemExam, fmtDate, fmtSlot, scheme.tertiary),
                    _buildExamCell(context, c.endSemExam, fmtDate, fmtSlot, scheme.error),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExamCell(
    BuildContext context,
    ExamSchedule? exam,
    String Function(DateTime) fmtDate,
    String Function(TimeSlot) fmtSlot,
    Color accent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (exam == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '—',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3), fontSize: 14),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              fmtDate(exam.date),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            fmtSlot(exam.timeSlot),
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
