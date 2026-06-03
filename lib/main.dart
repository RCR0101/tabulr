import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'constants/app_constants.dart';
import 'utils/web_utils.dart' as web_utils;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
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

void main() async {
  final totalStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  PerformanceMonitor().initialize();

  await SecureLogger.measureAsync('firebase_init', () => Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ));

  await SecureLogger.measureAsync('app_check_init', () =>
    FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider(FirebaseConfig.recaptchaSiteKey),
    ),
  );

  await SecureLogger.measureAsync('campus_init', () => CampusService.initializeCampus());

  final userSettingsService = UserSettingsService();
  final themeService = theme_service.ThemeService();
  await SecureLogger.measureAsync('parallel_services', () => Future.wait([
    CoursesMasterService().loadForCampus(),
    AuthService().initialize(),
    userSettingsService.initializeSettings(),
    themeService.initialize(),
    PreferencesService().initialize(),
  ]));

  // Sync theme from UserSettings (Firestore source of truth) to ThemeService
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

class TimetableMakerApp extends StatelessWidget {
  const TimetableMakerApp({super.key});

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
          home: const AuthWrapper(),
          debugShowCheckedModeBanner: false,
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

  @override
  void initState() {
    super.initState();
    // Listen to auth method chosen stream to trigger rebuilds for guest mode
    _authMethodSubscription = _authService.authMethodChosenStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _authMethodSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _authService.authStateChanges,
      builder: (context, authSnapshot) {
        // Show loading while checking auth state
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: TimetableListSkeleton(),
          );
        }
        
        // Force rebuild when auth state changes by checking current state
        final isAuthenticated = _authService.isAuthenticated;
        final isGuest = _authService.isGuest;
        
        // If user is authenticated, go to app shell with sidebar
        if (isAuthenticated) {
          return const AppShell();
        }
        
        // If user has chosen guest mode, go to simple home screen
        if (isGuest) {
          return const HomeScreen();
        }
        
        // Otherwise, show auth screen
        return const AuthScreen();
      },
    );
  }
}

