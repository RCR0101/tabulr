import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

/// A standardized search text field: a leading search icon, the app's standard
/// input decoration, and an optional clear button when [controller] has text.
///
/// Use instead of hand-rolled search `TextField`s so search inputs look and
/// behave consistently across screens.
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// Custom clear handler for the trailing clear button. When null, the button
  /// clears the controller and fires [onChanged] with an empty string.
  final VoidCallback? onClear;

  /// Compact variant (smaller radius/padding) for toolbars and inline forms.
  final bool dense;

  const AppSearchField({
    super.key,
    required this.controller,
    this.hint = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.onClear,
    this.dense = false,
  });

  void _clear() {
    if (onClear != null) {
      onClear!();
    } else {
      controller.clear();
      onChanged?.call('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: dense ? 13 : 14),
          decoration: AppDesign.inputDecoration(
            context,
            hint: hint,
            dense: dense,
            prefixIcon: Icon(Icons.search_rounded, size: AppDesign.iconSizeMd),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: AppDesign.iconSizeMd),
                    tooltip: 'Clear',
                    onPressed: _clear,
                  ),
          ),
        );
      },
    );
  }
}
