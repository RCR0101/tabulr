import 'package:flutter/material.dart';

import '../../models/acad_resource_type.dart';
import '../../services/data/acad_drives_service.dart';
import '../../services/data/auth_service.dart';
import '../../services/ui/toast_service.dart';
import '../common/app_dialog.dart';
import '../common/course_picker_sheet.dart';

/// "Report a problem" on an Acad Drives file. The report goes to the admin
/// queue (Admin → Acad Drives Quality), where it is fixed in one tap.
Future<void> showReportFileDialog(BuildContext context, Map<String, dynamic> file) {
  final auth = AuthService();
  if (!auth.isAuthenticated || auth.userEmail == null) {
    ToastService.showError('Sign in with your BITS email to report a file');
    return Future.value();
  }
  return AppDialog.adaptive(
    context: context,
    title: 'Report a problem',
    icon: Icons.flag_outlined,
    content: ReportFileForm(
      file: file,
      onSubmit: (problem, course, type, note) async {
        await AcadDrivesService().reportFile(file,
            reporterEmail: auth.userEmail!,
            problem: problem,
            suggestedCourse: course,
            suggestedType: type,
            note: note);
      },
    ),
  );
}

typedef ReportSubmit = Future<void> Function(
    AcadFileProblem problem, String? course, String? type, String? note);

class ReportFileForm extends StatefulWidget {
  const ReportFileForm({super.key, required this.file, required this.onSubmit, this.pickCourse});

  final Map<String, dynamic> file;
  final ReportSubmit onSubmit;

  /// Replaces the course picker sheet (tests).
  final Future<String?> Function(BuildContext)? pickCourse;

  @override
  State<ReportFileForm> createState() => _ReportFileFormState();
}

class _ReportFileFormState extends State<ReportFileForm> {
  AcadFileProblem? _problem;
  String? _course;
  AcadResourceType? _type;
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickCourse() async {
    final code = widget.pickCourse != null
        ? await widget.pickCourse!(context)
        : (await showCoursePicker(context, title: 'Which course is it for?'))?.firstOrNull?.courseCode;
    if (code != null && mounted) setState(() => _course = code);
  }

  bool get _ready => switch (_problem) {
        null => false,
        AcadFileProblem.wrongCourse => _course != null,
        AcadFileProblem.wrongType => _type != null,
        _ => true,
      };

  Future<void> _send() async {
    if (!_ready || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSubmit(
        _problem!,
        _problem == AcadFileProblem.wrongCourse ? _course : null,
        _problem == AcadFileProblem.wrongType ? _type?.key : null,
        _note.text,
      );
      ToastService.showSuccess('Thanks! An admin will take a look.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ToastService.showError('Could not send the report: $e');
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final codes = (widget.file['course_codes'] as List?) ?? const [];
    final current = AcadResourceType.fromKey(widget.file['resource_type'] as String?);
    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.file['name'] ?? ''}',
                style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              [if (codes.isNotEmpty) 'Filed under ${codes.first}', 'shown as ${current.label}'].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            RadioGroup<AcadFileProblem>(
              groupValue: _problem,
              onChanged: (p) => setState(() => _problem = p),
              child: Column(
                children: [
                  for (final p in AcadFileProblem.values)
                    RadioListTile<AcadFileProblem>(
                      value: p,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(p.label),
                    ),
                ],
              ),
            ),
            if (_problem == AcadFileProblem.wrongCourse)
              OutlinedButton.icon(
                icon: const Icon(Icons.school_outlined, size: 18),
                label: Text(_course == null ? 'Pick the right course' : 'Should be: $_course'),
                onPressed: _pickCourse,
              ),
            if (_problem == AcadFileProblem.wrongType)
              DropdownButtonFormField<AcadResourceType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'It is actually', border: OutlineInputBorder()),
                items: [
                  for (final t in AcadResourceType.values)
                    if (t != current) DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() => _type = t),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Anything else? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _ready && !_sending ? _send : null,
                  child: Text(_sending ? 'Sending…' : 'Send report'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Ask for resources" on a course: tells admins what students are missing,
/// so they know which contributors to look for.
Future<void> showRequestResourcesDialog(BuildContext context, String course) {
  final auth = AuthService();
  final email = auth.userEmail;
  final userDocId = auth.userDocId;
  if (!auth.isAuthenticated || email == null || userDocId == null) {
    ToastService.showError('Sign in with your BITS email to ask for resources');
    return Future.value();
  }
  return AppDialog.adaptive(
    context: context,
    title: 'Ask for $course resources',
    icon: Icons.record_voice_over_outlined,
    content: RequestResourcesForm(
      course: course,
      onSubmit: (types, note) async {
        var asked = 0;
        for (final t in types) {
          final ok = await AcadDrivesService().requestResources(
              course: course, type: t, email: email, userDocId: userDocId, note: note);
          if (ok) asked++;
        }
        return asked;
      },
    ),
  );
}

class RequestResourcesForm extends StatefulWidget {
  const RequestResourcesForm({super.key, required this.course, required this.onSubmit});

  final String course;

  /// Sends one request per type; returns how many were new.
  final Future<int> Function(List<String> types, String? note) onSubmit;

  @override
  State<RequestResourcesForm> createState() => _RequestResourcesFormState();
}

class _RequestResourcesFormState extends State<RequestResourcesForm> {
  static const _askable = [
    AcadResourceType.pyq,
    AcadResourceType.solutions,
    AcadResourceType.notes,
    AcadResourceType.lectures,
    AcadResourceType.assignments,
    AcadResourceType.books,
  ];
  final Set<String> _types = {};
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_types.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final asked = await widget.onSubmit(_types.toList(), _note.text);
      if (asked == 0) {
        ToastService.showInfo('You have already asked for that. We will look for it.');
      } else {
        ToastService.showSuccess("Noted. We'll look for someone who has them.");
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ToastService.showError('Could not send: $e');
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("What's missing? Admins see how many students ask for each course and go looking for drives.",
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _askable)
                FilterChip(
                  label: Text(t.label),
                  selected: _types.contains(t.key),
                  onSelected: (on) => setState(() => on ? _types.add(t.key) : _types.remove(t.key)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Which exam or year? (optional)',
              hintText: 'e.g. 2024 compre with solutions',
              border: OutlineInputBorder(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _types.isNotEmpty && !_sending ? _send : null,
                child: Text(_sending ? 'Sending…' : 'Ask'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
