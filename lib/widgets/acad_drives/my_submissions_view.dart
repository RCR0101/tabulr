import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/data/acad_drives_service.dart';
import '../../utils/design_constants.dart';
import '../common/app_dialog.dart';

/// Opens the student's own drive submissions and where each has got to:
/// waiting for review, approved, live with N files, a sharing problem the
/// sync hit, or not added (with the reviewer's note).
Future<void> showMySubmissions(BuildContext context, {required String email}) {
  return AppDialog.adaptive(
    context: context,
    title: 'My submissions',
    icon: Icons.outbox_rounded,
    content: SizedBox(
      width: 560,
      child: MySubmissionsView(stream: AcadDrivesService().mySubmissions(email)),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
    ],
  );
}

class MySubmissionsView extends StatelessWidget {
  const MySubmissionsView({super.key, required this.stream});

  final Stream<List<MySubmission>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MySubmission>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Could not load your submissions. Try again in a moment.'),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              "You haven't submitted a drive yet. Use Submit resource to share one.",
              style: TextStyle(color: AppDesign.muted(context)),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _SubmissionTile(item: items[i]),
        );
      },
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.item});

  final MySubmission item;

  (IconData, Color, String, String?) _describe(BuildContext context) {
    final date = item.syncedAt == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(item.syncedAt!);
    return switch (item.stage) {
      MySubmissionStage.waiting => (
          Icons.hourglass_top_rounded,
          AppDesign.info(context),
          'Waiting for review',
          'An admin checks each link before it is added.',
        ),
      MySubmissionStage.approved => (
          Icons.check_circle_outline_rounded,
          AppDesign.info(context),
          'Approved',
          'Its files appear after the next sync.',
        ),
      MySubmissionStage.live => (
          Icons.cloud_done_rounded,
          AppDesign.success(context),
          'Live · ${item.syncedFiles ?? 0} ${item.syncedFiles == 1 ? 'file' : 'files'}',
          'Last synced $date. Thank you!',
        ),
      MySubmissionStage.problem => (
          Icons.link_off_rounded,
          AppDesign.warning(context),
          'Could not sync',
          item.syncProblem,
        ),
      MySubmissionStage.rejected => (
          Icons.do_not_disturb_on_outlined,
          AppDesign.danger(context),
          'Not added',
          item.reviewNote,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (icon, color, label, detail) = _describe(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(item.title.isEmpty ? item.driveLink : item.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
          if (detail != null && detail.isNotEmpty)
            Text(detail, style: text.bodySmall?.copyWith(color: AppDesign.muted(context))),
        ],
      ),
      trailing: item.driveLink.startsWith('https://')
          ? IconButton(
              tooltip: 'Open the link',
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              onPressed: () => launchUrl(Uri.parse(item.driveLink), mode: LaunchMode.externalApplication),
            )
          : null,
    );
  }
}
