import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_constants.dart';
import '../../services/data/auth_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../common/app_dialog.dart';
import 'admin_workspace.dart';
import 'timetable_changes_review.dart';

/// What the scheduled checks found upstream and no admin has dealt with yet:
/// LMS timetable-change and seating posts, a new Bulletin, new faculty on the
/// BITS website. Seating and roster notices arrive parsed and can be applied
/// here in one step; timetable changes open a per-row review
/// ([TimetableChangesReview]). Hidden entirely when the queue is empty.
class UpstreamNoticesPanel extends StatefulWidget {
  const UpstreamNoticesPanel({super.key});

  @override
  State<UpstreamNoticesPanel> createState() => _UpstreamNoticesPanelState();
}

class _UpstreamNoticesPanelState extends State<UpstreamNoticesPanel> {
  // Held, not rebuilt: the admin screen rebuilds on every upload progress tick.
  late final _stream = FirebaseFirestore.instance
      .collection('upstream_notices')
      .where('status', isEqualTo: 'new')
      .snapshots();
  final Set<String> _busy = {};

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion);

  Future<void> _close(DocumentReference ref, String status) => ref.update({
        'status': status,
        'handledBy': AuthService().userEmail,
        'handledAt': FieldValue.serverTimestamp(),
      });

  /// Seating replaces the campus's exam seating; a roster adds new faculty
  /// through the same rebuild as Professor Schedules.
  Future<void> _apply(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final kind = d.data()['kind'];
    final ok = await AppDialog.confirm(
      context: context,
      title: kind == 'seating' ? 'Replace exam seating?' : 'Add the new faculty?',
      message: kind == 'seating'
          ? "Hyderabad's exam seating is replaced with this PDF: ${d.data()['preview'] ?? ''}."
          : 'They are added to Professor Chambers with their email and phone; '
              'chambers and names already on file are kept.',
      confirmLabel: 'Apply',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(d.id));
    try {
      if (kind == 'seating') {
        final r = await _functions
            .httpsCallable('apply_seating_notice',
                options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
            .call({'noticeId': d.id});
        ToastService.showSuccess('Seating updated: ${(r.data as Map)['preview']}');
      } else {
        final r = await _functions
            .httpsCallable('rebuildProfessorSchedules',
                options: HttpsCallableOptions(timeout: const Duration(minutes: 9)))
            .call({'campusCode': 'hyderabad', 'usePending': true});
        await _close(d.reference, 'done');
        final respelled = ((r.data as Map)['respelled'] as List?)?.cast<Object>() ?? const [];
        if (respelled.isNotEmpty && mounted) {
          AppDialog.adaptive(
            context: context,
            title: 'Matched by spelling — please check',
            content: Text(respelled.join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          );
        } else {
          ToastService.showSuccess('New faculty added');
        }
      }
    } catch (e) {
      ToastService.showError('Could not apply: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(d.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final docs = [...?snap.data?.docs]
          ..sort((a, b) => '${b.data()['postedAt']}'.compareTo('${a.data()['postedAt']}'));
        if (docs.isEmpty) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        return AdminSection(
          title: 'Upstream changes',
          subtitle: '${docs.length} new since you last looked. Apply them, then mark done.',
          trailing: Icon(Icons.campaign_rounded, size: 19, color: AppDesign.warning(context)),
          child: Column(
            children: [
              for (final d in docs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.data()['title']}',
                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (d.data()['preview'] != null)
                        Text('${d.data()['preview']}',
                            style: text.bodySmall?.copyWith(color: AppDesign.muted(context))),
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final a in (d.data()['attachments'] as List? ?? const []))
                            InkWell(
                              onTap: () => launchUrl(Uri.parse('${a['url']}'),
                                  mode: LaunchMode.externalApplication),
                              child: Text('${a['name']}',
                                  style: text.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary)),
                            ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: _busy.contains(d.id)
                                  ? null
                                  : () => _close(d.reference, 'dismissed'),
                              child: const Text('Dismiss'),
                            ),
                            if (d.data()['kind'] == 'timetable_changes')
                              FilledButton(
                                onPressed: () => AppDialog.adaptive(
                                  context: context,
                                  title: '${d.data()['title']}',
                                  content: TimetableChangesReview(noticeId: d.id),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                                child: const Text('Review'),
                              ),
                            if (d.data()['kind'] == 'timetable_changes')
                              FilledButton.tonal(
                                onPressed: () => _close(d.reference, 'done'),
                                child: const Text('Done'),
                              )
                            else if ((d.data()['kind'] == 'seating' && d.data()['applicable'] == true) ||
                                d.data()['kind'] == 'roster')
                              FilledButton(
                                onPressed: _busy.contains(d.id) ? null : () => _apply(d),
                                child: Text(_busy.contains(d.id) ? 'Applying…' : 'Apply'),
                              )
                            else
                              FilledButton.tonal(
                                onPressed: () => _close(d.reference, 'done'),
                                child: const Text('Done'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
