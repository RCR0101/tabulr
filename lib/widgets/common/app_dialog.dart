import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';
import 'app_button.dart';

class AppDialog {
  AppDialog._();

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
    IconData? icon,
    Color? iconColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        shape: AppDesign.dialogShape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: AppDesign.dialogPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppDesign.spacingSm),
                        decoration: BoxDecoration(
                          color: (iconColor ?? scheme.primary)
                              .withValues(alpha: 0.1),
                          borderRadius: AppDesign.borderRadiusSm,
                        ),
                        child: Icon(icon,
                            size: 20, color: iconColor ?? scheme.primary),
                      ),
                      const SizedBox(width: AppDesign.spacingSm + 4),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesign.spacingMd),
                content,
                if (actions != null) ...[
                  const SizedBox(height: AppDesign.spacingLg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions
                        .expand(
                            (a) => [a, const SizedBox(width: AppDesign.spacingSm)])
                        .toList()
                      ..removeLast(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDangerous = false,
    IconData? icon,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      icon: icon ?? (isDangerous ? Icons.warning_amber_rounded : null),
      iconColor: isDangerous
          ? Theme.of(context).colorScheme.error
          : null,
      content: Text(message),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: isDangerous ? AppButtonVariant.danger : AppButtonVariant.primary,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    return result ?? false;
  }

  static Future<String?> input({
    required BuildContext context,
    required String title,
    String? initialValue,
    String? hint,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    IconData? icon,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await show<String>(
      context: context,
      title: title,
      icon: icon,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: AppDesign.inputDecoration(
          context,
          label: hint ?? title,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.of(context).pop(null),
        ),
        AppButton(
          label: confirmLabel,
          onTap: () => Navigator.of(context).pop(controller.text),
        ),
      ],
    );
    controller.dispose();
    return result;
  }
}
