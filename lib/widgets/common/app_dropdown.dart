import 'package:flutter/material.dart';

/// A dropdown in a rounded, bordered box.
///
/// `DropdownButton` paints its own focus highlight as a full-bleed **square**
/// rectangle behind the button. Dropped into a rounded container — which is how
/// every one of these is styled — that highlight pokes out past the corners and
/// reads as a stray grey block rather than as "this control has focus".
///
/// Here the box itself is the focus indicator: the button's own highlight is
/// suppressed and the border it already draws thickens and picks up the primary
/// colour instead. The affordance is kept (it still shows keyboard focus) and it
/// is exactly the size and shape of the control, because it *is* the control.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.width,
    this.height = 34,
    this.isExpanded = false,
    this.icon,
    this.textStyle,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;

  /// Null sizes the box to its content.
  final double? width;
  final double height;

  final bool isExpanded;
  final Widget? icon;
  final TextStyle? textStyle;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;

    // Observes the button's focus rather than taking it: hasFocus is true when
    // any descendant holds primary focus, which is what lets the border below
    // stand in for the highlight the button itself no longer draws.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (mounted && hasFocus != _focused) {
          setState(() => _focused = hasFocus);
        }
      },
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: _focused && enabled
            ? scheme.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        border: Border.all(
          color: _focused && enabled ? scheme.primary : scheme.outlineVariant,
          width: _focused && enabled ? 1.6 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: widget.value,
          hint: widget.hint,
          isDense: true,
          isExpanded: widget.isExpanded,
          icon: widget.icon,
          // Suppressed in favour of the border above — this is the square
          // rectangle that looked wrong inside the rounded box.
          focusColor: Colors.transparent,
          // Rounds the popup menu to match the control it opens from.
          borderRadius: BorderRadius.circular(10),
          style: widget.textStyle ??
              TextStyle(fontSize: 13, color: scheme.onSurface),
          items: widget.items,
          onChanged: widget.onChanged,
        ),
      ),
      ),
    );
  }
}
