import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';
import 'package:timetable_maker/utils/design_constants.dart';
import 'package:timetable_maker/widgets/common/app_button.dart';
import 'package:timetable_maker/widgets/common/app_dropdown.dart';
import 'package:timetable_maker/widgets/common/app_search_field.dart';
import 'package:timetable_maker/widgets/common/empty_state_widget.dart';
import 'package:timetable_maker/widgets/common/inline_error_card.dart';

import '../helpers/preview_harness.dart';

/// The same components under the sharpest and roundest theme presets, so the
/// per-theme geometry can be seen to reach every corner. Writing the PNG is
/// the point; there is nothing asserted here.
void main() {
  setUpAll(loadPreviewFont);

  final presets = <(String, AppTheme)>[
    ('sharp', AppTheme.amoledDark),
    ('round', AppTheme.catppuccinDark),
  ];

  for (final (name, theme) in presets) {
    testWidgets('theme shapes — $name', (tester) async {
      usePreviewSurface(tester, const Size(1100, 1500));
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeService().getLightThemeData(theme),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final geometry = ThemeGeometry.of(context);
              final scheme = Theme.of(context).colorScheme;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${theme.displayName} · card ${geometry.cardRadius.toInt()} · '
                    'button ${geometry.buttonRadius.toInt()} · '
                    'input ${geometry.inputRadius.toInt()} · '
                    'chip ${geometry.chipRadius.toInt()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: AppDesign.cardBorderRadius(context),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: AppDesign.innerBorderRadius(context),
                          ),
                          child: Icon(Icons.school_rounded, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('A card with an inner accent')),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: AppDesign.chipBorderRadius(context),
                          ),
                          child: const Text('chip'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      AppButton(label: 'Primary', onTap: () {}),
                      const SizedBox(width: 12),
                      AppButton(label: 'Secondary', variant: AppButtonVariant.secondary, onTap: () {}),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppSearchField(controller: controller, hint: 'Search courses'),
                  const SizedBox(height: 16),
                  AppDropdown<String>(
                    value: 'L1',
                    items: const [
                      DropdownMenuItem(value: 'L1', child: Text('L1 · Dr. A Sharma')),
                      DropdownMenuItem(value: 'L2', child: Text('L2 · Dr. B Rao')),
                    ],
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  const InlineErrorCard(message: 'Something went wrong loading this.'),
                  const SizedBox(height: 16),
                  EmptyStateWidget(
                    icon: Icons.event_busy_rounded,
                    title: 'No timetables yet',
                    subtitle: 'Build one from the catalogue.',
                    actionLabel: 'New timetable',
                    onAction: () {},
                  ),
                ],
              );
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await capturePreview(tester, 'theme_shapes_$name');
    });
  }
}
