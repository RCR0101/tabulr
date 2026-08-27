import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/painting.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../constants/app_constants.dart';
import 'config_service.dart';
import 'user_settings_service.dart';
import '../ui/secure_logger.dart';
import '../ui/tutorial_service.dart';
import '../ui/remote_log_sink.dart';

enum AuthSignInResult { signedIn, cancelled, redirecting }

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Resolved per use, not in a field. This singleton gets constructed by
  /// whatever touches it first — including a widget mid-build — and
  /// `FirebaseAuth.instance` throws when no app is initialised, taking that
  /// widget down with it.
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  final ConfigService _config = ConfigService();
  late final GoogleSignIn _googleSignIn;

  // Session-only guest mode tracker (not persisted)
  bool _isCurrentlyGuest = false;

  // Stream controller for auth state changes including guest mode
  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();

  // Feeds the current app-user id to the remote log sink; subscribed once in
  // initialize() so login/logout keep shipped logs attributable.
  StreamSubscription<User?>? _authSub;
  Future<void>? _initialization;

  User? get currentUser => _firebaseAuth.currentUser;
  bool get isAuthenticated => _firebaseAuth.currentUser != null;
  bool get isGuest => _isCurrentlyGuest && !isAuthenticated;
  bool get hasChosenAuthMethod => isAuthenticated || _isCurrentlyGuest;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  Stream<bool> get authMethodChosenStream => _authStateController.stream;

  // Initialization is shared by startup and AuthWrapper. Running it twice can
  // process a redirect twice or create duplicate auth-state subscriptions.
  Future<void> initialize() async {
    final initialization = _initialization ??= _initialize();
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    try {
      // Validate Google Web Client ID for web
      if (kIsWeb && !_config.isValidConfiguration) {
        throw Exception('Invalid configuration. Missing: GOOGLE_WEB_CLIENT_ID');
      }

      // Persist auth across browser sessions on web
      if (kIsWeb) {
        await _firebaseAuth.setPersistence(Persistence.LOCAL);
      }

      // Initialize GoogleSignIn with web client ID if on web
      if (kIsWeb) {
        _googleSignIn = GoogleSignIn(clientId: _config.googleWebClientId);
      } else {
        _googleSignIn = GoogleSignIn();
      }

      // Print configuration in debug mode
      _config.printConfiguration();

      if (kIsWeb) {
        // Check for redirect result on web
        try {
          final redirectResult = await _firebaseAuth.getRedirectResult();
          if (redirectResult.user != null) {
            SecureLogger.authEvent('Google Sign-In redirect successful');
            // Store auth preference
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(StorageKeys.isAuthenticated, true);
            await prefs.remove(StorageKeys.isGuest);
          } else {
            SecureLogger.debug('AUTH', 'No redirect result found');
          }
        } catch (e) {
          SecureLogger.debug('AUTH', 'No redirect result available');
        }
      }

      // Sync prefs if Firebase already has a user (e.g. restored from persistence)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.isGuest);

      if (currentUser != null) {
        SecureLogger.info('AUTH', 'Current user found during initialization');
        await prefs.setBool(StorageKeys.isAuthenticated, true);
      } else {
        SecureLogger.debug(
          'AUTH',
          'No current user found during initialization',
        );
        // Don't clear is_authenticated here — on web, Firebase restores the
        // persisted session asynchronously, so currentUser can be null for a
        // moment after startup. The pref is only cleared on explicit sign-out.
        // (This previously blamed App Check, which was never activated.)
      }

      // Keep the remote log sink's user id in lockstep with auth state, so every
      // shipped log carries the app-specific id (e.g. "f20220123H"). Fires on
      // login, logout, and persistence restore. Uses the app id, never the
      // Firebase UID.
      RemoteLogSink().setUserId(userDocId);
      _authSub ??= authStateChanges.listen((user) {
        RemoteLogSink().setUserId(deriveUserDocId(user?.email));
      });
    } catch (e) {
      SecureLogger.error('AUTH', 'Failed to initialize AuthService', e);
      rethrow;
    }
  }

  static bool isPopupCancellationCode(String code) => const {
    'popup-closed-by-user',
    'cancelled-popup-request',
    'web-context-cancelled',
  }.contains(code);

  static bool shouldUseRedirectForPopupCode(String code) => const {
    'popup-blocked',
    'operation-not-supported-in-this-environment',
    'web-storage-unsupported',
  }.contains(code);

  AuthFlowException _friendlyAuthError(Object error) {
    if (error is AuthFlowException) return error;
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'network-request-failed' => const AuthFlowException(
          'Network error. Check your connection and try again.',
        ),
        'unauthorized-domain' => const AuthFlowException(
          'This domain is not authorized for sign-in. Please contact support.',
        ),
        'popup-blocked' => const AuthFlowException(
          'The sign-in popup was blocked. Allow popups and try again.',
        ),
        'too-many-requests' => const AuthFlowException(
          'Too many sign-in attempts. Wait a moment and try again.',
        ),
        _ => AuthFlowException(
          error.message ?? 'Google sign-in failed. Please try again.',
        ),
      };
    }
    final text = error.toString().toLowerCase();
    if (text.contains('network')) {
      return const AuthFlowException(
        'Network error. Check your connection and try again.',
      );
    }
    return const AuthFlowException('Google sign-in failed. Please try again.');
  }

  Future<AuthSignInResult> signInWithGoogle() async {
    try {
      await initialize();
      if (kIsWeb) {
        // Web authentication - use redirect method which is more reliable
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();

        // Add scopes
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({'prompt': 'select_account'});

        try {
          SecureLogger.info('AUTH', 'Starting Google Sign-In popup');
          final userCredential = await _firebaseAuth.signInWithPopup(
            googleProvider,
          );

          if (userCredential.user == null) {
            return AuthSignInResult.cancelled;
          }

          SecureLogger.authEvent('Google Sign-In popup successful');

          // Store auth preference
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(StorageKeys.isAuthenticated, true);
          await prefs.remove(StorageKeys.isGuest);

          return AuthSignInResult.signedIn;
        } catch (popupError) {
          if (popupError is FirebaseAuthException &&
              isPopupCancellationCode(popupError.code)) {
            SecureLogger.info('AUTH', 'Google Sign-In popup cancelled');
            return AuthSignInResult.cancelled;
          }
          if (popupError is! FirebaseAuthException ||
              !shouldUseRedirectForPopupCode(popupError.code)) {
            rethrow;
          }

          SecureLogger.warning('AUTH', 'Popup unavailable; using redirect', {
            'code': popupError.code,
          });
          try {
            await _firebaseAuth.signInWithRedirect(googleProvider);
            return AuthSignInResult.redirecting;
          } catch (redirectError) {
            SecureLogger.error(
              'AUTH',
              'Redirect sign-in also failed',
              redirectError,
            );
            throw _friendlyAuthError(redirectError);
          }
        }
      } else {
        // Mobile authentication
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return AuthSignInResult.cancelled;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _firebaseAuth.signInWithCredential(
          credential,
        );

        // Store auth preference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(StorageKeys.isAuthenticated, true);
        await prefs.remove(StorageKeys.isGuest);

        return userCredential.user == null
            ? AuthSignInResult.cancelled
            : AuthSignInResult.signedIn;
      }
    } catch (e) {
      SecureLogger.error('AUTH', 'Failed to sign in with Google', e);
      throw _friendlyAuthError(e);
    }
  }

  Future<void> signInAsGuest() async {
    try {
      // Set session-only guest mode (not persisted across app restarts)
      _isCurrentlyGuest = true;

      // Clear any existing auth preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.isAuthenticated);
      await prefs.remove(StorageKeys.isGuest);

      // Notify listeners that auth method has been chosen
      _authStateController.add(true);

      SecureLogger.authEvent('Guest mode activated');
    } catch (e) {
      _isCurrentlyGuest = false;
      SecureLogger.error('AUTH', 'Failed to set guest mode', e);
      rethrow;
    }
  }

  Future<void> signOut() async {
    _isCurrentlyGuest = false;

    // Google provider cleanup must not prevent the authoritative Firebase
    // session from being terminated.
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (error) {
        SecureLogger.warning('AUTH', 'Google provider sign-out failed', {
          'error': error.toString(),
        });
      }
    }

    try {
      await _firebaseAuth.signOut();
    } catch (error) {
      SecureLogger.error('AUTH', 'Firebase sign-out failed', error);
      throw const AuthFlowException(
        'Could not sign out. Check your connection and try again.',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.isAuthenticated);
      await prefs.remove(StorageKeys.isGuest);

      // Everything keyed to the account that just left. Both are process-wide
      // singletons, so anything left behind is read as the *next* account's —
      // an in-progress tour keeps running over the login screen, and the new
      // user inherits the old one's completed-tutorial and theme settings.
      TutorialService().reset();
      await UserSettingsService().clearSettings();

      // Notify auth method chosen listeners after clearing guest mode
      _authStateController.add(false);
      SecureLogger.authEvent('User signed out successfully');
    } catch (error) {
      // Firebase is already signed out. Cleanup can be retried on next launch,
      // so do not misreport the completed sign-out as a session failure.
      SecureLogger.error('AUTH', 'Post-sign-out cleanup failed', error);
      _authStateController.add(false);
    }
  }

  Future<bool> isGuestMode() async {
    // Return the current session guest mode status
    return _isCurrentlyGuest;
  }

  String? get userEmail => currentUser?.email;
  String? get userName => currentUser?.displayName;
  String? get userPhotoUrl => currentUser?.photoURL;

  NetworkImage? _cachedPhotoImage;
  String? _cachedPhotoUrl;

  NetworkImage? get userPhotoImage {
    final url = userPhotoUrl;
    if (url == null) return null;
    if (_cachedPhotoUrl != url) {
      _cachedPhotoUrl = url;
      _cachedPhotoImage = NetworkImage(url);
    }
    return _cachedPhotoImage;
  }

  /// Derives the Firestore document ID for the current user from their email.
  /// Format: {username}{campusLetter} e.g. "f20220123H" for Hyderabad.
  String? get userDocId {
    final email = currentUser?.email;
    if (email == null) return null;
    return deriveUserDocId(email);
  }

  static String? deriveUserDocId(String? email) {
    if (email == null || !email.contains('@')) return null;
    final atIdx = email.indexOf('@');
    final username = email.substring(0, atIdx);
    final domain = email.substring(atIdx + 1).toLowerCase();

    if (domain == 'hyderabad.bits-pilani.ac.in') return '${username}H';
    if (domain == 'pilani.bits-pilani.ac.in') return '${username}P';
    if (domain == 'goa.bits-pilani.ac.in') return '${username}G';
    if (domain == 'dubai.bits-pilani.ac.in') return '${username}D';
    return null;
  }

  // Check if user has valid authentication state
  Future<bool> isValidAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAuthenticated =
          prefs.getBool(StorageKeys.isAuthenticated) ?? false;
      return isAuthenticated;
    } catch (e) {
      SecureLogger.error('AUTH', 'Failed to check auth state', e);
      return false;
    }
  }

  // Clear all auth data
  Future<void> clearAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.isAuthenticated);
      await prefs.remove(StorageKeys.isGuest);
    } catch (e) {
      SecureLogger.error('AUTH', 'Failed to clear auth data', e);
    }
  }
}
