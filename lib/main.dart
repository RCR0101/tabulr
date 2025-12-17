import 'dart:async';
import 'package:flutter/material.dart';
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
import 'services/theme_service.dart';
import 'services/campus_service.dart';
import 'services/preferences_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize campus service
  await CampusService.initializeCampus();
  
  // Initialize Auth Service
  await AuthService().initialize();
  
  // Initialize Theme Service
  await ThemeService().initialize();
  
  // Initialize Preferences Service
  await PreferencesService().initialize();
  
  if (kIsWeb) {
    setUrlStrategy(PathUrlStrategy());
    _setupWebCacheClearOnClose();
  }
  
  runApp(const TimetableMakerApp());
}

void _setupWebCacheClearOnClose() {
  if (kIsWeb) {
    try {
      // Clear localStorage when the page is about to unload (only for guest users)
      html.window.addEventListener('beforeunload', (event) {
        try {
          // Only clear if user is in guest mode
          final authService = AuthService();
          if (!authService.isAuthenticated) {
            js.context.callMethod('eval', [
              'window.localStorage.removeItem("user_timetable_data")'
            ]);
          }
        } catch (e) {
          print('Error clearing localStorage: $e');
        }
      });
      
      // Also clear on page hide (covers mobile scenarios)
      html.window.addEventListener('pagehide', (event) {
        try {
          // Only clear if user is in guest mode
          final authService = AuthService();
          if (!authService.isAuthenticated) {
            js.context.callMethod('eval', [
              'window.localStorage.removeItem("user_timetable_data")'
            ]);
          }
        } catch (e) {
          print('Error clearing localStorage: $e');
        }
      });
    } catch (e) {
      print('Error setting up cache clearing: $e');
    }
  }
}

class TimetableMakerApp extends StatelessWidget {
  const TimetableMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, child) {
        final themeService = ThemeService();
        return MaterialApp(
          title: 'Tabulr',
          theme: themeService.getThemeData(themeService.currentTheme),
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
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        // Force rebuild when auth state changes by checking current state
        final isAuthenticated = _authService.isAuthenticated;
        final isGuest = _authService.isGuest;
        
        print('AuthWrapper rebuild - isAuthenticated: $isAuthenticated, isGuest: $isGuest');
        
        // If user is authenticated, go to timetables screen
        if (isAuthenticated) {
          return const TimetablesScreen();
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
