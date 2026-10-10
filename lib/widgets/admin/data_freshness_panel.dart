import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_constants.dart';
import '../../models/data_freshness.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import 'admin_workspace.dart';

/// One dataset's last upload, per campus (or once, under `null`, when it is
/// shared by all three).
class FreshnessRow {
  const FreshnessRow(this.label, this.stamps, {this.howTo});

  final String label;
  final Map<String?, DateTime?> stamps;

  /// Where to refresh it, so whoever inherits the admin screen knows.
  final String? howTo;
}

/// Shows when each dataset students depend on was last uploaded, and flags
/// anything not refreshed since this term began. Reads only the markers the
/// upload paths already write.
class DataFreshnessPanel extends StatefulWidget {
  const DataFreshnessPanel({super.key, this.rows});

  /// Injected by tests and previews; loaded from Firestore otherwise.
  final List<FreshnessRow>? rows;

  @override
  State<DataFreshnessPanel> createState() => _DataFreshnessPanelState();
}

class _DataFreshnessPanelState extends State<DataFreshnessPanel> {
  bool _checking = false;

  /// Runs the weekly LMS and Bulletin check now; anything new appears under
  /// Upstream changes.
  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final r = await FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion)
          .httpsCallable('check_upstream_now',
              options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
          .call();
      final added = ((r.data as Map)['added'] as List?) ?? const [];
      ToastService.showSuccess(added.isEmpty
          ? 'Nothing new on the LMS or the Bulletin page'
          : '${added.length} new — see Upstream changes');
    } catch (e) {
      ToastService.showError('Check failed: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  late final Future<List<FreshnessRow>> _rows =
      widget.rows != null ? Future.value(widget.rows) : _load();

  static Future<List<FreshnessRow>> _load() async {
    final db = FirebaseFirestore.instance;
    Future<DateTime?> stamp(String path, List<String> fields) async {
      try {
        final data = (await db.doc(path).get()).data();
        for (final f in fields) {
          final t = parseUploadStamp(data?[f]);
          if (t != null) return t;
        }
      } catch (_) {
        // A missing or unreadable marker shows as "Never", which is the point.
      }
      return null;
    }

    Future<Map<String?, DateTime?>> perCampus(String Function(String) path, List<String> fields) async {
      final ids = CampusConstants.ids;
      final values = await Future.wait(ids.map((c) => stamp(path(c), fields)));
      return {for (var i = 0; i < ids.length; i++) ids[i]: values[i]};
    }

    Future<DateTime?> drivesIndex() async {
      try {
        final res = await http.get(Uri.parse(AppUrls.acadDrivesIndexUrl)).timeout(const Duration(seconds: 8));
        return parseUploadStamp((jsonDecode(res.body) as Map)['updatedAt']);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      perCampus((c) => 'campuses/$c/metadata/current', ['uploadedAt', 'lastUpdated']),
      perCampus((c) => 'campuses/$c/academicCalendar/current', ['updatedAt']),
      // Seating and professor schedules are only uploaded for Hyderabad.
      stamp('admin_metadata/exam_seating_hyderabad', ['lastUpdated']).then((t) => {'hyderabad': t}),
      // `professors` is the marker the pre-callable admin script wrote.
      stamp('admin_metadata/professors_hyderabad', ['lastUpdated'])
          .then((t) async => {'hyderabad': t ?? await stamp('admin_metadata/professors', ['lastUpdated'])}),
      stamp('reference/prerequisites', ['lastUpdated']).then((t) => {null: t}),
      drivesIndex().then((t) => {null: t}),
    ]);
    return [
      FreshnessRow('Timetable', results[0], howTo: 'Timetable Upload below'),
      FreshnessRow('Academic calendar', results[1], howTo: 'Rides along with the timetable PDF'),
      FreshnessRow('Exam seating', results[2], howTo: 'From the LMS: Apply it under Upstream changes'),
      FreshnessRow('Professor schedules', results[3], howTo: 'Professor Schedules → Rebuild Schedules'),
      FreshnessRow('Prerequisites', results[4], howTo: 'scripts/upload-prerequisites.js'),
      FreshnessRow('Acad Drives', results[5], howTo: 'Weekly sync, Monday mornings'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AdminSection(
      title: 'Data freshness',
      subtitle: 'Green: this term · Amber: last term · Red: never uploaded',
      trailing: TextButton.icon(
        icon: _checking
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync_rounded, size: 18),
        label: const Text('Check now'),
        onPressed: _checking || widget.rows != null ? null : _checkNow,
      ),
      child: FutureBuilder<List<FreshnessRow>>(
        future: _rows,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(AppDesign.spacingMd),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final now = DateTime.now();
          return Column(
            children: [for (final row in snap.data!) _row(context, row, now)],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, FreshnessRow row, DateTime now) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (row.howTo != null)
                  Text(row.howTo!, style: text.bodySmall?.copyWith(color: AppDesign.muted(context))),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in row.stamps.entries)
                  _chip(context, CampusConstants.labels[e.key], e.value, now),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String? campus, DateTime? at, DateTime now) {
    final state = freshnessOf(at, now);
    final color = switch (state) {
      // success() is the theme's secondary, which is grey in some themes.
      Freshness.current => Color.lerp(Colors.green, Theme.of(context).colorScheme.primary, 0.2)!,
      Freshness.stale => AppDesign.warning(context),
      Freshness.missing => AppDesign.danger(context),
    };
    final when = at == null
        ? 'Never'
        : MaterialLocalizations.of(context).formatShortDate(at.toLocal());
    final word = switch (state) {
      Freshness.current => when,
      Freshness.stale => 'Last term · $when',
      Freshness.missing => 'Never',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppDesign.cardBorderRadius(context),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        campus == null ? word : '$campus · $word',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
