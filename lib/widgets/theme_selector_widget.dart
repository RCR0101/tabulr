import 'package:flutter/material.dart';
import '../services/theme_service.dart' as theme_service;
import '../services/user_settings_service.dart';
import '../services/responsive_service.dart';
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
                        DropdownButton<user_settings.ThemeMode>(
                          value: themeMode,
                          onChanged: (value) {
                            if (value != null) {
                              _userSettingsService.updateThemeMode(value);
                              _updateThemeServiceMode(value);
                            }
                          },
                          underline: Container(),
                          items: user_settings.ThemeMode.values.map((mode) {
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

                  return InkWell(
                    onTap: () async {
                      await _themeService.setTheme(theme);
                      await _userSettingsService.updateThemeVariant(theme);
                    },
                    borderRadius: BorderRadius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 12)),
                    child: Container(
                      constraints: BoxConstraints(
                        minHeight: ResponsiveService.getTouchTargetSize(context),
                      ),
                      child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: themeData.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected 
                              ? themeData.colorScheme.primary 
                              : themeData.colorScheme.outline,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: themeData.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _themeService.getThemeIcon(theme),
                            color: themeData.colorScheme.primary,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _themeService.getThemeName(theme),
                            style: TextStyle(
                              color: themeData.colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: themeData.colorScheme.primary,
                              size: 16,
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

  IconData _getThemeModeIcon(user_settings.ThemeMode mode) {
    switch (mode) {
      case user_settings.ThemeMode.light:
        return Icons.light_mode;
      case user_settings.ThemeMode.dark:
        return Icons.dark_mode;
      case user_settings.ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _getThemeModeName(user_settings.ThemeMode mode) {
    switch (mode) {
      case user_settings.ThemeMode.light:
        return 'Light Mode';
      case user_settings.ThemeMode.dark:
        return 'Dark Mode';
      case user_settings.ThemeMode.system:
        return 'System Mode';
    }
  }

  String _getThemeModeDescription(user_settings.ThemeMode mode) {
    switch (mode) {
      case user_settings.ThemeMode.light:
        return 'Always use light theme';
      case user_settings.ThemeMode.dark:
        return 'Always use dark theme';
      case user_settings.ThemeMode.system:
        return 'Follow system settings';
    }
  }

  void _updateThemeServiceMode(user_settings.ThemeMode mode) {
    switch (mode) {
      case user_settings.ThemeMode.light:
        _themeService.setThemeMode(ThemeMode.light);
        break;
      case user_settings.ThemeMode.dark:
        _themeService.setThemeMode(ThemeMode.dark);
        break;
      case user_settings.ThemeMode.system:
        _themeService.setThemeMode(ThemeMode.system);
        break;
    }
  }
}

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const ThemeSelectorDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            // Header with close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48), // For symmetry
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
            // Theme selector
            const Expanded(
              child: ThemeSelectorWidget(),
            ),
          ],
        ),
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
          case user_settings.ThemeMode.light:
            icon = Icons.light_mode;
            tooltip = 'Theme: Light Mode';
            break;
          case user_settings.ThemeMode.dark:
            icon = Icons.dark_mode;
            tooltip = 'Theme: Dark Mode';
            break;
          case user_settings.ThemeMode.system:
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
    
    return GestureDetector(
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
          child: Container(
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