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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212), 
        cardColor: const Color(0xFF1E1E1E), 
        
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF82AAFF),       
          secondary: Color(0xFFC3E88D),      
          background: Color(0xFF121212),
          surface: Color(0xFF1E1E1E),
          error: Color(0xFFFF9B9B),         
          onPrimary: Color(0xFF10141C),      
          onSecondary: Color(0xFF181C10),    
          onBackground: Color(0xFFE0E0E0),   
          onSurface: Color(0xFFE0E0E0),      
          onError: Color(0xFF1C1010),        
          outline: Color(0xFF3A3A3A),       
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF82AAFF), 
            foregroundColor: const Color(0xFF10141C), 
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF82AAFF), 
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121212),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF82AAFF), width: 1.5),
          ),
        ),
        
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
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
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        // If user is authenticated, go to timetables screen
        if (snapshot.hasData && snapshot.data != null) {
          return const TimetablesScreen();
        }
        
        // If user has chosen an auth method as guest, go to simple home screen
        if (_authService.hasChosenAuthMethod && _authService.isGuest) {
          return const HomeScreen();
        }
        
        // If user has chosen an auth method (authenticated), go to timetables screen
        if (_authService.hasChosenAuthMethod) {
          return const TimetablesScreen();
        }
        
        // Otherwise, show auth screen (guest users will see this on every app start)
        return const AuthScreen();
      },
    );
  }
}
