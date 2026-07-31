import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/cdc_slot.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/branch_structure_service.dart';
import '../services/data/courses_master_service.dart';
import '../services/data/profile_service.dart';
import '../services/ui/secure_logger.dart';
import '../utils/branch_constants.dart' as constants;

class AutoLoadCDCResult {
  final String primaryBranch;

  /// Second branch for dual-degree students, or null for a single degree.
  final String? secondaryBranch;

  /// Year-semester, e.g. `3-1`.
  final String semester;

  /// The course the student picked for each optional CDC — a slot listing two
  /// or more alternatives of which exactly one is taken. Empty when this
  /// degree and year has no choices to make.
  ///
  /// Everything downstream resolves against this the same way, via
  /// [CdcSlot.resolveAll]: an unanswered choice contributes nothing rather
  /// than quietly loading the first alternative.
  final Set<String> chosen;

  AutoLoadCDCResult({
    required this.primaryBranch,
    this.secondaryBranch,
    required this.semester,
    this.chosen = const {},
  });
}

class AutoLoadCDCDialog extends StatefulWidget {
  const AutoLoadCDCDialog({super.key, this.semesters});

  /// The year-semesters on offer. Defaults to years 1–4; sample timetables
  /// narrow it to the first semester of each year, the only ones they cover.
  final List<String>? semesters;

  @override
  State<AutoLoadCDCDialog> createState() => _AutoLoadCDCDialogState();
}

class _AutoLoadCDCDialogState extends State<AutoLoadCDCDialog> {
  final List<String> _branches =
      constants.branchCodeToName.keys.toList()..sort();

  // Dual-degree students run to 4-2; a single degree simply never selects those.
  late final List<String> _semesters =
      widget.semesters ?? SemesterConstants.yearsOneToFour;

  String? _selectedBranch;
  String? _selectedSecondaryBranch;
  String? _selectedSemester;

  /// The optional CDCs for the chosen degree and year, once the first step has
  /// been submitted and found some. Null means we are still on the first step.
  List<CdcSlot>? _choices;

  /// Chosen course per entry of [_choices], by index — not by course code,
  /// because two choices may offer the same alternative.
  final Map<int, String> _picks = {};

  bool _resolving = false;

  bool get _canSubmit => _selectedBranch != null && _selectedSemester != null;

  /// The primary button: submits step one, or confirms the picks on step two.
  /// Every choice must be answered — a half-answered set would silently load
  /// fewer courses than the student asked for.
  bool get _canAdvance => _resolving
      ? false
      : _choices == null
          ? _canSubmit
          : _picks.length == _choices!.length;

  /// Spins while step one is looking up whether there are choices to make —
  /// that is a Firestore read, and on a cold cache the dialog would otherwise
  /// just sit there.
  Widget _primaryIcon(double size) => _resolving
      ? SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        )
      : Icon(Icons.download, size: size);

  void _advance() {
    if (_choices == null) {
      _submit();
    } else {
      Navigator.of(context).pop(_result);
    }
  }

  /// Cancel on step one, back to it on step two — the picks belong to a
  /// particular degree and year, so they are dropped rather than carried into
  /// whatever gets chosen next.
  void _back() {
    if (_choices == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _choices = null;
      _picks.clear();
    });
  }

  AutoLoadCDCResult get _result => AutoLoadCDCResult(
    primaryBranch: _selectedBranch!,
    secondaryBranch: _selectedSecondaryBranch,
    semester: _selectedSemester!,
    chosen: _picks.values.toSet(),
  );

  /// Leaves the first step. A degree and year whose CDCs include a choice can't
  /// be loaded until the student says which course they are taking, so those
  /// get a second step; everything else closes straight away, exactly as
  /// before.
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _resolving = true);

    List<CdcSlot> slots;
    try {
      slots = await BranchStructureService().getCoreCourseSlots(
        _selectedSemester!,
        _selectedBranch!,
        null,
        _selectedSecondaryBranch,
      );
    } catch (e) {
      // The loader that runs next reads the same structure and will report an
      // empty result properly; blocking here would only hide that.
      SecureLogger.warning('AUTO_LOAD_CDC', 'Could not resolve optional CDCs',
          {'error': e.toString()});
      slots = const [];
    }
    if (!mounted) return;

    final choices = [for (final slot in slots) if (slot.isChoice) slot];
    if (choices.isEmpty) {
      Navigator.of(context).pop(_result);
      return;
    }
    setState(() {
      _choices = choices;
      _resolving = false;
    });
  }

  @override
  void initState() {
    super.initState();
    // Pre-select the user's saved defaults so CDC loading is one tap.
    final profile = ProfileService().cached;
    if (profile.primaryBranch != null &&
        _branches.contains(profile.primaryBranch)) {
      _selectedBranch = profile.primaryBranch;
    }
    if (profile.secondaryBranch != null &&
        _branches.contains(profile.secondaryBranch) &&
        profile.secondaryBranch != _selectedBranch) {
      _selectedSecondaryBranch = profile.secondaryBranch;
    }
    if (profile.currentSemester != null &&
        _semesters.contains(profile.currentSemester)) {
      _selectedSemester = profile.currentSemester;
    }
  }


  /// Step two, shown only when this degree and year has optional CDCs: one
  /// course has to be picked out of each set of alternatives before anything
  /// can be loaded.
  List<Widget> _choiceFields() {
    final scheme = Theme.of(context).colorScheme;
    final choices = _choices!;
    final master = CoursesMasterService();

    return [
      Text(
        choices.length == 1
            ? 'One of your core courses is a choice. Pick the course you are taking.'
            : '${choices.length} of your core courses are choices. Pick the course you are taking for each.',
        style: TextStyle(
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
        ),
      ),
      SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),
      for (var i = 0; i < choices.length; i++) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _picks.containsKey(i)
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in choices[i].options)
                RadioListTile<String>(
                  value: option,
                  // ignore: deprecated_member_use
                  groupValue: _picks[i],
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    ResponsiveService.triggerSelectionFeedback(context);
                    setState(() => _picks[i] = value!);
                  },
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    option,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    master.getTitle(option),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  /// Step one: which degree and year to pull CDCs for.
  List<Widget> _degreeFields() {
    return [
      Text(
        'Select your branch and year to automatically load Core Discipline Courses (CDCs). '
        'Add a second branch if you are a dual degree student.',
        style: TextStyle(
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
        ),
      ),
      SizedBox(
        height: ResponsiveService.getAdaptiveSpacing(context, 20),
      ),

      Text(
        'Branch *',
        style: TextStyle(
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
          fontWeight: FontWeight.w500,
        ),
      ),
      SizedBox(
        height: ResponsiveService.getAdaptiveSpacing(context, 8),
      ),
      DropdownButtonFormField<String>(
        initialValue: _selectedBranch,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: ResponsiveService.getAdaptivePadding(
            context,
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
        ),
        items:
            _branches.map((branch) {
              final name = constants.branchCodeToName[branch] ?? branch;
              return DropdownMenuItem<String>(
                value: branch,
                child: Text('$branch - $name'),
              );
            }).toList(),
        onChanged: (String? newValue) {
          ResponsiveService.triggerSelectionFeedback(context);
          setState(() {
            _selectedBranch = newValue;
            // A branch cannot be both halves of a dual degree.
            if (_selectedSecondaryBranch == newValue) {
              _selectedSecondaryBranch = null;
            }
          });
        },
        isExpanded: true,
        hint: const Text('Select your branch'),
      ),

      SizedBox(
        height: ResponsiveService.getAdaptiveSpacing(context, 16),
      ),

      Text(
        'Second branch',
        style: TextStyle(
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
          fontWeight: FontWeight.w500,
        ),
      ),
      SizedBox(
        height: ResponsiveService.getAdaptiveSpacing(context, 8),
      ),
      DropdownButtonFormField<String?>(
        initialValue: _selectedSecondaryBranch,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: ResponsiveService.getAdaptivePadding(
            context,
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('None (single degree)'),
          ),
          ..._branches.where((branch) => branch != _selectedBranch).map(
            (branch) {
              final name = constants.branchCodeToName[branch] ?? branch;
              return DropdownMenuItem<String?>(
                value: branch,
                child: Text('$branch - $name'),
              );
            },
          ),
        ],
        onChanged: (String? newValue) {
          ResponsiveService.triggerSelectionFeedback(context);
          setState(() {
            _selectedSecondaryBranch = newValue;
          });
        },
        isExpanded: true,
      ),

      SizedBox(
        height: ResponsiveService.getAdaptiveSpacing(context, 16),
      ),

      Text(
        'Semester *',
        style: TextStyle(
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
          fontWeight: FontWeight.w500,
        ),
      ),
      SizedBox(
        height: ResponsiveService.getAdaptiveSpacing(context, 8),
      ),
      DropdownButtonFormField<String>(
        initialValue: _selectedSemester,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: ResponsiveService.getAdaptivePadding(
            context,
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
        ),
        items:
            _semesters.map((semester) {
              return DropdownMenuItem<String>(
                value: semester,
                child: Text('Semester $semester'),
              );
            }).toList(),
        onChanged: (String? newValue) {
          ResponsiveService.triggerSelectionFeedback(context);
          setState(() {
            _selectedSemester = newValue;
          });
        },
        isExpanded: true,
        hint: const Text('Select your semester'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.school,
            color: Theme.of(context).colorScheme.primary,
            size: ResponsiveService.getAdaptiveIconSize(context, 24),
          ),
          SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
          Expanded(
            child: Text(
              _choices == null ? 'Auto Load CDCs' : 'Pick your courses',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 20),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: ResponsiveService.getValue(
          context,
          mobile: MediaQuery.sizeOf(context).width - 32,
          tablet: 400,
          desktop: 350,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...(_choices == null ? _degreeFields() : _choiceFields()),

              if (isMobile) ...[
                SizedBox(
                  height: ResponsiveService.getAdaptiveSpacing(context, 20),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      ResponsiveService.triggerSelectionFeedback(context);
                      _back();
                    },
                    style: TextButton.styleFrom(
                      minimumSize: Size(
                        double.infinity,
                        ResponsiveService.getTouchTargetSize(context),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Text(_choices == null ? 'Cancel' : 'Back'),
                  ),
                ),
                SizedBox(
                  height: ResponsiveService.getAdaptiveSpacing(context, 12),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _canAdvance
                            ? () {
                              ResponsiveService.triggerMediumFeedback(context);
                              _advance();
                            }
                            : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      minimumSize: Size(
                        double.infinity,
                        ResponsiveService.getTouchTargetSize(context),
                      ),
                    ),
                    icon: _primaryIcon(
                      ResponsiveService.getAdaptiveIconSize(context, 16),
                    ),
                    label: const Text('Load CDCs'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions:
          isMobile
              ? null
              : [
                TextButton(
                  onPressed: _back,
                  child: Text(_choices == null ? 'Cancel' : 'Back'),
                ),
                FilledButton.icon(
                  onPressed: _canAdvance ? _advance : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: _primaryIcon(16),
                  label: const Text('Load CDCs'),
                ),
              ],
    );
  }
}
