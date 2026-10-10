import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/acad_resource_type.dart';
import '../../services/data/acad_drives_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/empty_state_widget.dart';
import '../../widgets/common/tabulr_surface.dart';

/// The queue of drive links students submitted from Acad Drives. Approving
/// one adds it to the crawler's registry; the next
/// `scripts/acad-drives` sync picks it up.
class DriveSubmissionsScreen extends StatefulWidget {
  const DriveSubmissionsScreen({super.key});

  @override
  State<DriveSubmissionsScreen> createState() => _DriveSubmissionsScreenState();
}

class _DriveSubmissionsScreenState extends State<DriveSubmissionsScreen> {
  final _service = AcadDrivesService();
  late final _stream = _service.pendingSubmissions();
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
          if (docs.isEmpty) {
            return const Center(
              child: EmptyStateWidget(
                icon: Icons.inbox_outlined,
                title: 'Nothing to review',
                subtitle: 'New drive links from students show up here.',
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(AppDesign.spacingMd),
                children: [for (final d in docs) _card(context, d)],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = doc.data();
    final link = (d['driveLink'] ?? '').toString();
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
    setState(() => _busy.add(doc.id));
    try {
      await _service.rejectSubmission(doc.reference);
    } catch (e) {
      ToastService.showError('Could not reject: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }
}
