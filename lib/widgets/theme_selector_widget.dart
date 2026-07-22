import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../main.dart' show TimetableMakerApp;
import '../services/ui/theme_service.dart' as theme_service;
import '../services/data/user_settings_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/design_constants.dart';
import 'common/app_tappable.dart';
import '../models/user_settings.dart' as user_settings;

class ThemeSelectorWidget extends StatefulWidget {
  const ThemeSelectorWidget({super.key});

  @override
  State<ThemeSelectorWidget> createState() => _ThemeSelectorWidgetState();
}

class _ThemeSelectorWidgetState extends State<ThemeSelectorWidget> {
  final theme_service.ThemeService _themeService = theme_service.ThemeService();
  final UserSettingsService _userSettingsService = UserSettingsService();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_themeService, _userSettingsService]),
      builder: (context, child) {
        final themeMode = _userSettingsService.themeMode;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme Settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getThemeModeIcon(themeMode),
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getThemeModeName(themeMode),
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _getThemeModeDescription(themeMode),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        DropdownButton<user_settings.AppThemeMode>(
                          value: themeMode,
                          onChanged: (value) async {
                            if (value == null) return;
                            final controller = TimetableMakerApp.themeTransition;
                            final box = context.findRenderObject() as RenderBox?;
                            final origin = box != null
                                ? box.localToGlobal(Offset(box.size.width - 40, box.size.height / 2))
                                : Offset.zero;
                            if (controller != null && origin != Offset.zero) {
                              final revealFuture = controller.runReveal(origin);
                              _userSettingsService.updateThemeMode(value);
                              _updateThemeServiceMode(value);
                              await revealFuture;
                            } else {
                              _userSettingsService.updateThemeMode(value);
                              _updateThemeServiceMode(value);
                            }
                          },
                          underline: Container(),
                          items: user_settings.AppThemeMode.values.map((mode) {
                            return DropdownMenuItem(
                              value: mode,
                              child: Text(_getThemeModeName(mode)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: ResponsiveService.getAdaptivePadding(context, const EdgeInsets.symmetric(horizontal: 16.0)),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: ResponsiveService.getGridColumns(context, mobileColumns: 1, tabletColumns: 2, desktopColumns: 2),
                  mainAxisSpacing: ResponsiveService.getAdaptiveSpacing(context, 12),
                  crossAxisSpacing: ResponsiveService.getAdaptiveSpacing(context, 12),
                  childAspectRatio: ResponsiveService.getValue(context, mobile: 2.5, tablet: 1.8, desktop: 1.5),
                ),
                itemCount: theme_service.AppTheme.values.length,
                itemBuilder: (context, index) {
                  final theme = theme_service.AppTheme.values[index];
                  final themeData = _themeService.getThemeData(theme);
                  final isSelected = _themeService.currentTheme == theme;

                  final cs = themeData.colorScheme;
                  return Semantics(
                    button: true,
                    selected: isSelected,
                    label: '${_themeService.getThemeName(theme)} theme',
                    child: InkWell(
                    onTapDown: (details) async {
                      if (isSelected) return;
                      final origin = details.globalPosition;
                      final controller = TimetableMakerApp.themeTransition;
                      if (controller != null) {
                        final revealFuture = controller.runReveal(origin);
                        await _themeService.setTheme(theme);
                        await _userSettingsService.updateThemeVariant(theme);
                        await revealFuture;
                      } else {
                        await _themeService.setTheme(theme);
                        await _userSettingsService.updateThemeVariant(theme);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3),
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: 1)]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Color swatch row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ColorDot(color: cs.primary, size: 18),
                              const SizedBox(width: 6),
                              _ColorDot(color: cs.secondary, size: 18),
                              const SizedBox(width: 6),
                              _ColorDot(color: cs.tertiary, size: 18),
                              const SizedBox(width: 6),
                              _ColorDot(color: cs.surfaceContainerHighest, size: 18, border: cs.outline),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isSelected) ...[
                                Icon(Icons.check_circle, color: cs.primary, size: 14),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  _themeService.getThemeName(theme),
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Choose your theme mode (light, dark, or system), then select your preferred theme style.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getThemeModeIcon(user_settings.AppThemeMode mode) {
    switch (mode) {
      case user_settings.AppThemeMode.light:
        return Icons.light_mode;
      case user_settings.AppThemeMode.dark:
        return Icons.dark_mode;
      case user_settings.AppThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _getThemeModeName(user_settings.AppThemeMode mode) {
    switch (mode) {
      case user_settings.AppThemeMode.light:
        return 'Light Mode';
      case user_settings.AppThemeMode.dark:
        return 'Dark Mode';
      case user_settings.AppThemeMode.system:
        return 'System Mode';
    }
  }

  String _getThemeModeDescription(user_settings.AppThemeMode mode) {
    switch (mode) {
      case user_settings.AppThemeMode.light:
        return 'Always use light theme';
      case user_settings.AppThemeMode.dark:
        return 'Always use dark theme';
      case user_settings.AppThemeMode.system:
        return 'Follow system settings';
    }
  }

  void _updateThemeServiceMode(user_settings.AppThemeMode mode) {
    switch (mode) {
      case user_settings.AppThemeMode.light:
        _themeService.setThemeMode(ThemeMode.light);
        break;
      case user_settings.AppThemeMode.dark:
        _themeService.setThemeMode(ThemeMode.dark);
        break;
      case user_settings.AppThemeMode.system:
        _themeService.setThemeMode(ThemeMode.system);
        break;
    }
  }
}

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  static Future<void> show(BuildContext context) {
    if (ResponsiveService.isMobile(context)) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppDesign.glassBlur, sigmaY: AppDesign.glassBlur),
              child: Container(
                color: scheme.surface.withValues(alpha: 0.85),
                height: MediaQuery.of(ctx).size.height * 0.85,
                child: const ThemeSelectorDialog(),
              ),
            ),
          );
        },
      );
    }
    return showDialog<void>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppDesign.glassBlur / 2, sigmaY: AppDesign.glassBlur / 2),
        child: const ThemeSelectorDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    final scheme = Theme.of(context).colorScheme;

    final content = Column(
      children: [
        if (isMobile)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 48),
            Text(
              'Theme Settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const Divider(),
        const Expanded(
          child: ThemeSelectorWidget(),
        ),
      ],
    );

    if (isMobile) return content;

    return Dialog(
      backgroundColor: scheme.surface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: MediaQuery.sizeOf(context).height * 0.7,
        padding: const EdgeInsets.only(top: 8),
        child: content,
      ),
    );
  }
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = theme_service.ThemeService();
    final userSettingsService = UserSettingsService();
    
    return ListenableBuilder(
      listenable: Listenable.merge([themeService, userSettingsService]),
      builder: (context, child) {
        final themeMode = userSettingsService.themeMode;
        IconData icon;
        String tooltip;

        switch (themeMode) {
          case user_settings.AppThemeMode.light:
            icon = Icons.light_mode;
            tooltip = 'Theme: Light Mode';
            break;
          case user_settings.AppThemeMode.dark:
            icon = Icons.dark_mode;
            tooltip = 'Theme: Dark Mode';
            break;
          case user_settings.AppThemeMode.system:
            icon = Icons.brightness_auto;
            tooltip = 'Theme: System Mode';
            break;
        }

        return IconButton(
          onPressed: () => ThemeSelectorDialog.show(context),
          icon: Icon(icon, size: ResponsiveService.getAdaptiveIconSize(context, 24)),
          tooltip: '$tooltip (${themeService.getThemeName(themeService.currentTheme)})',
          iconSize: ResponsiveService.getTouchTargetSize(context),
          padding: EdgeInsets.all(ResponsiveService.getValue(context, mobile: 12.0, tablet: 8.0, desktop: 8.0)),
        );
      },
    );
  }
}

class ThemePreviewCard extends StatelessWidget {
  final theme_service.AppTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  const ThemePreviewCard({
    super.key,
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeService = theme_service.ThemeService();
    final themeData = themeService.getThemeData(theme);

    return AppTappable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? themeData.colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 120,
            child: Column(
              children: [
                // Theme preview header
                Container(
                  height: 30,
                  color: themeData.scaffoldBackgroundColor,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: themeData.colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: themeData.colorScheme.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: themeData.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
                // Theme preview content
                Expanded(
                  child: Container(
                    color: themeData.cardColor,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              themeService.getThemeIcon(theme),
                              color: themeData.colorScheme.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                themeService.getThemeName(theme),
                                style: TextStyle(
                                  color: themeData.colorScheme.onSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check,
                                color: themeData.colorScheme.primary,
                                size: 14,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: themeData.colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 20,
                              height: 8,
                              decoration: BoxDecoration(
                                color: themeData.colorScheme.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 15,
                              height: 8,
                              decoration: BoxDecoration(
                                color: themeData.colorScheme.outline,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 15,
                              height: 8,
                              decoration: BoxDecoration(
                                color: themeData.colorScheme.outline,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 25,
                              height: 8,
                              decoration: BoxDecoration(
                                color: themeData.colorScheme.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  final Color? border;

  const _ColorDot({required this.color, required this.size, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border != null
            ? Border.all(color: border!.withValues(alpha: 0.3), width: 1)
            : null,
      ),
    );
  }
}