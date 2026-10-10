import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';

/// The edits a "Timetable changes-N" PDF proposes, judged against the live
/// timetable (functions-python/changes.py), with a tick per row. Rows whose
/// live data still matches the PDF's "existing" start ticked; rows to check
/// start unticked; rows already in, or that need adding by hand, can't be
/// ticked. Applying re-judges on the server, so nothing stale is written.
/// Every row can show its snippet of the PDF, open by default where a human
/// has to decide (check, add by hand, not found).
class TimetableChangesReview extends StatefulWidget {
  const TimetableChangesReview({super.key, required this.noticeId, this.preview});

  final String noticeId;

  /// A preview_changes_notice result to show instead of calling it (tests).
  final Map? preview;

  @override
  State<TimetableChangesReview> createState() => _TimetableChangesReviewState();
}

class _TimetableChangesReviewState extends State<TimetableChangesReview> {
  static const _order = ['check', 'apply', 'manual', 'missing', 'done'];
  static const _kinds = {
    'instructor': 'Instructor',
    'schedule': 'Room / hours',
    'exam': 'Exam dates',
    'new_course': 'New course',
  };

  List<Map<String, dynamic>>? _changes;
  String? _error;
  String _summary = '';
  final Set<String> _selected = {};
  // Kept across applies: the apply result re-judges rows but sends no images.
  final Map<String, Uint8List> _shots = {};
  final Set<String> _open = {};
  bool _applying = false;

  HttpsCallable _call(String name) =>
      FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion)
          .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(minutes: 2)));

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _take(widget.preview!);
    } else {
      _load();
    }
  }

  void _take(Map data) {
    final list = [
      for (final c in (data['changes'] as List)) Map<String, dynamic>.from(c as Map)
    ]..sort((a, b) => _order.indexOf(a['status']).compareTo(_order.indexOf(b['status'])));
    _changes = list;
    _summary = '${data['summary'] ?? ''}';
    for (final c in list) {
      final shot = c['snippet'];
      if (shot is String && !_shots.containsKey(c['key'])) {
        _shots[c['key'] as String] = base64Decode(shot);
        if (const {'check', 'manual', 'missing'}.contains(c['status'])) _open.add(c['key'] as String);
      }
    }
    _selected
      ..clear()
      ..addAll(list.where((c) => c['status'] == 'apply').map((c) => c['key'] as String));
  }

  Future<void> _load() async {
    try {
      final r = await _call('preview_changes_notice').call({'noticeId': widget.noticeId});
      if (mounted) setState(() => _take(r.data as Map));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final r = await _call('apply_changes_notice')
          .call({'noticeId': widget.noticeId, 'keys': _selected.toList()});
      final data = r.data as Map;
      ToastService.showSuccess('${data['applied']} changes applied to the timetable');
      if (mounted) setState(() => _take(data));
    } catch (e) {
      ToastService.showError('Could not apply: $e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  (Color, String) _status(BuildContext context, String status) => switch (status) {
        'apply' => (AppDesign.info(context), 'Ready'),
        'check' => (AppDesign.warning(context), 'Check'),
        'done' => (AppDesign.success(context), 'Already in'),
        'manual' => (AppDesign.danger(context), 'Add by hand'),
        _ => (AppDesign.danger(context), 'Not found'),
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_error != null) return Text('Could not read the PDF: $_error');
    final changes = _changes;
    if (changes == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_summary, style: text.bodyMedium),
          Text(
            'Ticked rows still match what the PDF calls "existing". "Check" means '
            'the live data differs from it: tick it if the PDF is right anyway.',
            style: text.bodySmall?.copyWith(color: AppDesign.muted(context)),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: changes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = changes[i];
                final key = c['key'] as String;
                final selectable = c['status'] == 'apply' || c['status'] == 'check';
                final (color, word) = _status(context, c['status'] as String);
                return CheckboxListTile(
                  value: _selected.contains(key),
                  onChanged: selectable && !_applying
                      ? (v) => setState(() => v! ? _selected.add(key) : _selected.remove(key))
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${'${c['course']} ${c['section']}'.trim()} · ${_kinds[c['kind']] ?? c['kind']}',
                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(word, style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ('${c['before']}'.isNotEmpty) Text('Now: ${c['before']}'),
                      if ('${c['after']}'.isNotEmpty)
                        Text('${c['status'] == 'done' ? 'PDF' : 'New'}: ${c['after']}'),
                      if ('${c['reason']}'.isNotEmpty)
                        Text('${c['reason']}', style: TextStyle(color: color)),
                      if (_shots[key] != null) ...[
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key)),
                          icon: Icon(_open.contains(key) ? Icons.expand_less : Icons.picture_as_pdf_outlined, size: 18),
                          label: Text(_open.contains(key) ? 'Hide the PDF' : 'What the PDF says'),
                        ),
                        if (_open.contains(key))
                          Container(
                            // The PDF is black on white in either theme.
                            color: Colors.white,
                            padding: const EdgeInsets.all(4),
                            child: Image.memory(_shots[key]!, filterQuality: FilterQuality.medium),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _selected.isEmpty || _applying ? null : _apply,
              child: Text(_applying ? 'Applying…' : 'Apply ${_selected.length}'),
            ),
          ),
        ],
      ),
    );
  }
}
