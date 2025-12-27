import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/timetables_screen.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart' as theme_service;
import 'services/campus_service.dart';
import 'services/preferences_service.dart';
import 'services/user_settings_service.dart';
import 'models/user_settings.dart' as user_settings;
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await CampusService.initializeCampus();
  await AuthService().initialize();
  
  final userSettingsService = UserSettingsService();
  await userSettingsService.initializeSettings();
  
  final themeService = theme_service.ThemeService();
  await themeService.initialize();
  
  await themeService.setTheme(userSettingsService.themeVariant);
  await themeService.setThemeMode(_convertToFlutterThemeMode(userSettingsService.themeMode));
  
  await PreferencesService().initialize();
  
  if (kIsWeb) {
    setUrlStrategy(PathUrlStrategy());
    _setupWebCacheClearOnClose();
  }
  
  runApp(const ProviderScope(child: TimetableMakerApp()));
}

void _setupWebCacheClearOnClose() {
  if (kIsWeb) {
    try {
      html.window.addEventListener('beforeunload', (event) {
        try {
          final authService = AuthService();
          if (!authService.isAuthenticated) {
            js.context.callMethod('eval', [
              'window.localStorage.removeItem("user_timetable_data")'
            ]);
          }
        } catch (e) {
          // Ignore localStorage errors
        }
      });
      
      html.window.addEventListener('pagehide', (event) {
        try {
          final authService = AuthService();
          if (!authService.isAuthenticated) {
            js.context.callMethod('eval', [
              'window.localStorage.removeItem("user_timetable_data")'
            ]);
          }
        } catch (e) {
          // Ignore localStorage errors
        }
      });
    } catch (e) {
      // Ignore cache setup errors
    }
  }
}

class TimetableMakerApp extends ConsumerWidget {
  const TimetableMakerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(themeDataProvider);
    
    return MaterialApp(
      title: 'Tabulr',
      theme: themeData,
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    if (authState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (authState.isAuthenticated) {
      return const TimetablesScreen();
    }
    
    if (authState.isGuest) {
      return const HomeScreen();
    }
    
    return const AuthScreen();
  }
}

ThemeMode _convertToFlutterThemeMode(user_settings.ThemeMode userThemeMode) {
  switch (userThemeMode) {
    case user_settings.ThemeMode.light:
      return ThemeMode.light;
    case user_settings.ThemeMode.dark:
      return ThemeMode.dark;
    case user_settings.ThemeMode.system:
      return ThemeMode.system;
  }
}
