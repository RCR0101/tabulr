import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'utils/web_utils.dart' as web_utils;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/maintenance_screen.dart';
import 'widgets/common/shimmer_loading.dart';
import 'widgets/app_shell.dart';
import 'services/data/auth_service.dart';
import 'services/ui/theme_service.dart' as theme_service;
import 'services/data/campus_service.dart';
import 'services/data/courses_master_service.dart';
import 'services/data/preferences_service.dart';
import 'services/data/config_service.dart';
import 'services/data/user_settings_service.dart';
import 'models/user_settings.dart' as user_settings;
import 'services/data/admin_service.dart';
import 'services/ui/secure_logger.dart';
import 'services/ui/performance_monitor.dart';
import 'services/ui/remote_log_sink.dart';
import 'utils/app_routes.dart';
import 'utils/app_scroll_behavior.dart';
import 'utils/design_constants.dart';
import 'constants/app_constants.dart';

void main() async {
  final totalStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // Logger worker requires Authorization: Bearer <API_KEY> on POSTs. Supplied at
  // build time via --dart-define=LOGGER_API_KEY=... so it stays out of source.
  const loggerApiKey = String.fromEnvironment('LOGGER_API_KEY');
  final loggerKey = loggerApiKey.isEmpty ? null : loggerApiKey;

  PerformanceMonitor().initialize(apiKey: loggerKey);
  // Ship app logs + admin audit trail to the logger worker -> R2 logs bucket.
  // Release-only (debug builds already log to the console) and warning+ to keep
  // worker invocations / R2 writes minimal in healthy operation.
  RemoteLogSink().initialize(
    enabled: !kDebugMode,
    minLevelIndex: 2,
    apiKey: loggerKey,
  );

  await SecureLogger.measureAsync(
    'firebase_init',
    () =>
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 40 * 1024 * 1024,
  );

  await SecureLogger.measureAsync(
    'local_init',
    () => Future.wait([
      CampusService.initializeCampus().catchError((e) {
        SecureLogger.error('STARTUP', 'Failed to initialize campus', e);
      }),
      theme_service.ThemeService().initialize().catchError((e) {
        SecureLogger.error('STARTUP', 'Failed to initialize theme', e);
      }),
      PreferencesService().initialize().catchError((e) {
        SecureLogger.error('STARTUP', 'Failed to initialize preferences', e);
      }),
    ]),
  );

  if (kIsWeb) {
    web_utils.usePathUrlStrategy();
    // Read once, here, while Uri.base is still the URL the user arrived on.
    AppRoutes.pendingShareCode = AppRoutes.shareCodeIn(Uri.base);
    _setupWebCacheClearOnClose();
  }

  AuthService().initialize().catchError((e) {
    SecureLogger.error('STARTUP', 'Failed to initialize auth', e);
  });
  CoursesMasterService().loadForCampus().catchError((e) {
    SecureLogger.error('STARTUP', 'Failed to load courses', e);
  });
  AdminService().checkAdminStatus();

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
            web_utils.clearLocalStorageItem(StorageKeys.userTimetableData);
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

  @override
  State<TimetableMakerApp> createState() => _TimetableMakerAppState();
}

class _TimetableMakerAppState extends State<TimetableMakerApp> {
  /// Built once and handed to the router delegate, which outlives the theme
  /// rebuilds this widget goes through.
  late final Widget _home = const MaintenanceGate(child: AuthWrapper());

  String? _lastBootColors;

  void _persistBootColors(ThemeData effective) {
    if (!kIsWeb) return;
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final bg = hex(effective.scaffoldBackgroundColor);
    final fg = hex(effective.colorScheme.onSurface);
    final accent = hex(effective.colorScheme.primary);
    final combined = '$bg|$fg|$accent';
    if (combined == _lastBootColors) return;
    _lastBootColors = combined;
    web_utils.setLocalStorageItem('tabulr_boot_bg', bg);
    web_utils.setLocalStorageItem('tabulr_boot_fg', fg);
    web_utils.setLocalStorageItem('tabulr_boot_accent', accent);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme_service.ThemeService(),
      builder: (context, child) {
        final themeService = theme_service.ThemeService();
        final light = themeService.getLightThemeData(themeService.currentTheme);
        final dark = themeService.getDarkThemeData(themeService.currentTheme);
        final isDark = switch (themeService.currentThemeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system =>
            MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        };
        _persistBootColors(isDark ? dark : light);
        // .router, not the plain constructor: it is what puts the web engine in
        // multi-entry history mode, without which the back button leaves the
        // site instead of walking back through the app. See [AppRouterDelegate].
        return MaterialApp.router(
          title: 'Tabulr',
          theme: light,
          darkTheme: dark,
          themeMode: themeService.currentThemeMode,
          themeAnimationDuration: AppDesign.motionStandard,
          themeAnimationCurve: AppDesign.curveStandard,
          routeInformationParser: const AppRouteInformationParser(),
          routerDelegate: AppRoutes.delegateFor(_home),
          scrollBehavior: const AppScrollBehavior(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

/// Root kill-switch gate. If `reference/app_config.maintenance` is true (read
/// at startup by [ConfigService] at no extra read cost), shows the
/// [MaintenanceScreen] instead of the app. The "Try again" action re-fetches the
/// config so users can recover without a manual reload. Server-side enforcement
/// is handled independently by firestore.rules.
class MaintenanceGate extends StatefulWidget {
  final Widget child;
  const MaintenanceGate({super.key, required this.child});

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  @override
  void initState() {
    super.initState();
    ConfigService()
        .loadSemesterDates()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((e) {
          SecureLogger.error('STARTUP', 'Failed to load app config', e);
        });
  }

  @override
  Widget build(BuildContext context) {
    final config = ConfigService();
    if (!config.isMaintenance) return widget.child;

    return MaintenanceScreen(
      message: config.maintenanceMessage,
      onRetry: () async {
        await config.reloadAppConfig();
        if (mounted) setState(() {});
        return !config.isMaintenance;
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
  StreamSubscription<dynamic>? _authSub;
  Timer? _authRestoreTimer;
  bool _authReady = false;

  /// Whose settings are currently loaded. Per-uid rather than a one-shot bool:
  /// signing out and back in as someone else re-emits with a different uid, and
  /// that account has its own theme and its own completed tutorials to load.
  String? _syncedUid;
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
    if (!mounted) return;
    setState(() => _wasPreviouslyAuthenticated = wasAuth);

    _authSub = _authService.authStateChanges.listen((user) {
      if (user != null) {
        _authRestoreTimer?.cancel();
        _authReady = true;
        if (_syncedUid != user.uid) {
          _syncedUid = user.uid;
          _syncThemeFromFirestore();
        }
        if (mounted) setState(() {});
      } else if (!_wasPreviouslyAuthenticated) {
        // Signing out drops the cached settings, so the next sign-in has to
        // reload them even when it is the same account coming back.
        _syncedUid = null;
        _authReady = true;
        if (mounted) setState(() {});
      } else {
        // Give web persistence a short restoration window, but never wait for
        // a second null event: Firebase may emit only once for an expired or
        // revoked session, which previously left the skeleton up forever.
        _wasPreviouslyAuthenticated = false;
        _authRestoreTimer?.cancel();
        _authRestoreTimer = Timer(const Duration(seconds: 1), () {
          if (!mounted || _authService.isAuthenticated) return;
          _syncedUid = null;
          _authReady = true;
          unawaited(_authService.clearAuthData());
          setState(() {});
        });
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
        user_settings.AppThemeMode.light => ThemeMode.light,
        user_settings.AppThemeMode.dark => ThemeMode.dark,
        user_settings.AppThemeMode.system => ThemeMode.system,
      };
      await themeService.setThemeMode(flutterMode);
    }
  }

  @override
  void dispose() {
    _authRestoreTimer?.cancel();
    _authMethodSubscription.cancel();
    _authSub?.cancel();
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
      return const Scaffold(body: TimetableListSkeleton());
    }

    return const AuthScreen();
  }
}
