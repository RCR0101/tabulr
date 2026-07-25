import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

/// Small shared pieces of the generator's constraints panel.
///
/// These were `_buildX()` methods on the generator's 2.6k-line `State`. As
/// methods they had no identity to the framework, so every one of them re-ran
/// whenever anything in the panel rebuilt. As `const`-constructible widgets
/// Flutter can skip the ones whose inputs are unchanged — and the three
/// avoidance lists, which were near-identical 56-line copies, collapse into one.

/// Section heading with an "Add" action, above a list of chips.
class ChipListSection extends StatelessWidget {
  const ChipListSection({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.chips,
    this.emptyHint,
    this.maxHeight = 80,
  });

  final String title;
  final String actionLabel;

  /// Null disables the action — the instructor lists use this to require a
  /// course selection first.
  final VoidCallback? onAction;

  final List<Widget> chips;

  /// Shown in place of the chip box when there is nothing yet AND the action is
  /// unavailable, explaining why.
  final String? emptyHint;

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: onAction,
              icon: Icon(
                  actionLabel == 'Rank' ? Icons.sort : Icons.add,
                  size: 16),
              label: Text(actionLabel, style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(spacing: 6, runSpacing: 4, children: chips),
            ),
          ),
        ] else if (emptyHint != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Text(
              emptyHint!,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// One removable entry in a [ChipListSection].
class RemovableChip extends StatelessWidget {
  const RemovableChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.tint,
  });

  final String label;
  final VoidCallback onRemove;

  /// Background tint. Defaults to the primary colour; the lab and instructor
  /// lists use the error colour to read as exclusions.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onRemove,
      backgroundColor: (tint ?? scheme.primary).withValues(alpha: 0.1),
      deleteIconColor: AppDesign.danger(context),
    );
  }
}

/// Advanced opt-in that hardens a soft intent into a hard filter. Deliberately
/// blunt about the consequence: a required constraint can return nothing.
class RequireToggle extends StatelessWidget {
  const RequireToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = value
        ? AppDesign.warning(context)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value
                    ? 'Required — may return no timetables'
                    : 'Require this (hard filter)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled row with a control on the right.
class ConstraintRow extends StatelessWidget {
  const ConstraintRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

/// A titled group of constraints, separated by a rule.
class ConstraintGroup extends StatelessWidget {
  const ConstraintGroup({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(width: 12),
            Expanded(
              child: Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}
