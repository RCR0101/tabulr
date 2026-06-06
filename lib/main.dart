import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'utils/web_utils.dart' as web_utils;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'constants/app_constants.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/common/shimmer_loading.dart';
import 'widgets/app_shell.dart';
import 'services/data/auth_service.dart';
import 'services/ui/theme_service.dart' as theme_service;
import 'services/data/campus_service.dart';
import 'services/data/courses_master_service.dart';
import 'services/data/preferences_service.dart';
import 'services/data/user_settings_service.dart';
import 'models/user_settings.dart' as user_settings;
import 'services/data/admin_service.dart';
import 'services/ui/secure_logger.dart';
import 'services/ui/performance_monitor.dart';
import 'widgets/theme_transition_overlay.dart';

void main() async {
  final totalStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  PerformanceMonitor().initialize();

  await SecureLogger.measureAsync('firebase_init', () => Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ));

  await SecureLogger.measureAsync('app_check_init', () => FirebaseAppCheck.instance.activate(
    webProvider: ReCaptchaEnterpriseProvider(FirebaseConfig.recaptchaEnterpriseSiteKey),
  ));

  await SecureLogger.measureAsync('campus_init', () => CampusService.initializeCampus());

  final userSettingsService = UserSettingsService();
  final themeService = theme_service.ThemeService();

  // Each service is wrapped so a single failure (e.g. Firestore permission-denied
  // when App Check token is invalid) doesn't kill the entire startup.
  await SecureLogger.measureAsync('parallel_services', () => Future.wait([
    CoursesMasterService().loadForCampus().catchError((e) {
      SecureLogger.error('STARTUP', 'Failed to load courses', e);
    }),
    AuthService().initialize().catchError((e) {
      SecureLogger.error('STARTUP', 'Failed to initialize auth', e);
    }),
    userSettingsService.initializeSettings().catchError((e) {
      SecureLogger.error('STARTUP', 'Failed to load user settings', e);
    }),
    themeService.initialize().catchError((e) {
      SecureLogger.error('STARTUP', 'Failed to initialize theme', e);
    }),
    PreferencesService().initialize().catchError((e) {
      SecureLogger.error('STARTUP', 'Failed to initialize preferences', e);
    }),
  ]));

  // Re-load settings if auth won the race (settings may have loaded as guest)
  if (AuthService().isAuthenticated) {
    try {
      await userSettingsService.initializeSettings(force: true);
    } catch (e) {
      SecureLogger.error('STARTUP', 'Failed to re-load user settings', e);
    }
  }
  final savedSettings = userSettingsService.userSettings;
  if (savedSettings != null) {
    await themeService.setTheme(savedSettings.themeVariant);
    final flutterMode = switch (savedSettings.themeMode) {
      user_settings.ThemeMode.light => ThemeMode.light,
      user_settings.ThemeMode.dark => ThemeMode.dark,
      user_settings.ThemeMode.system => ThemeMode.system,
    };
    await themeService.setThemeMode(flutterMode);
  }

  // Non-blocking admin check — runs in background after auth is ready
  AdminService().checkAdminStatus();

  if (kIsWeb) {
    web_utils.usePathUrlStrategy();
    _setupWebCacheClearOnClose();
  }

  totalStopwatch.stop();
  SecureLogger.performance('total_startup', totalStopwatch.elapsed);

  runApp(const TimetableMakerApp());
}

void _setupWebCacheClearOnClose() {
  if (kIsWeb) {
    try {
      void clearGuestData() {
        try {
          final authService = AuthService();
          if (!authService.isAuthenticated) {
            web_utils.clearLocalStorageItem('user_timetable_data');
          }
        } catch (e) {
          // Silently ignore localStorage errors
        }
      }

      web_utils.addBeforeUnloadListener(() {
        clearGuestData();
        return false;
      });
      web_utils.addPageHideListener(clearGuestData);
    } catch (e) {
      // Silently ignore cache clearing setup errors
    }
  }
}

class TimetableMakerApp extends StatefulWidget {
  const TimetableMakerApp({super.key});

  static ThemeTransitionController? themeTransition;

  @override
  State<TimetableMakerApp> createState() => _TimetableMakerAppState();
}

class _TimetableMakerAppState extends State<TimetableMakerApp> {
  final _screenshotKey = GlobalKey();
  final _themeTransition = ThemeTransitionController();

  @override
  void initState() {
    super.initState();
    TimetableMakerApp.themeTransition = _themeTransition;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme_service.ThemeService(),
      builder: (context, child) {
        final themeService = theme_service.ThemeService();
        return MaterialApp(
          title: 'Tabulr',
          theme: themeService.getLightThemeData(themeService.currentTheme),
          darkTheme: themeService.getDarkThemeData(themeService.currentTheme),
          themeMode: themeService.currentThemeMode,
          debugShowCheckedModeBanner: false,
          home: ThemeTransitionOverlay(
            controller: _themeTransition,
            screenshotKey: _screenshotKey,
            child: RepaintBoundary(
              key: _screenshotKey,
              child: const AuthWrapper(),
            ),
          ),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  late StreamSubscription<bool> _authMethodSubscription;
  late StreamSubscription<dynamic> _authSub;
  bool _authReady = false;
  bool _themeSynced = false;
  bool _wasPreviouslyAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _initAuth();
    _authMethodSubscription = _authService.authMethodChosenStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initAuth() async {
    final wasAuth = await _authService.isValidAuthState();
    if (mounted) {
      setState(() => _wasPreviouslyAuthenticated = wasAuth);
    }

    _authSub = _authService.authStateChanges.listen((user) {
      if (user != null) {
        _authReady = true;
        if (!_themeSynced) {
          _themeSynced = true;
          _syncThemeFromFirestore();
        }
        if (mounted) setState(() {});
      } else if (!_wasPreviouslyAuthenticated) {
        _authReady = true;
        if (mounted) setState(() {});
      } else {
        // User was previously authenticated but Firebase emitted null.
        // This happens on web when App Check hasn't validated yet.
        // Wait for the next emission — if the session is truly gone,
        // Firebase will emit null again and we'll show login.
        _wasPreviouslyAuthenticated = false;
        // Don't set _authReady yet — keep showing skeleton
      }
    });
  }

  Future<void> _syncThemeFromFirestore() async {
    final userSettingsService = UserSettingsService();
    await userSettingsService.initializeSettings(force: true);
    final settings = userSettingsService.userSettings;
    if (settings != null) {
      final themeService = theme_service.ThemeService();
      await themeService.setTheme(settings.themeVariant);
      final flutterMode = switch (settings.themeMode) {
        user_settings.ThemeMode.light => ThemeMode.light,
        user_settings.ThemeMode.dark => ThemeMode.dark,
        user_settings.ThemeMode.system => ThemeMode.system,
      };
      await themeService.setThemeMode(flutterMode);
    }
  }

  @override
  void dispose() {
    _authMethodSubscription.cancel();
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authService.isAuthenticated) {
      return const AppShell();
    }

    if (_authService.isGuest) {
      return const HomeScreen();
    }

    if (!_authReady) {
      return const Scaffold(
        body: TimetableListSkeleton(),
      );
    }

    return const AuthScreen();
  }
}

