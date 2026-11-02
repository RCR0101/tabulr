import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/acad_resource_type.dart';
import '../../services/data/acad_drives_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../utils/drive_link.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/empty_state_widget.dart';
import '../../widgets/common/tabulr_surface.dart';

/// The queue of drive links students submitted from Acad Drives. Approving
/// one adds it to the crawler's registry; the next
/// `scripts/acad-drives` sync picks it up. Below the queue, drives whose last
/// sync failed (never shared, deleted, empty), as the crawler reported them.
class DriveSubmissionsScreen extends StatefulWidget {
  const DriveSubmissionsScreen({super.key});

  @override
  State<DriveSubmissionsScreen> createState() => _DriveSubmissionsScreenState();
}

class _DriveSubmissionsScreenState extends State<DriveSubmissionsScreen> {
  final _service = AcadDrivesService();
  late final _stream = _service.pendingSubmissions();
  late final _sourcesStream = _service.sources();
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.add_link_rounded,
          title: 'Drive Submissions',
          subtitle: 'Approved drives sync on the next crawler run',
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _sourcesStream,
        builder: (context, sourcesSnap) => StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: EmptyStateWidget(
                  icon: Icons.error_outline,
                  title: 'Could not load submissions',
                  subtitle: 'Check your admin access and try again.',
                ),
              );
            }
            final docs = snapshot.data ?? const [];
            final sources = sourcesSnap.data ?? const [];
            final failing = [
              for (final s in sources)
                if (s.data()['disabled'] != true && (s.data()['lastSync'] as Map?)?['problem'] != null) s
            ]..sort((a, b) => '${a.data()['name']}'.compareTo('${b.data()['name']}'));
            if (docs.isEmpty && failing.isEmpty) {
              return const Center(
                child: EmptyStateWidget(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing to review',
                  subtitle: 'New drive links from students show up here.',
                ),
              );
            }
            // Drive id -> name of the synced drive it already is.
            final synced = <String, String>{
              for (final s in sources)
                if (driveIdOf('${s.data()['driveLink'] ?? ''}') case final id?) id: '${s.data()['name']}',
            };
            final seen = <String>{};
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  children: [
                    for (final d in docs) _card(context, d, synced: synced, seen: seen),
                    if (failing.isNotEmpty) ...[
                      const SizedBox(height: AppDesign.spacingMd),
                      Text('Drives that failed to sync',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: AppDesign.spacingSm),
                        child: Text(
                          'From the last sync run. Fix the link with the contributor, or stop syncing it; '
                          'files it already synced stay.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppDesign.muted(context)),
                        ),
                      ),
                      for (final s in failing) _failingCard(context, s),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _failingCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final text = Theme.of(context).textTheme;
    final d = doc.data();
    final sync = (d['lastSync'] as Map?) ?? const {};
    final at = (sync['at'] as Timestamp?)?.toDate();
    final link = '${d['driveLink'] ?? ''}';
    final busy = _busy.contains(doc.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: TabulrSurface(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${d['name']}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [
                'by ${d['contributor'] ?? 'Unknown'}',
                if (at != null) 'last tried ${MaterialLocalizations.of(context).formatShortDate(at)}',
              ].join('  ·  '),
              style: text.bodySmall?.copyWith(color: AppDesign.muted(context)),
            ),
            const SizedBox(height: AppDesign.spacingSm),
            Text('${sync['problem']}', style: text.bodyMedium?.copyWith(color: AppDesign.warning(context))),
            const SizedBox(height: AppDesign.spacingSm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (link.startsWith('https://'))
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                    child: const Text('Open link'),
                  ),
                const SizedBox(width: AppDesign.spacingSm),
                FilledButton.tonal(
                  onPressed: busy ? null : () => _stopSyncing(doc),
                  child: const Text('Stop syncing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopSyncing(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Stop syncing "${doc.data()['name']}"?',
      message: 'The sync skips it from now on. Files it already synced stay in Acad Drives.',
      confirmLabel: 'Stop syncing',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(doc.id));
    try {
      await _service.setSourceDisabled(doc.reference, true);
    } catch (e) {
      ToastService.showError('Could not update: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  Widget _card(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required Map<String, String> synced,
    required Set<String> seen,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = doc.data();
    final link = (d['driveLink'] ?? '').toString();
    // Caught here rather than by the sync: a link it cannot read, a drive
    // that is already synced, or the same drive sent twice.
    final driveId = driveIdOf(link);
    final warning = driveId == null
        ? 'The sync cannot read this link: it is not a Google Drive folder or file.'
        : synced.containsKey(driveId)
            ? 'Already synced as "${synced[driveId]}". Approving would add every file twice.'
            : !seen.add(driveId)
                ? 'The same drive as a submission above.'
                : null;
    final type = d['resourceType'] == null ? null : AcadResourceType.fromKey(d['resourceType'] as String);
    final submittedAt = (d['submittedAt'] as Timestamp?)?.toDate();
    final busy = _busy.contains(doc.id);
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: TabulrSurface(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((d['title'] ?? '').toString(),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [
                'by ${d['contributorName']}',
                d['submittedBy'],
                if (submittedAt != null) MaterialLocalizations.of(context).formatShortDate(submittedAt),
              ].join('  ·  '),
              style: muted,
            ),
            const SizedBox(height: AppDesign.spacingSm),
            InkWell(
              onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
              child: Text(link,
                  style: text.bodyMedium?.copyWith(color: scheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (d['courseCode'] != null || type != null) ...[
              const SizedBox(height: AppDesign.spacingSm),
              Wrap(spacing: 8, children: [
                if (d['courseCode'] != null) Chip(label: Text('Course: ${d['courseCode']}')),
                if (type != null) Chip(label: Text(type.label)),
              ]),
            ],
            if (warning != null) ...[
              const SizedBox(height: AppDesign.spacingSm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: AppDesign.warning(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(warning, style: text.bodySmall?.copyWith(color: AppDesign.warning(context))),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppDesign.spacingSm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => _reject(doc),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: AppDesign.spacingSm),
                FilledButton(
                  onPressed: busy ? null : () => _approve(doc),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final name = await AppDialog.input(
      context: context,
      title: 'Name this drive',
      initialValue: (doc.data()['title'] ?? '').toString(),
      hint: 'Shown to students as the drive name',
      confirmLabel: 'Approve',
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => _busy.add(doc.id));
    try {
      final added = await _service.approveSubmission(doc, name: name);
      if (added) {
        ToastService.showSuccess('Added "$name". It syncs on the next crawler run.');
      } else {
        ToastService.showError('A drive called "$name" already exists. Pick another name.');
      }
    } catch (e) {
      ToastService.showError('Could not approve: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  Future<void> _reject(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    // Shown to the student in "My submissions", so they can fix and resend.
    final note = await AppDialog.input(
      context: context,
      title: 'Reject this link?',
      hint: 'Reason the student sees (optional), e.g. "Not shared publicly"',
      confirmLabel: 'Reject',
    );
    if (note == null || !mounted) return;
    setState(() => _busy.add(doc.id));
    try {
      await _service.rejectSubmission(doc.reference, note: note.length > 300 ? note.substring(0, 300) : note);
    } catch (e) {
      ToastService.showError('Could not reject: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }
}
