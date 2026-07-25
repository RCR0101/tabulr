import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/academic_calendar_event.dart';
import '../services/data/academic_calendar_service.dart';
import '../services/data/campus_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/datetime_utils.dart';
import '../utils/design_constants.dart';
import 'common/app_tappable.dart';
import 'common/empty_state_widget.dart';
import 'common/shimmer_loading.dart';

/// Opens the campus academic calendar as a scrollable agenda — a bottom sheet
/// on phones, a dialog on wide screens. [campusId] defaults to the current
/// campus, so this works with no timetable selected.
Future<void> showAcademicCalendarSheet(
  BuildContext context, {
  String? campusId,
}) {
  final id = campusId ?? CampusService.campusId;

  if (ResponsiveService.isMobile(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) =>
            AcademicCalendarList(campusId: id, scrollController: controller),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: AcademicCalendarList(campusId: id),
      ),
    ),
  );
}

/// Loads a campus's academic calendar and hands it to [AcademicCalendarAgenda].
class AcademicCalendarList extends StatefulWidget {
  const AcademicCalendarList({
    super.key,
    required this.campusId,
    this.scrollController,
  });

  final String campusId;

  /// Supplied by [DraggableScrollableSheet] so the sheet drags with the list.
  final ScrollController? scrollController;

  @override
  State<AcademicCalendarList> createState() => _AcademicCalendarListState();
}

class _AcademicCalendarListState extends State<AcademicCalendarList> {
  List<AcademicCalendarEvent>? _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await AcademicCalendarService().load(campusId: widget.campusId);
    if (!mounted) return;
    setState(() => _events = events);
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AcademicCalendarHeader(campusId: widget.campusId),
        if (events == null)
          const Expanded(child: GenericListSkeleton(itemHeight: 72))
        else
          Expanded(
            child: AcademicCalendarAgenda(
              events: events,
              scrollController: widget.scrollController,
            ),
          ),
      ],
    );
  }
}

class _AcademicCalendarHeader extends StatelessWidget {
  const _AcademicCalendarHeader({required this.campusId});

  final String campusId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDesign.spacingMd, AppDesign.spacingMd, AppDesign.spacingSm, 0),
      child: Row(
        children: [
          Icon(Icons.event_note, size: AppDesign.iconSizeMd,
              color: theme.colorScheme.primary),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Academic Calendar',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  Campus.fromCode(campusId).displayName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: AppDesign.opacityMedium),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The academic calendar (holidays, deadlines, exam windows, term boundaries)
/// as a chronological list, upcoming first. The week grid only shows entries
/// for the week being looked at; this answers "when is the next holiday" and
/// "what have I got coming up" without navigating.
class AcademicCalendarAgenda extends StatefulWidget {
  const AcademicCalendarAgenda({
    super.key,
    required this.events,
    this.scrollController,
  });

  final List<AcademicCalendarEvent> events;
  final ScrollController? scrollController;

  @override
  State<AcademicCalendarAgenda> createState() => _AcademicCalendarAgendaState();
}

class _AcademicCalendarAgendaState extends State<AcademicCalendarAgenda> {
  final Set<AcademicEventCategory> _categories = {};
  bool _showPast = false;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Past means finished — a multi-day entry stays current until its last day.
  static bool _isPast(AcademicCalendarEvent e) {
    final end = e.endDate ?? e.date;
    return DateTime(end.year, end.month, end.day).isBefore(_today);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.event_note,
        title: 'No academic calendar yet',
        subtitle: 'Holidays and deadlines appear here once your campus '
            'calendar has been uploaded.',
      );
    }
    return _body(Theme.of(context), widget.events);
  }

  Widget _body(ThemeData theme, List<AcademicCalendarEvent> all) {
    final upcoming = [for (final e in all) if (!_isPast(e)) e];
    final past = [for (final e in all) if (_isPast(e)) e];

    final visible = [
      ...(_showPast ? past.reversed : const <AcademicCalendarEvent>[]),
      ...upcoming,
    ].where((e) => _categories.isEmpty || _categories.contains(e.category)).toList();

    final present = {for (final e in all) e.category}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, AppDesign.spacingSm,
          AppDesign.spacingMd, AppDesign.spacingLg),
      children: [
        _filters(theme, present, past.length),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingXl),
            child: Text(
              'Nothing matches those filters.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface
                    .withValues(alpha: AppDesign.opacityMedium),
              ),
            ),
          )
        else
          ..._grouped(theme, visible),
      ],
    );
  }

  Widget _filters(
      ThemeData theme, List<AcademicEventCategory> present, int pastCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: Wrap(
        spacing: AppDesign.spacingSm,
        runSpacing: AppDesign.spacingXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final c in present)
            FilterChip(
              label: Text(academicCategoryLabel(c)),
              labelStyle: theme.textTheme.labelMedium,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              showCheckmark: false,
              selectedColor: academicCategoryColor(context, c)
                  .withValues(alpha: 0.18),
              selected: _categories.contains(c),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (on) => setState(() {
                if (on) {
                  _categories.add(c);
                } else {
                  _categories.remove(c);
                }
              }),
            ),
          if (pastCount > 0)
            AppTappable(
              onTap: () => setState(() => _showPast = !_showPast),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.spacingSm, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_showPast ? Icons.visibility_off : Icons.history,
                        size: AppDesign.iconSizeSm,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: AppDesign.spacingXs),
                    Text(
                      _showPast ? 'Hide past' : 'Show past ($pastCount)',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Rows with a month heading wherever the month changes.
  List<Widget> _grouped(ThemeData theme, List<AcademicCalendarEvent> events) {
    final widgets = <Widget>[];
    int? month;
    int? year;

    for (final e in events) {
      if (e.date.month != month || e.date.year != year) {
        month = e.date.month;
        year = e.date.year;
        widgets.add(Padding(
          padding: EdgeInsets.only(
            top: widgets.isEmpty ? 0 : AppDesign.spacingMd,
            bottom: AppDesign.spacingSm,
          ),
          child: Row(
            children: [
              Text(
                '${monthAbbrev(month)} $year'.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: AppDesign.opacityMedium),
                ),
              ),
              const SizedBox(width: AppDesign.spacingSm),
              Expanded(
                child: Divider(
                  color: theme.colorScheme.outline
                      .withValues(alpha: AppDesign.opacityDivider),
                ),
              ),
            ],
          ),
        ));
      }

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
        child: _row(theme, e),
      ));
    }

    return widgets;
  }

  Widget _row(ThemeData theme, AcademicCalendarEvent e) {
    final scheme = theme.colorScheme;
    final accent = academicCategoryColor(context, e.category);
    final past = _isPast(e);
    final isNow = e.coversDay(_today);
    // Past entries are dimmed, never hidden behind unreadable opacity.
    final fade = past ? 0.7 : 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingMd, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: past ? 0.04 : 0.08),
        borderRadius: AppDesign.borderRadiusMd,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Text(
                  '${e.date.day}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent.withValues(alpha: fade),
                  ),
                ),
                Text(
                  DayConstants.weekDays[e.date.weekday - 1],
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: past ? 0.4 : 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesign.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: past ? 0.7 : 1),
                  ),
                ),
                const SizedBox(height: AppDesign.spacingXs),
                Wrap(
                  spacing: AppDesign.spacingSm,
                  runSpacing: AppDesign.spacingXxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill(theme, academicCategoryLabel(e.category), accent, fade),
                    if (e.isRange)
                      Text(
                        _dateSpan(e),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!past)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 84),
              child: Text(
                _relative(e),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
                  color: isNow
                      ? accent
                      : scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, String label, Color accent, double fade) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15 * fade),
        borderRadius: AppDesign.borderRadiusXs,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: accent.withValues(alpha: fade),
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }

  /// "14 Mar" or "14 Mar – 18 Mar".
  static String _dateSpan(AcademicCalendarEvent e) => e.isRange
      ? '${formatDayMonth(e.date)} – ${formatDayMonth(e.endDate!)}'
      : formatDayMonth(e.date);

  /// Plain-words countdown. Empty beyond a month out, where the date itself
  /// is the more useful thing to read.
  static String _relative(AcademicCalendarEvent e) {
    final today = _today;
    final start = DateTime(e.date.year, e.date.month, e.date.day);

    // A range that has already started reads "On now"; its end date is already
    // spelled out on the row's meta line.
    if (e.coversDay(today)) return e.isRange ? 'On now' : 'Today';

    final days = start.difference(today).inDays;
    if (days == 1) return 'Tomorrow';
    if (days <= 30) return 'in $days days';
    return '';
  }
}
