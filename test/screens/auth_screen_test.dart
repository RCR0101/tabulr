import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/auth_screen.dart';
import 'package:timetable_maker/services/data/auth_service.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';

void main() {
  Future<void> pumpAuth(
    WidgetTester tester, {
    required Future<AuthSignInResult> Function() signIn,
    required Future<void> Function() guest,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeService().getLightThemeData(AppTheme.githubDark),
        home: AuthScreen(signInWithGoogle: signIn, continueAsGuest: guest),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('guest progress does not make Google appear to be signing in', (
    tester,
  ) async {
    final guest = Completer<void>();
    await pumpAuth(
      tester,
      signIn: () async => AuthSignInResult.signedIn,
      guest: () => guest.future,
    );

    await tester.tap(find.byKey(const ValueKey('guest-sign-in-button')));
    await tester.pump();

    expect(find.text('Opening Tabulr...'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Signing in...'), findsNothing);

    guest.complete();
    await tester.pumpAndSettle();
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Google progress leaves the guest action accurately labelled', (
    tester,
  ) async {
    final signIn = Completer<AuthSignInResult>();
    await pumpAuth(tester, signIn: () => signIn.future, guest: () async {});

    await tester.tap(find.byKey(const ValueKey('google-sign-in-button')));
    await tester.pump();

    expect(find.text('Signing in...'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.text('Opening Tabulr...'), findsNothing);

    signIn.complete(AuthSignInResult.signedIn);
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
