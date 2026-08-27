import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/auth_service.dart';

void main() {
  group('Google popup decisions', () {
    test('user cancellation never falls back to redirect', () {
      for (final code in [
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-cancelled',
      ]) {
        expect(AuthService.isPopupCancellationCode(code), isTrue);
        expect(AuthService.shouldUseRedirectForPopupCode(code), isFalse);
      }
    });

    test('only popup capability failures use redirect', () {
      for (final code in [
        'popup-blocked',
        'operation-not-supported-in-this-environment',
        'web-storage-unsupported',
      ]) {
        expect(AuthService.shouldUseRedirectForPopupCode(code), isTrue);
        expect(AuthService.isPopupCancellationCode(code), isFalse);
      }

      expect(
        AuthService.shouldUseRedirectForPopupCode('network-request-failed'),
        isFalse,
      );
      expect(
        AuthService.shouldUseRedirectForPopupCode('unauthorized-domain'),
        isFalse,
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
