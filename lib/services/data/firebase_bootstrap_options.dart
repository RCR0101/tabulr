import 'package:firebase_core/firebase_core.dart';

/// Applies deployment-only Firebase overrides without modifying the generated
/// `firebase_options.dart` file that CI injects.
FirebaseOptions resolveFirebaseOptions(
  FirebaseOptions configured, {
  required bool isWeb,
  String authDomain = const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
  String? currentHost,
}) {
  final normalizedDomain = authDomain.trim().toLowerCase();
  if (!isWeb || normalizedDomain.isEmpty) return configured;

  // A custom auth domain only fixes redirect storage when it is genuinely
  // same-origin. Do not leak preview or localhost auth state through production.
  final normalizedHost = (currentHost ?? Uri.base.host).trim().toLowerCase();
  if (normalizedHost != normalizedDomain) return configured;
  return configured.copyWith(authDomain: normalizedDomain);
}
