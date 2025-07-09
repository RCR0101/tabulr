import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize Auth Service
  await AuthService().initialize();
  
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
    return MaterialApp(
      title: 'Tabulr',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF0D1117),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          secondary: Color(0xFF56D364),
          surface: Color(0xFF161B22),
          background: Color(0xFF0D1117),
          error: Color(0xFFFF6B6B),
          onPrimary: Color(0xFF0D1117),
          onSecondary: Color(0xFF0D1117),
          onSurface: Color(0xFFF0F6FC),
          onBackground: Color(0xFFF0F6FC),
          onError: Color(0xFF0D1117),
          outline: Color(0xFF30363D),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          foregroundColor: Color(0xFFF0F6FC),
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF161B22),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF58A6FF),
            foregroundColor: const Color(0xFF0D1117),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF58A6FF),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF21262D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF58A6FF)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8B949E)),
          hintStyle: const TextStyle(color: Color(0xFF6E7681)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF21262D),
          selectedColor: const Color(0xFF58A6FF),
          labelStyle: const TextStyle(color: Color(0xFFF0F6FC)),
          secondaryLabelStyle: const TextStyle(color: Color(0xFF0D1117)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: MaterialStateProperty.all(const Color(0xFF21262D)),
          dataRowColor: MaterialStateProperty.all(const Color(0xFF161B22)),
          dividerThickness: 1,
        ),
        expansionTileTheme: const ExpansionTileThemeData(
          backgroundColor: Color(0xFF21262D),
          collapsedBackgroundColor: Color(0xFF161B22),
          iconColor: Color(0xFF58A6FF),
          collapsedIconColor: Color(0xFF8B949E),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    
    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        // If user is authenticated, go to home screen
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }
        
        // If user has chosen an auth method (guest or sign-in), go to home screen
        if (authService.hasChosenAuthMethod) {
          return const HomeScreen();
        }
        
        // Otherwise, show auth screen (guest users will see this on every app start)
        return const AuthScreen();
      },
    );
  }
}
