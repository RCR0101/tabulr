import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../services/ui/responsive_service.dart';
import '../../utils/design_constants.dart';
import 'app_button.dart';

class AppDialog {
  AppDialog._();

  static Future<T?> adaptive<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
    IconData? icon,
    Color? iconColor,
  }) {
    if (ResponsiveService.isMobile(context)) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppDesign.glassBlur, sigmaY: AppDesign.glassBlur),
              child: Container(
                color: scheme.surface.withValues(alpha: 0.85),
                child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppDesign.spacingSm),
                          decoration: BoxDecoration(
                            color: (iconColor ?? scheme.primary).withValues(alpha: 0.1),
                            borderRadius: AppDesign.borderRadiusSm,
                          ),
                          child: Icon(icon, size: 20, color: iconColor ?? scheme.primary),
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
                          .expand((a) => [a, const SizedBox(width: AppDesign.spacingSm)])
                          .toList()
                        ..removeLast(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ),
          ),
          );
        },
      );
    }
    return show<T>(
      context: context,
      title: title,
      content: content,
      actions: actions,
      icon: icon,
      iconColor: iconColor,
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
    IconData? icon,
    Color? iconColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveService.isMobile(context);
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        shape: AppDesign.dialogShape,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isMobile ? MediaQuery.sizeOf(context).width * 0.92 : AppDesign.maxDialogWidth,
          ),
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
    final result = await adaptive<bool>(
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
    final result = await adaptive<String>(
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
