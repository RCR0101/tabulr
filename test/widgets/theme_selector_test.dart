import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';
import 'package:timetable_maker/utils/design_constants.dart';
import 'package:timetable_maker/widgets/theme_selector_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('system mode previews the device brightness without overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await ThemeService().setThemeMode(ThemeMode.system);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeService().getLightThemeData(AppTheme.githubDark),
        home: const Scaffold(body: ThemeSelectorWidget()),
      ),
    );
    await tester.pumpAndSettle();

    final brightness = tester.widget<Text>(
      find.byKey(const ValueKey('theme-preview-brightness-githubDark')),
    );
    expect(brightness.data, 'LIGHT');
    expect(find.byKey(const ValueKey('theme-mode-selector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared card geometry follows the selected palette', (
    tester,
  ) async {
    BorderRadiusGeometry? githubRadius;
    BorderRadiusGeometry? draculaRadius;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeService().getLightThemeData(AppTheme.githubDark),
        home: Builder(
          builder: (context) {
            githubRadius = AppDesign.cardDecoration(context).borderRadius;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeService().getLightThemeData(AppTheme.draculaDark),
        home: Builder(
          builder: (context) {
            draculaRadius = AppDesign.cardDecoration(context).borderRadius;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(githubRadius, BorderRadius.circular(6));
    expect(draculaRadius, BorderRadius.circular(14));
    expect(githubRadius, isNot(draculaRadius));
  });
}
