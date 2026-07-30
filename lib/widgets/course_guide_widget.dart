import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'common/empty_state_widget.dart';
import '../services/data/course_guide_service.dart';
import '../services/data/courses_master_service.dart';
import '../services/data/branch_structure_service.dart';
import '../services/data/profile_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/branch_constants.dart' as constants;
import '../utils/design_constants.dart';

class CourseGuideWidget extends StatefulWidget {
  const CourseGuideWidget({super.key});

  @override
  State<CourseGuideWidget> createState() => _CourseGuideWidgetState();
}

class _CourseGuideWidgetState extends State<CourseGuideWidget> {
  final CourseGuideService _courseGuideService = CourseGuideService();
  final BranchStructureService _branchService = BranchStructureService();

  List<String> _availableBranches = [];
  String? _selectedPrimaryBranch;
  String? _selectedSecondaryBranch;
  String? _selectedSemester;

  /// Whether the second-branch picker is on screen. Hidden by default because
  /// most students are single degree, and a dropdown they must ignore is one
  /// more thing between them and their courses.
  bool _dualDegree = false;

  Map<String, List<CourseGuideSlot>> _cdcData = {};
  bool _isLoading = true;
  bool _isSearching = false;
  String? _error;
  String? _validationError;

  /// Guards against an earlier, slower load overwriting a later one when the
  /// student changes branch or semester twice in quick succession.
  int _loadSeq = 0;

  final List<String> _semesterOptions = SemesterConstants.yearsOneToFour;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  /// Pre-selects the student's saved defaults where they're valid options, so
  /// the guide opens on their own courses. Everything stays editable.
  void _prefillFromProfile(List<String> branches) {
    final profile = ProfileService().cached;
    if (profile.primaryBranch != null &&
        branches.contains(profile.primaryBranch)) {
      _selectedPrimaryBranch = profile.primaryBranch;
    }
    // The secondary dropdown excludes the primary, so never pre-fill it to the
    // same branch.
    if (profile.secondaryBranch != null &&
        profile.secondaryBranch != _selectedPrimaryBranch &&
        branches.contains(profile.secondaryBranch)) {
      _selectedSecondaryBranch = profile.secondaryBranch;
      _dualDegree = true;
    }
    if (profile.currentSemester != null &&
        _semesterOptions.contains(profile.currentSemester)) {
      _selectedSemester = profile.currentSemester;
    }
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await _branchService.getAvailableBranches();
      if (!mounted) return;
      setState(() {
        _availableBranches = branches;
        _isLoading = false;
        _prefillFromProfile(branches);
      });
      // A prefilled branch is an answerable question — don't make them press a
      // button to ask it.
      if (_selectedPrimaryBranch != null) _loadCDCs();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load branches: $e';
        _isLoading = false;
      });
    }
  }

  bool get _hasDualBranch =>
      _selectedPrimaryBranch != null && _selectedSecondaryBranch != null;

  bool get _isValidDualBranch {
    if (!_hasDualBranch) return true;
    return constants.isMscBranch(_selectedPrimaryBranch!) &&
        constants.isBeBranch(_selectedSecondaryBranch!);
  }

  Future<void> _loadCDCs() async {
    if (_selectedPrimaryBranch == null) {
      setState(() {
        _cdcData = {};
        _validationError = null;
      });
      return;
    }

    if (_hasDualBranch && !_isValidDualBranch) {
      setState(() {
        _cdcData = {};
        _validationError =
            'A dual degree is an MSc (B-codes) plus a BE (A-codes). Swap the two, or clear the second branch.';
      });
      return;
    }

    final seq = ++_loadSeq;
    setState(() {
      _isSearching = true;
      _validationError = null;
      _error = null;
    });

    try {
      final data = await _courseGuideService.getCDCsForDegree(
        _selectedPrimaryBranch!,
        _selectedSecondaryBranch,
        semester: _selectedSemester,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _cdcData = data;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = 'Failed to load CDCs: $e';
        _cdcData = {};
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _availableBranches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: AppDesign.muted(context)),
            const SizedBox(height: AppDesign.spacingMd),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: AppDesign.spacingMd),
            FilledButton(onPressed: _loadBranches, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(),
        const SizedBox(height: AppDesign.spacingSm),
        Expanded(child: _buildResults()),
      ],
    );
  }

  // ── Filters ────────────────────────────────────────────────────────────────

  Widget _buildFilters() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedPrimaryBranch,
            isExpanded: true,
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Your branch',
              hint: 'Select a branch',
              prefixIcon:
                  const Icon(Icons.school_rounded, size: AppDesign.iconSizeMd),
            ),
            items: _availableBranches
                .map((code) => DropdownMenuItem(
                      value: code,
                      child: Text(
                        '$code · ${constants.branchCodeToName[code] ?? code}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedPrimaryBranch = v;
                if (_selectedSecondaryBranch == v) {
                  _selectedSecondaryBranch = null;
                }
              });
              _loadCDCs();
            },
          ),
          if (_dualDegree) ...[
            const SizedBox(height: AppDesign.spacingSm + 4),
            DropdownButtonFormField<String>(
              initialValue: _selectedSecondaryBranch,
              isExpanded: true,
              decoration: AppDesign.inputDecoration(
                context,
                label: 'Second branch',
                hint: 'Select a branch',
                prefixIcon: const Icon(Icons.school_outlined,
                    size: AppDesign.iconSizeMd),
                suffixIcon: IconButton(
                  tooltip: 'Not a dual degree',
                  icon: const Icon(Icons.close_rounded,
                      size: AppDesign.iconSizeSm),
                  onPressed: () {
                    setState(() {
                      _dualDegree = false;
                      _selectedSecondaryBranch = null;
                      _validationError = null;
                    });
                    _loadCDCs();
                  },
                ),
              ),
              items: _availableBranches
                  .where((c) => c != _selectedPrimaryBranch)
                  .map((code) => DropdownMenuItem(
                        value: code,
                        child: Text(
                          '$code · ${constants.branchCodeToName[code] ?? code}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedSecondaryBranch = v);
                _loadCDCs();
              },
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _dualDegree = true),
                icon: const Icon(Icons.add_rounded, size: AppDesign.iconSizeSm),
                label: const Text('I have a second branch (dual degree)'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDesign.spacingSm),
                  minimumSize: Size(0, ResponsiveService.getTouchTargetSize(context)),
                ),
              ),
            ),
          if (_validationError != null) ...[
            const SizedBox(height: AppDesign.spacingSm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: AppDesign.iconSizeSm, color: scheme.error),
                const SizedBox(width: AppDesign.spacingSm),
                Expanded(
                  child: Text(_validationError!,
                      style: TextStyle(color: scheme.error, fontSize: 13)),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppDesign.spacingSm + 4),
          _buildSemesterChips(),
        ],
      ),
    );
  }

  /// Year/semester as a chip row rather than a dropdown: there are only nine
  /// choices, and this way the whole degree is visible and one tap away.
  Widget _buildSemesterChips() {
    final scheme = Theme.of(context).colorScheme;

    Widget chip(String? value, String label) {
      final selected = _selectedSemester == value;
      return Padding(
        padding: const EdgeInsets.only(right: AppDesign.spacingSm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
          selectedColor: scheme.primary,
          side: BorderSide(
            color: selected
                ? Colors.transparent
                : scheme.outline.withValues(alpha: 0.4),
          ),
          onSelected: (_) {
            if (selected) return;
            setState(() => _selectedSemester = value);
            _loadCDCs();
          },
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(null, 'All years'),
          for (final sem in _semesterOptions)
            chip(sem, 'Year ${sem.split('-')[0]}-${sem.split('-')[1]}'),
        ],
      ),
    );
  }

  // ── Results ────────────────────────────────────────────────────────────────

  Widget _buildResults() {
    if (_isSearching && _cdcData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline_rounded,
        title: _error!,
      );
    }

    if (_selectedPrimaryBranch == null) {
      return const EmptyStateWidget(
        icon: Icons.school_outlined,
        title: 'Pick your branch',
        subtitle:
            'The guide lists the core courses (CDCs) your degree requires, year by year.',
      );
    }

    final semesters = _cdcData.keys.where((k) => _cdcData[k]!.isNotEmpty).toList()
      ..sort();
    if (semesters.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: _selectedSemester == null
            ? 'No core courses listed for this branch yet'
            : 'Nothing listed for year $_selectedSemester',
        subtitle: _selectedSemester == null
            ? null
            : 'Try another year, or "All years" to see the whole degree.',
      );
    }

    return Opacity(
      // A reload keeps the old list on screen rather than flashing a spinner —
      // dimmed so it's clear the numbers are about to change.
      opacity: _isSearching ? 0.5 : 1,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingSm),
        itemCount: semesters.length,
        itemBuilder: (context, i) => CourseGuideSemesterCard(
          semester: semesters[i],
          slots: _cdcData[semesters[i]]!,
          // One semester on screen is the answer itself; eight is a menu.
          initiallyExpanded: semesters.length == 1,
        ),
      ),
    );
  }
}

/// One year-semester of the guide: a header that summarises the term, and its
/// courses.
///
/// Split out from [CourseGuideWidget] so the layout can be rendered from a
/// preview test without Firestore — see `test/goldens/course_guide_preview_test.dart`.
class CourseGuideSemesterCard extends StatelessWidget {
  const CourseGuideSemesterCard({
    super.key,
    required this.semester,
    required this.slots,
    this.initiallyExpanded = false,
  });

  final String semester;
  final List<CourseGuideSlot> slots;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final parts = semester.split('-');
    final label = parts.length == 2
        ? 'Year ${parts[0]} · Semester ${parts[1]}'
        : semester;

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm + 4),
      decoration: AppDesign.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The tile's own divider draws a second line over the header border.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // ExpansionTile's header is a ListTile, which paints its ink splash on
        // the nearest Material — without this the card's own decoration is that
        // ancestor and swallows the tap feedback (Flutter asserts on it).
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
              horizontal: AppDesign.spacingMd, vertical: AppDesign.spacingXs),
          childrenPadding: EdgeInsets.zero,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              // A choice is one course to take, not two, so it counts once.
              '${slots.length} course${slots.length == 1 ? '' : 's'} · ${_unitsLabel(slots)} units',
              style: TextStyle(
                  fontSize: 12.5, color: AppDesign.muted(context)),
            ),
          ),
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppDesign.dividerColor(context)),
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < slots.length; i++)
                      _SlotRow(
                        slot: slots[i],
                        banded: i.isOdd,
                        isLast: i == slots.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Total units for the term. A choice contributes the one course the student
  /// will take — usually a fixed number, but shown as a range when the
  /// alternatives don't carry the same credit.
  static String _unitsLabel(List<CourseGuideSlot> slots) {
    var low = 0.0;
    var high = 0.0;
    for (final slot in slots) {
      final values = slot.options.map((o) => o.credits).toList()..sort();
      low += values.first;
      high += values.last;
    }
    return low == high
        ? _credits(low)
        : '${_credits(low)}–${_credits(high)}';
  }

  static String _credits(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

/// One requirement. A plain course is a single line; a choice is the same line
/// repeated under a "take one of these" banner, so the block can never be read
/// as "take both".
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.banded,
    required this.isLast,
  });

  final CourseGuideSlot slot;
  final bool banded;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        // Choices get a hue of their own, not just a lighter grey — the
        // difference has to survive both themes and colour blindness, and the
        // banner carries the actual meaning.
        color: slot.isChoice
            ? scheme.tertiary.withValues(alpha: 0.11)
            : banded
                ? scheme.onSurface.withValues(alpha: 0.03)
                : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppDesign.dividerColor(context))),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingMd, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slot.isChoice) ...[
            Row(
              children: [
                Icon(Icons.alt_route_rounded,
                    size: 15, color: scheme.tertiary),
                const SizedBox(width: AppDesign.spacingXs + 2),
                Text(
                  'Take any one of these',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: scheme.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesign.spacingSm),
          ],
          for (var i = 0; i < slot.options.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text('or',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppDesign.muted(context),
                    )),
              ),
            _optionLine(context, slot.options[i]),
          ],
        ],
      ),
    );
  }

  Widget _optionLine(BuildContext context, CourseGuideEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final name = entry.name.isNotEmpty
        ? entry.name
        : CoursesMasterService().getTitle(entry.code);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // Fixed so codes line up down the column — that is how a student
          // scans for one. Every code is `XXX Fnnn`-shaped, so it fits.
          width: 92,
          child: Text(
            entry.code,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: AppDesign.spacingSm),
        Expanded(
          // Wrapped, never ellipsised: the title is how a student recognises
          // the course.
          child: Text(
            name.isEmpty ? '—' : name,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
            ),
          ),
        ),
        const SizedBox(width: AppDesign.spacingSm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: AppDesign.borderRadiusXs,
          ),
          child: Text(
            '${CourseGuideSemesterCard._credits(entry.credits)}'
            '${entry.isInCreditHours ? 'CH' : 'U'}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
