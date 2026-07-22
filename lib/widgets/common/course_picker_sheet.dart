import 'package:flutter/material.dart';
import '../../services/data/courses_master_service.dart';
import '../../utils/course_code.dart';
import '../../utils/design_constants.dart';
import 'app_button.dart';
import 'app_search_field.dart';
import 'empty_state_widget.dart';

/// Multi-select picker over the campus course catalogue.
///
/// Exists so admin screens never have to hand-type a code, title and unit
/// count the catalogue already holds. Typos there reach students directly, and
/// a mistyped code silently matches nothing at all.
///
/// Multi-select rather than one-at-a-time because the callers build *groups* —
/// a minor's Core list is five to a dozen courses, and reopening a dialog per
/// course is what made the old text box preferable.
///
/// Resolves to the chosen entries, or null if dismissed.
Future<List<CourseMasterEntry>?> showCoursePicker(
  BuildContext context, {
  /// Codes already in the list being edited. Shown greyed and unselectable so
  /// the same course can't be added twice.
  Set<String> alreadyChosen = const {},
  String title = 'Add courses',
}) {
  return showModalBottomSheet<List<CourseMasterEntry>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CoursePickerSheet(
      alreadyChosen: {for (final c in alreadyChosen) normalizeCourseCode(c)},
      title: title,
    ),
  );
}

class _CoursePickerSheet extends StatefulWidget {
  const _CoursePickerSheet({required this.alreadyChosen, required this.title});

  final Set<String> alreadyChosen;
  final String title;

  @override
  State<_CoursePickerSheet> createState() => _CoursePickerSheetState();
}

class _CoursePickerSheetState extends State<_CoursePickerSheet> {
  final _service = CoursesMasterService();
  final _search = TextEditingController();

  List<CourseMasterEntry> _all = const [];
  final Map<String, CourseMasterEntry> _picked = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _service.loadForCampus();
    } catch (_) {
      // Falls through to the empty state; the catalogue is cached locally in
      // normal use, so this only bites when it has never been fetched.
    }
    if (!mounted) return;
    setState(() {
      _all = _service.allCourses
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));
      _loading = false;
    });
  }

  List<CourseMasterEntry> get _visible {
    if (_query.isEmpty) return _all;
    final q = _query.toUpperCase();
    return _all
        .where((c) =>
            c.courseCode.toUpperCase().contains(q) ||
            c.title.toUpperCase().contains(q))
        .toList(growable: false);
  }

  void _toggle(CourseMasterEntry course) {
    final key = normalizeCourseCode(course.courseCode);
    setState(() {
      if (_picked.remove(key) == null) _picked[key] = course;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.spacingMd,
                0,
                AppDesign.spacingMd,
                AppDesign.spacingSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppDesign.spacingSm),
                  AppSearchField(
                    controller: _search,
                    hint: 'Search a code or title…',
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.search_off,
                          title: _all.isEmpty
                              ? 'Catalogue unavailable'
                              : 'No course matches "$_query"',
                          subtitle: _all.isEmpty
                              ? 'The course master has not loaded for this campus.'
                              : 'Try a code like CS F320.',
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final course = visible[i];
                            final key =
                                normalizeCourseCode(course.courseCode);
                            final existing =
                                widget.alreadyChosen.contains(key);
                            final selected = _picked.containsKey(key);

                            return CheckboxListTile(
                              dense: true,
                              value: existing || selected,
                              // Already-added courses stay ticked but locked,
                              // which reads better than hiding them — the
                              // admin can see the group already covers it.
                              onChanged:
                                  existing ? null : (_) => _toggle(course),
                              title: Text(
                                course.courseCode,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                course.title,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              secondary: Text(
                                '${course.credits.round()}u',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              child: AppButton(
                label: _picked.isEmpty
                    ? 'Select courses'
                    : 'Add ${_picked.length} course${_picked.length == 1 ? '' : 's'}',
                icon: Icons.add,
                expand: true,
                onTap: _picked.isEmpty
                    ? null
                    : () => Navigator.of(context)
                        .pop(_picked.values.toList(growable: false)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
