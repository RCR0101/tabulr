import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/auth_service.dart';
import 'package:timetable_maker/services/data/firebase_bootstrap_options.dart';

void main() {
  group('Firebase bootstrap options', () {
    const configured = FirebaseOptions(
      apiKey: 'key',
      appId: 'app',
      messagingSenderId: 'sender',
      projectId: 'project',
      authDomain: 'project.firebaseapp.com',
    );

    test('uses the same-origin auth domain on web', () {
      final resolved = resolveFirebaseOptions(
        configured,
        isWeb: true,
        authDomain: ' tabulr.net ',
        currentHost: 'TABULR.NET',
      );
      expect(resolved.authDomain, 'tabulr.net');
    });

    test('does not modify native, preview, or unconfigured builds', () {
      expect(
        resolveFirebaseOptions(
          configured,
          isWeb: false,
          authDomain: 'tabulr.net',
        ),
        same(configured),
      );
      expect(
        resolveFirebaseOptions(
          configured,
          isWeb: true,
          authDomain: 'tabulr.net',
          currentHost: 'preview.web.app',
        ),
        same(configured),
      );
      expect(
        resolveFirebaseOptions(configured, isWeb: true, authDomain: ''),
        same(configured),
      );
    });
  });

  test('campus user ids are derived only for supported BITS domains', () {
    expect(
      AuthService.deriveUserDocId('f20220001@hyderabad.bits-pilani.ac.in'),
      'f20220001H',
    );
    expect(
      AuthService.deriveUserDocId('f20220001@pilani.bits-pilani.ac.in'),
      'f20220001P',
    );
    expect(AuthService.deriveUserDocId('student@example.com'), isNull);
  });
}
