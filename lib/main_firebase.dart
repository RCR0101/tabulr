import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TimetableMakerApp());
}

class TimetableMakerApp extends StatelessWidget {
  const TimetableMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tabulr',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF1A1A1A),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64B5F6),
          secondary: Color(0xFF81C784),
          surface: Color(0xFF1E1E1E),
          background: Color(0xFF121212),
          error: Color(0xFFE57373),
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          onBackground: Colors.white,
          onError: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1E1E1E),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF64B5F6),
            foregroundColor: Colors.black,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64B5F6),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF404040)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF404040)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF64B5F6)),
          ),
          labelStyle: const TextStyle(color: Color(0xFFB0B0B0)),
          hintStyle: const TextStyle(color: Color(0xFF808080)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF2A2A2A),
          selectedColor: const Color(0xFF64B5F6),
          labelStyle: const TextStyle(color: Colors.white),
          secondaryLabelStyle: const TextStyle(color: Colors.black),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: MaterialStateProperty.all(const Color(0xFF2A2A2A)),
          dataRowColor: MaterialStateProperty.all(const Color(0xFF1E1E1E)),
          dividerThickness: 1,
        ),
        expansionTileTheme: const ExpansionTileThemeData(
          backgroundColor: Color(0xFF2A2A2A),
          collapsedBackgroundColor: Color(0xFF1E1E1E),
          iconColor: Color(0xFF64B5F6),
          collapsedIconColor: Color(0xFFB0B0B0),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}