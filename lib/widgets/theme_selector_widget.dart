import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/user_settings.dart' as user_settings;
import '../services/ui/responsive_service.dart';
import '../services/ui/theme_preferences_controller.dart';
import '../services/ui/theme_service.dart';
import '../utils/design_constants.dart';

class ThemeSelectorWidget extends StatelessWidget {
  const ThemeSelectorWidget({super.key});

  user_settings.AppThemeMode _settingsMode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => user_settings.AppThemeMode.light,
    ThemeMode.dark => user_settings.AppThemeMode.dark,
    ThemeMode.system => user_settings.AppThemeMode.system,
  };

  String _modeDescription(user_settings.AppThemeMode mode) => switch (mode) {
    user_settings.AppThemeMode.light => 'Always use the light palette',
    user_settings.AppThemeMode.dark => 'Always use the dark palette',
    user_settings.AppThemeMode.system => 'Match this device automatically',
  };

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();
    final preferences = ThemePreferencesController();

    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        final mode = _settingsMode(themeService.currentThemeMode);
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final effectiveBrightness = switch (mode) {
          user_settings.AppThemeMode.light => Brightness.light,
          user_settings.AppThemeMode.dark => Brightness.dark,
          user_settings.AppThemeMode.system => platformBrightness,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.spacingMd,
                AppDesign.spacingSm,
                AppDesign.spacingMd,
                AppDesign.spacingMd,
              ),
              child: _ModeSelector(
                mode: mode,
                description: _modeDescription(mode),
                onChanged: preferences.setThemeMode,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 560 ? 2 : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppDesign.spacingMd,
                      0,
                      AppDesign.spacingMd,
                      AppDesign.spacingLg,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppDesign.spacingMd,
                      crossAxisSpacing: AppDesign.spacingMd,
                      mainAxisExtent: 174,
                    ),
                    itemCount: AppTheme.values.length,
                    itemBuilder: (context, index) {
                      final theme = AppTheme.values[index];
                      final themeData = themeService.getThemeData(
                        theme,
                        platformBrightness: platformBrightness,
                      );
                      return ThemePreviewCard(
                        key: ValueKey('theme-preview-${theme.name}'),
                        theme: theme,
                        themeData: themeData,
                        effectiveBrightness: effectiveBrightness,
                        isSelected: themeService.currentTheme == theme,
                        onTap: () => preferences.setTheme(theme),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.description,
    required this.onChanged,
  });

  final user_settings.AppThemeMode mode;
  final String description;
  final ValueChanged<user_settings.AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingSm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: AppDesign.cardBorderRadius(context),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<user_settings.AppThemeMode>(
              key: const ValueKey('theme-mode-selector'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: user_settings.AppThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 17),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: user_settings.AppThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 17),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: user_settings.AppThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined, size: 17),
                  label: Text('System'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => onChanged(selection.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 520) ...[
            const SizedBox(width: AppDesign.spacingMd),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  static Future<void> show(BuildContext context) {
    if (ResponsiveService.isMobile(context)) {
      final dialogRadius = ThemeGeometry.of(context).dialogRadius;
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(dialogRadius),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppDesign.glassBlur,
                sigmaY: AppDesign.glassBlur,
              ),
              child: Container(
                color: scheme.surface.withValues(alpha: 0.94),
                height: MediaQuery.sizeOf(ctx).height * 0.88,
                child: const ThemeSelectorDialog(),
              ),
            ),
          );
        },
      );
    }

    return showDialog<void>(
      context: context,
      builder: (context) => const ThemeSelectorDialog(),
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
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: AppDesign.buttonBorderRadius(context),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  color: scheme.onPrimaryContainer,
                  size: 19,
                ),
              ),
              const SizedBox(width: AppDesign.spacingSm + 4),
              Expanded(
                child: Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        const Expanded(child: ThemeSelectorWidget()),
      ],
    );

    if (isMobile) return SafeArea(top: false, child: content);

    return Dialog(
      backgroundColor: scheme.surface,
      shape: AppDesign.dialogShape(context),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: content,
      ),
    );
  }
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        final (icon, modeName) = switch (themeService.currentThemeMode) {
          ThemeMode.light => (Icons.light_mode_outlined, 'Light'),
          ThemeMode.dark => (Icons.dark_mode_outlined, 'Dark'),
          ThemeMode.system => (Icons.brightness_auto_outlined, 'System'),
        };
        return IconButton(
          onPressed: () => ThemeSelectorDialog.show(context),
          icon: Icon(
            icon,
            size: ResponsiveService.getAdaptiveIconSize(context, 24),
          ),
          tooltip:
              'Appearance: $modeName, '
              '${themeService.currentTheme.displayName}',
          iconSize: ResponsiveService.getTouchTargetSize(context),
          padding: EdgeInsets.all(
            ResponsiveService.getValue(
              context,
              mobile: 12,
              tablet: 8,
              desktop: 8,
            ),
          ),
        );
      },
    );
  }
}

class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.theme,
    required this.themeData,
    required this.effectiveBrightness,
    required this.isSelected,
    required this.onTap,
  });

  final AppTheme theme;
  final ThemeData themeData;
  final Brightness effectiveBrightness;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outerScheme = Theme.of(context).colorScheme;
    final geometry =
        themeData.extension<ThemeGeometry>() ?? const ThemeGeometry();
    final radius = BorderRadius.circular(geometry.cardRadius + 2);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${theme.displayName} theme',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSelected ? null : onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: AppDesign.motionFast,
            curve: AppDesign.curveStandard,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color:
                    isSelected
                        ? outerScheme.primary
                        : outerScheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
              boxShadow:
                  isSelected
                      ? [
                        BoxShadow(
                          color: outerScheme.primary.withValues(alpha: 0.13),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                      : null,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Theme(
                data: themeData,
                child: Builder(
                  builder:
                      (previewContext) => _ThemePreviewContent(
                        theme: theme,
                        brightness: effectiveBrightness,
                        selected: isSelected,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewContent extends StatelessWidget {
  const _ThemePreviewContent({
    required this.theme,
    required this.brightness,
    required this.selected,
  });

  final AppTheme theme;
  final Brightness brightness;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final scheme = themeData.colorScheme;
    final geometry = ThemeGeometry.of(context);
    final accents =
        themeData.extension<TimetableTheme>()?.accents ??
        [scheme.primary, scheme.secondary, scheme.tertiary];

    return ColoredBox(
      color: themeData.scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            color: scheme.surface,
            child: Row(
              children: [
                Icon(theme.icon, size: 16, color: scheme.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    theme.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: themeData.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  brightness == Brightness.dark ? 'DARK' : 'LIGHT',
                  key: ValueKey('theme-preview-brightness-${theme.name}'),
                  style: themeData.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 9,
                    letterSpacing: 0.7,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_circle, color: scheme.primary, size: 15),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(
                          geometry.cardRadius,
                        ),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          _PreviewClass(
                            label: 'M',
                            color: accents[0 % accents.length],
                            widthFactor: 0.82,
                          ),
                          const SizedBox(height: 5),
                          _PreviewClass(
                            label: 'T',
                            color: accents[1 % accents.length],
                            widthFactor: 0.62,
                          ),
                          const SizedBox(height: 5),
                          _PreviewClass(
                            label: 'W',
                            color: accents[2 % accents.length],
                            widthFactor: 0.74,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        Container(
                          height: 29,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              geometry.inputRadius,
                            ),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            'Search courses',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: themeData.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(
                              geometry.buttonRadius,
                            ),
                          ),
                          child: Text(
                            'Generate',
                            style: themeData.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewClass extends StatelessWidget {
  const _PreviewClass({
    required this.label,
    required this.color,
    required this.widthFactor,
  });

  final String label;
  final Color color;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Row(
        children: [
          SizedBox(
            width: 11,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 8,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
