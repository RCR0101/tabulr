import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/data/admin_service.dart';
import '../services/data/config_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/web_utils.dart' as web_utils;
import '../constants/app_constants.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/section_header.dart';
import 'admin/branch_group_management_screen.dart';
import 'admin/course_guide_management_screen.dart';
import 'admin/prerequisites_management_screen.dart';
import 'admin/duplicate_courses_management_screen.dart';
import 'admin/course_management_screen.dart';
import 'admin/exam_seating_management_screen.dart';
import 'admin/professor_management_screen.dart';
import 'admin/bug_tracker_screen.dart';
import '../services/ui/tutorial_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final AdminService _adminService = AdminService();

  static const _campuses = CampusConstants.ids;
  static const _campusLabels = CampusConstants.labels;

  final Map<String, PlatformFile?> _timetableFiles = {};
  PlatformFile? _examFile;
  PlatformFile? _profsFile;

  final Map<String, List<TextEditingController>> _timetableHeaders = {
    for (final c in _campuses) c: [TextEditingController()],
  };
  final List<TextEditingController> _examHeaders = [TextEditingController()];
  final Map<String, TextEditingController> _pageFromControllers = {
    for (final c in _campuses) c: TextEditingController(),
  };
  final Map<String, TextEditingController> _pageToControllers = {
    for (final c in _campuses) c: TextEditingController(),
  };
  final TextEditingController _examYearController =
      TextEditingController(text: '2026');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) TutorialService().showAdminTutorial(context);
      });
    });
  }

  bool _uploadingTimetable = false;
  bool _uploadingExam = false;
  bool _rebuildingProfs = false;
  bool _archiving = false;

  String? _timetableResult;
  String? _timetableProgress;
  String? _examResult;
  String? _examProgress;
  String? _profsResult;
  String? _profsProgress;
  String? _archiveResult;
  String? _archiveProgress;

  final _archiveYearController = TextEditingController();
  int _archiveSemester = 1;

  late final Map<String, DateTime> _semesterDates = {
    ...ConfigService().semesterDates,
  };
  bool _savingDates = false;
  String? _datesResult;

  @override
  void dispose() {
    for (final list in _timetableHeaders.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    for (final c in _examHeaders) {
      c.dispose();
    }
    for (final c in _pageFromControllers.values) {
      c.dispose();
    }
    for (final c in _pageToControllers.values) {
      c.dispose();
    }
    _examYearController.dispose();
    _archiveYearController.dispose();
    super.dispose();
  }

  List<String> _getHeaders(List<TextEditingController> controllers) {
    return controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _pickFile({
    required List<String> extensions,
    required ValueChanged<PlatformFile> onPicked,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      onPicked(result.files.first);
    }
  }

  Future<void> _uploadTimetables() async {
    final toUpload = <String, PlatformFile>{};
    for (final campus in _campuses) {
      final file = _timetableFiles[campus];
      if (file != null && file.bytes != null) toUpload[campus] = file;
    }
    if (toUpload.isEmpty) return;

    setState(() {
      _uploadingTimetable = true;
      _timetableResult = null;
      _timetableProgress = null;
    });

    final results = <String>[];
    final total = toUpload.length;
    var done = 0;
    try {
      for (final entry in toUpload.entries) {
        final campus = entry.key;
        final label = _campusLabels[campus]!;
        setState(() => _timetableProgress =
            'Uploading $label (${ done + 1}/$total)...');
        final from = int.tryParse(_pageFromControllers[campus]!.text.trim());
        final to = int.tryParse(_pageToControllers[campus]!.text.trim());
        final year = int.tryParse(_examYearController.text.trim()) ?? 2026;
        final count = await _adminService.uploadTimetable(
          campusCode: campus,
          fileBytes: entry.value.bytes!,
          fileName: entry.value.name,
          excludeHeaders: _getHeaders(_timetableHeaders[campus]!),
          pageRange: (from != null && to != null) ? [from, to] : null,
          examYear: year,
        );
        done++;
        results.add('$label: $count courses');
        setState(() => _timetableProgress =
            '${results.join(' | ')}${done < total ? ' | Processing...' : ''}');
      }
      setState(() {
        _timetableResult = results.join('\n');
        _timetableProgress = null;
      });
      ToastService.showSuccess('Timetable upload complete');
    } catch (e) {
      setState(() {
        _timetableResult = 'Error: $e';
        _timetableProgress = null;
      });
      ToastService.showError('Upload failed');
    } finally {
      setState(() => _uploadingTimetable = false);
    }
  }

  Future<void> _uploadExamSeating() async {
    if (_examFile == null || _examFile!.bytes == null) return;
    setState(() {
      _uploadingExam = true;
      _examResult = null;
      _examProgress = 'Uploading PDF...';
    });
    try {
      setState(() => _examProgress = 'Processing exam seating...');
      final count = await _adminService.uploadExamSeating(
        campusCode: 'hyderabad',
        fileBytes: _examFile!.bytes!,
        fileName: _examFile!.name,
        excludeHeaders: _getHeaders(_examHeaders),
      );
      setState(() {
        _examResult = 'Uploaded $count exams';
        _examProgress = null;
      });
      ToastService.showSuccess('Uploaded $count exams');
    } catch (e) {
      setState(() {
        _examResult = 'Error: $e';
        _examProgress = null;
      });
      ToastService.showError('Upload failed');
    } finally {
      setState(() => _uploadingExam = false);
    }
  }

  static const String _profsTemplateJson = '''{
  "profs": [
    {
      "name": "JOHN DOE",
      "chamber": "A-123"
    },
    {
      "name": "JANE SMITH",
      "chamber": "D-204"
    }
  ]
}
''';

  Future<void> _downloadProfsTemplate() async {
    final bytes = Uint8List.fromList(utf8.encode(_profsTemplateJson));
    const fileName = 'profs_template.json';
    try {
      if (kIsWeb) {
        web_utils.downloadBlob(bytes, fileName);
        ToastService.showSuccess('Template downloaded');
        return;
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save profs template',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path != null) ToastService.showSuccess('Template saved');
    } catch (e) {
      ToastService.showError('Could not save template');
    }
  }

  Future<void> _rebuildProfessors() async {
    setState(() {
      _rebuildingProfs = true;
      _profsResult = null;
      _profsProgress = 'Rebuilding professor schedules...';
    });
    try {
      final result = await _adminService.rebuildProfessorSchedules(
        profsJsonBytes: _profsFile?.bytes,
      );
      final total = result['professorsUpdated'] ?? 0;
      final matched = result['withSchedule'] ?? 0;
      setState(() {
        _profsResult = 'Updated $total professors ($matched matched)';
        _profsProgress = null;
      });
      ToastService.showSuccess('Updated $total professors');
    } catch (e) {
      setState(() {
        _profsResult = 'Error: $e';
        _profsProgress = null;
      });
      ToastService.showError('Rebuild failed');
    } finally {
      setState(() => _rebuildingProfs = false);
    }
  }

  Future<void> _archiveTimetables() async {
    final year = _archiveYearController.text.trim();
    if (year.isEmpty || !RegExp(r'^\d{4}-\d{4}$').hasMatch(year)) {
      ToastService.showError('Enter academic year in YYYY-YYYY format');
      return;
    }
    setState(() {
      _archiving = true;
      _archiveResult = null;
      _archiveProgress = 'Archiving timetables...';
    });
    try {
      final result = await _adminService.archiveTimetables(
        academicYear: year,
        semester: _archiveSemester,
      );
      final processed = result['usersProcessed'] ?? 0;
      final total = result['totalTimetablesArchived'] ?? 0;
      final skipped = result['usersSkipped'] ?? 0;
      setState(() {
        _archiveResult = 'Archived $total timetables from $processed users ($skipped skipped)';
        _archiveProgress = null;
      });
      ToastService.showSuccess('Archived $total timetables');
    } catch (e) {
      setState(() {
        _archiveResult = 'Error: $e';
        _archiveProgress = null;
      });
      ToastService.showError('Archive failed');
    } finally {
      setState(() => _archiving = false);
    }
  }

  Future<void> _saveSemesterDates() async {
    // Sanity: each start must not be after its matching end.
    bool ordered(String a, String b) =>
        !_semesterDates[a]!.isAfter(_semesterDates[b]!);
    if (!ordered('semesterStart', 'semesterEnd') ||
        !ordered('midsemStart', 'midsemEnd') ||
        !ordered('endsemStart', 'endsemEnd')) {
      ToastService.showError('Each start date must be on or before its end date');
      return;
    }
    setState(() {
      _savingDates = true;
      _datesResult = null;
    });
    try {
      await ConfigService().saveSemesterDates(_semesterDates);
      setState(() => _datesResult = 'Semester dates saved');
      ToastService.showSuccess('Semester dates saved');
    } catch (e) {
      setState(() => _datesResult = 'Error: $e');
      ToastService.showError('Save failed');
    } finally {
      setState(() => _savingDates = false);
    }
  }

  Future<void> _pickSemesterDate(String key) async {
    final current = _semesterDates[key]!;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 3),
    );
    if (picked != null) {
      setState(() {
        _semesterDates[key] = picked;
        _datesResult = null;
      });
    }
  }

  bool get _hasTimetableFiles =>
      _timetableFiles.values.any((f) => f != null);

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Key? key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: AppDesign.opacityDivider),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDesign.spacingSm),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: AppDesign.borderRadiusSm,
                  ),
                  child: Icon(icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: AppDesign.spacingSm + 4),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePicker({
    required String label,
    required PlatformFile? file,
    required List<String> extensions,
    required ValueChanged<PlatformFile?> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingSm + 4, vertical: AppDesign.spacingSm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(
          color: file != null
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
              ),
            ),
          ),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: InkWell(
              onTap: () => _pickFile(
                extensions: extensions,
                onPicked: (f) => onChanged(f),
              ),
              borderRadius: AppDesign.borderRadiusSm,
              child: Row(
                children: [
                  Icon(
                    file != null
                        ? Icons.check_circle_rounded
                        : Icons.upload_file_rounded,
                    size: 18,
                    color: file != null
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                  ),
                  const SizedBox(width: AppDesign.spacingSm),
                  Expanded(
                    child: Text(
                      file?.name ?? 'No file selected',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: file != null
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (file != null)
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium)),
              onPressed: () => onChanged(null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 14,
            ),
        ],
      ),
    );
  }

  Widget _buildExamYearField() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm + 4),
      child: Row(
        children: [
          Text(
            'Exam Year',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
            ),
          ),
          const SizedBox(width: AppDesign.spacingSm + 4),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _examYearController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '2026',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.spacingSm + 4,
                  vertical: AppDesign.spacingSm + 2,
                ),
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: AppDesign.borderRadiusSm,
                  borderSide:
                      BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppDesign.borderRadiusSm,
                  borderSide:
                      BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppDesign.borderRadiusSm,
                  borderSide: BorderSide(color: scheme.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampusSubheading(String campus) {
    return SectionHeader(title: _campusLabels[campus]!);
  }

  Widget _buildPageRange(String campus) {
    final scheme = Theme.of(context).colorScheme;
    InputDecoration inputDeco(String hint) =>
        AppDesign.inputDecoration(context, hint: hint, dense: true);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Page range',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
                ),
              ),
              const SizedBox(width: AppDesign.spacingXs),
              Text(
                '(optional — leave empty for all pages)',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _pageFromControllers[campus]!,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: inputDeco('From'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDesign.spacingSm),
                child: Text('–',
                    style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
              ),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _pageToControllers[campus]!,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: inputDeco('To'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm),
        ],
      ),
    );
  }

  Widget _buildHeaderExclusions(List<TextEditingController> controllers) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Additional headers to exclude',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
              ),
            ),
            const SizedBox(width: AppDesign.spacingXs),
            Text(
              '(defaults are built-in, add semester-specific ones here)',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesign.spacingSm),
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.spacingXs + 2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. COMP CODE, SEATING ARRANGEMENT...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface
                            .withValues(alpha: AppDesign.opacityLow),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppDesign.spacingSm + 4,
                        vertical: AppDesign.spacingSm + 2,
                      ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: AppDesign.borderRadiusSm,
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.15),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppDesign.borderRadiusSm,
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppDesign.borderRadiusSm,
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (controllers.length > 1)
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline_rounded,
                        size: 18,
                        color: scheme.error.withValues(alpha: 0.7)),
                    onPressed: () {
                      setState(() {
                        controllers[i].dispose();
                        controllers.removeAt(i);
                      });
                    },
                    padding: const EdgeInsets.only(left: AppDesign.spacingXs),
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () {
              setState(() => controllers.add(TextEditingController()));
            },
            borderRadius: AppDesign.borderRadiusSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppDesign.spacingXs,
                  horizontal: AppDesign.spacingSm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: AppDesign.spacingXs),
                  Text(
                    'Add header',
                    style: TextStyle(fontSize: 13, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
      ],
    );
  }

  Widget _buildProgressIndicator(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppDesign.spacingSm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingSm + 4, vertical: AppDesign.spacingSm + 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppDesign.spacingSm + 2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBadge(String result) {
    final isError = result.startsWith('Error');
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppDesign.spacingSm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingSm + 4, vertical: AppDesign.spacingSm),
      decoration: BoxDecoration(
        color: isError
            ? scheme.error.withValues(alpha: 0.1)
            : scheme.primary.withValues(alpha: 0.08),
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(
          color: isError
              ? scheme.error.withValues(alpha: 0.2)
              : scheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 16,
            color: isError ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              result,
              style: TextStyle(
                fontSize: 13,
                color: isError ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _managementCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    Key? key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: key,
      color: scheme.surface,
      borderRadius: AppDesign.borderRadiusSm,
      child: InkWell(
        borderRadius: AppDesign.borderRadiusSm,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: AppDesign.borderRadiusSm,
            border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppDesign.spacingSm + 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface
                                .withValues(alpha: AppDesign.opacityMedium))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color:
                      scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _managementCards() {
    final accent = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    return [
      _managementCard(
        key: TutorialKeys.adminManagement,
        icon: Icons.menu_book_rounded,
        title: 'Course Management',
        subtitle: 'Courses, sections & exams',
        color: accent,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CourseManagementScreen())),
      ),
      _managementCard(
        icon: Icons.event_seat_rounded,
        title: 'Exam Seating',
        subtitle: 'Rooms & allocations',
        color: secondary,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ExamSeatingManagementScreen())),
      ),
      _managementCard(
        icon: Icons.person_rounded,
        title: 'Professor Chambers',
        subtitle: 'Chamber & contact info',
        color: tertiary,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ProfessorManagementScreen())),
      ),
      _managementCard(
        icon: Icons.auto_stories_rounded,
        title: 'Course Guide',
        subtitle: 'CDC structure per branch',
        color: accent,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CourseGuideManagementScreen())),
      ),
      _managementCard(
        icon: Icons.workspaces_rounded,
        title: 'Branch Groups',
        subtitle: 'First-year course groups',
        color: secondary,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const BranchGroupManagementScreen())),
      ),
      _managementCard(
        icon: Icons.account_tree_rounded,
        title: 'Prerequisites',
        subtitle: 'Prereqs & co-requisites',
        color: tertiary,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const PrerequisitesManagementScreen())),
      ),
      _managementCard(
        icon: Icons.content_copy_rounded,
        title: 'Duplicate Courses',
        subtitle: 'Equivalence groups',
        color: secondary,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const DuplicateCoursesManagementScreen())),
      ),
      _managementCard(
        icon: Icons.bug_report_rounded,
        title: 'Bug Tracker',
        subtitle: 'User reports & status',
        color: accent,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BugTrackerScreen())),
      ),
    ];
  }

  Widget _timetableUploadSection() {
    return _buildSection(
      key: TutorialKeys.adminTimetableUpload,
      title: 'Timetable Upload',
      icon: Icons.schedule_rounded,
      children: [
        for (final campus in _campuses) ...[
          _buildCampusSubheading(campus),
          _buildFilePicker(
            label: 'PDF',
            file: _timetableFiles[campus],
            extensions: ['pdf'],
            onChanged: (f) =>
                setState(() => _timetableFiles[campus] = f),
          ),
          if (_timetableFiles[campus] != null) ...[
            _buildPageRange(campus),
            _buildHeaderExclusions(_timetableHeaders[campus]!),
          ],
        ],
        const SizedBox(height: AppDesign.spacingSm),
        _buildExamYearField(),
        AppButton(
          label: 'Upload Timetables',
          icon: Icons.cloud_upload_rounded,
          onTap: _hasTimetableFiles && !_uploadingTimetable
              ? _uploadTimetables
              : null,
          isLoading: _uploadingTimetable,
          expand: true,
        ),
        if (_timetableProgress != null)
          _buildProgressIndicator(_timetableProgress!),
        if (_timetableResult != null)
          _buildResultBadge(_timetableResult!),
      ],
    );
  }

  Widget _examUploadSection() {
    return _buildSection(
      key: TutorialKeys.adminExamUpload,
      title: 'Exam Seating (Hyderabad)',
      icon: Icons.event_seat_rounded,
      children: [
        _buildFilePicker(
          label: 'PDF File',
          file: _examFile,
          extensions: ['pdf'],
          onChanged: (f) => setState(() => _examFile = f),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        _buildHeaderExclusions(_examHeaders),
        AppButton(
          label: 'Upload Exam Seating',
          icon: Icons.cloud_upload_rounded,
          onTap: _examFile != null && !_uploadingExam
              ? _uploadExamSeating
              : null,
          isLoading: _uploadingExam,
          expand: true,
        ),
        if (_examProgress != null)
          _buildProgressIndicator(_examProgress!),
        if (_examResult != null) _buildResultBadge(_examResult!),
      ],
    );
  }

  Widget _profsSection() {
    return _buildSection(
      title: 'Professor Schedules',
      icon: Icons.school_rounded,
      children: [
        _buildFilePicker(
          label: 'profs.json',
          file: _profsFile,
          extensions: ['json'],
          onChanged: (f) => setState(() => _profsFile = f),
        ),
        Text(
          'Optional — uses stored data if not provided',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: AppDesign.opacityLow),
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Download template',
            icon: Icons.download_rounded,
            variant: AppButtonVariant.ghost,
            onTap: _downloadProfsTemplate,
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm + 4),
        AppButton(
          label: 'Rebuild Schedules',
          icon: Icons.sync_rounded,
          onTap: !_rebuildingProfs ? _rebuildProfessors : null,
          isLoading: _rebuildingProfs,
          expand: true,
        ),
        if (_profsProgress != null)
          _buildProgressIndicator(_profsProgress!),
        if (_profsResult != null) _buildResultBadge(_profsResult!),
      ],
    );
  }

  Widget _archiveSection() {
    final scheme = Theme.of(context).colorScheme;
    return _buildSection(
      title: 'Archive Timetables',
      icon: Icons.archive_rounded,
      children: [
        TextField(
          controller: _archiveYearController,
          decoration: InputDecoration(
            labelText: 'Academic Year',
            hintText: '2025-2026',
            border: const OutlineInputBorder(),
            isDense: true,
            labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium)),
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        DropdownButtonFormField<int>(
          initialValue: _archiveSemester,
          decoration: const InputDecoration(
            labelText: 'Semester',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Semester 1')),
            DropdownMenuItem(value: 2, child: Text('Semester 2')),
          ],
          onChanged: (v) => setState(() => _archiveSemester = v ?? 1),
        ),
        const SizedBox(height: AppDesign.spacingSm + 4),
        AppButton(
          label: 'Archive All Users',
          icon: Icons.archive_rounded,
          onTap: !_archiving ? _archiveTimetables : null,
          isLoading: _archiving,
          expand: true,
        ),
        if (_archiveProgress != null)
          _buildProgressIndicator(_archiveProgress!),
        if (_archiveResult != null) _buildResultBadge(_archiveResult!),
      ],
    );
  }

  Widget _semesterDatesSection() {
    final scheme = Theme.of(context).colorScheme;
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return _buildSection(
      title: 'Semester Dates',
      icon: Icons.date_range_rounded,
      children: [
        Text(
          'Drives the Calendar and exports. Applies to all users on next open.',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow),
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        for (final key in ConfigService.dateKeys)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.spacingXs + 2),
            child: InkWell(
              borderRadius: AppDesign.borderRadiusSm,
              onTap: _savingDates ? null : () => _pickSemesterDate(key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.spacingSm + 4,
                    vertical: AppDesign.spacingSm + 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: AppDesign.borderRadiusSm,
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ConfigService.dateLabels[key] ?? key,
                        style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface
                                .withValues(alpha: AppDesign.opacityHigh)),
                      ),
                    ),
                    Text(fmt(_semesterDates[key]!),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                    const SizedBox(width: AppDesign.spacingSm),
                    Icon(Icons.edit_calendar_rounded,
                        size: 16, color: AppDesign.muted(context)),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppDesign.spacingSm),
        AppButton(
          label: 'Save Dates',
          icon: Icons.check_rounded,
          onTap: !_savingDates ? _saveSemesterDates : null,
          isLoading: _savingDates,
          expand: true,
        ),
        if (_datesResult != null) _buildResultBadge(_datesResult!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveService.getAdaptivePadding(
      context,
      const EdgeInsets.all(AppDesign.spacingMd),
    );
    final wide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Admin Dashboard'),
      body: SingleChildScrollView(
        padding: padding,
        child: wide ? _wideLayout() : _narrowLayout(),
      ),
    );
  }

  Widget _narrowLayout() {
    return Column(
      children: [
        ..._managementCards().map((c) => Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
              child: c,
            )),
        const SizedBox(height: AppDesign.spacingSm),
        _timetableUploadSection(),
        _archiveSection(),
        _examUploadSection(),
        _profsSection(),
        _semesterDatesSection(),
      ],
    );
  }

  /// Lays out the management cards as centered rows of up to 4, with every
  /// card a uniform width so partial rows stay symmetric.
  Widget _managementGrid() {
    const perRow = 4;
    const gap = AppDesign.spacingMd;
    final cards = _managementCards();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _wideLayout() {
    return Column(
      children: [
        _managementGrid(),
        const SizedBox(height: AppDesign.spacingMd),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  _timetableUploadSection(),
                  _archiveSection(),
                ],
              ),
            ),
            const SizedBox(width: AppDesign.spacingMd),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  _examUploadSection(),
                  _profsSection(),
                  _semesterDatesSection(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
