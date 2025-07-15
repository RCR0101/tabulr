import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  githubDark,
  draculaDark,
  oceanicDark,
  cobaltDark,
  materialDark,
  nordDark,
  tokyoNightDark,
  gruvboxDark,
  catppuccinDark,
  solarizedDark,
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  AppTheme _currentTheme = AppTheme.githubDark;
  static const String _themeKey = 'selected_theme';

  AppTheme get currentTheme => _currentTheme;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    _currentTheme = AppTheme.values[themeIndex];
    notifyListeners();
  }

  Future<void> setTheme(AppTheme theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, theme.index);
    notifyListeners();
  }

  String getThemeName(AppTheme theme) {
    switch (theme) {
      case AppTheme.githubDark:
        return 'GitHub Dark';
      case AppTheme.draculaDark:
        return 'Dracula';
      case AppTheme.oceanicDark:
        return 'Oceanic';
      case AppTheme.cobaltDark:
        return 'Cobalt Blue';
      case AppTheme.materialDark:
        return 'Material Dark';
      case AppTheme.nordDark:
        return 'Nord';
      case AppTheme.tokyoNightDark:
        return 'Tokyo Night';
      case AppTheme.gruvboxDark:
        return 'Gruvbox';
      case AppTheme.catppuccinDark:
        return 'Catppuccin';
      case AppTheme.solarizedDark:
        return 'Solarized Dark';
    }
  }

  IconData getThemeIcon(AppTheme theme) {
    switch (theme) {
      case AppTheme.githubDark:
        return Icons.code;
      case AppTheme.draculaDark:
        return Icons.brightness_2;
      case AppTheme.oceanicDark:
        return Icons.waves;
      case AppTheme.cobaltDark:
        return Icons.blur_on;
      case AppTheme.materialDark:
        return Icons.android;
      case AppTheme.nordDark:
        return Icons.ac_unit;
      case AppTheme.tokyoNightDark:
        return Icons.nightlight_round;
      case AppTheme.gruvboxDark:
        return Icons.grain;
      case AppTheme.catppuccinDark:
        return Icons.pets;
      case AppTheme.solarizedDark:
        return Icons.wb_sunny;
    }
  }

  ThemeData getThemeData(AppTheme theme) {
    switch (theme) {
      case AppTheme.githubDark:
        return _buildGitHubTheme();
      case AppTheme.draculaDark:
        return _buildDraculaTheme();
      case AppTheme.oceanicDark:
        return _buildOceanicTheme();
      case AppTheme.cobaltDark:
        return _buildCobaltTheme();
      case AppTheme.materialDark:
        return _buildMaterialTheme();
      case AppTheme.nordDark:
        return _buildNordTheme();
      case AppTheme.tokyoNightDark:
        return _buildTokyoNightTheme();
      case AppTheme.gruvboxDark:
        return _buildGruvboxTheme();
      case AppTheme.catppuccinDark:
        return _buildCatppuccinTheme();
      case AppTheme.solarizedDark:
        return _buildSolarizedTheme();
    }
  }

  ThemeData _buildGitHubTheme() {
    return ThemeData.dark().copyWith(
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
    );
  }

  ThemeData _buildDraculaTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF282A36),
      scaffoldBackgroundColor: const Color(0xFF282A36),
      cardColor: const Color(0xFF44475A),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFBD93F9),
        secondary: Color(0xFF50FA7B),
        surface: Color(0xFF44475A),
        background: Color(0xFF282A36),
        error: Color(0xFFFF5555),
        onPrimary: Color(0xFF282A36),
        onSecondary: Color(0xFF282A36),
        onSurface: Color(0xFFF8F8F2),
        onBackground: Color(0xFFF8F8F2),
        onError: Color(0xFF282A36),
        outline: Color(0xFF6272A4),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF282A36),
        foregroundColor: Color(0xFFF8F8F2),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF44475A),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFBD93F9),
          foregroundColor: const Color(0xFF282A36),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFBD93F9),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF44475A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6272A4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6272A4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFBD93F9)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF8BE9FD)),
        hintStyle: const TextStyle(color: Color(0xFF6272A4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF44475A),
        selectedColor: const Color(0xFFBD93F9),
        labelStyle: const TextStyle(color: Color(0xFFF8F8F2)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF282A36)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF44475A)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF282A36)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF44475A),
        collapsedBackgroundColor: Color(0xFF282A36),
        iconColor: Color(0xFFBD93F9),
        collapsedIconColor: Color(0xFF6272A4),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildOceanicTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF263238),
      scaffoldBackgroundColor: const Color(0xFF263238),
      cardColor: const Color(0xFF37474F),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF80CBC4),
        secondary: Color(0xFF4FC3F7),
        surface: Color(0xFF37474F),
        background: Color(0xFF263238),
        error: Color(0xFFFF8A80),
        onPrimary: Color(0xFF263238),
        onSecondary: Color(0xFF263238),
        onSurface: Color(0xFFECEFF1),
        onBackground: Color(0xFFECEFF1),
        onError: Color(0xFF263238),
        outline: Color(0xFF546E7A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF263238),
        foregroundColor: Color(0xFFECEFF1),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF37474F),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF80CBC4),
          foregroundColor: const Color(0xFF263238),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF80CBC4),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF455A64),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF546E7A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF546E7A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF80CBC4)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
        hintStyle: const TextStyle(color: Color(0xFF607D8B)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF455A64),
        selectedColor: const Color(0xFF80CBC4),
        labelStyle: const TextStyle(color: Color(0xFFECEFF1)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF263238)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF455A64)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF37474F)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF455A64),
        collapsedBackgroundColor: Color(0xFF37474F),
        iconColor: Color(0xFF80CBC4),
        collapsedIconColor: Color(0xFF90A4AE),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }


  ThemeData _buildCobaltTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF193549),
      scaffoldBackgroundColor: const Color(0xFF193549),
      cardColor: const Color(0xFF1E415E),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF0088FF),
        secondary: Color(0xFFFFAA3E),
        surface: Color(0xFF1E415E),
        background: Color(0xFF193549),
        error: Color(0xFFFF628C),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFF193549),
        onSurface: Color(0xFFFFFFFF),
        onBackground: Color(0xFFFFFFFF),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFF335971),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF193549),
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF1E415E),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0088FF),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF0088FF),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF244C6A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF335971)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF335971)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0088FF)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF80B5DB)),
        hintStyle: const TextStyle(color: Color(0xFF5A7A92)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF244C6A),
        selectedColor: const Color(0xFF0088FF),
        labelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF244C6A)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF1E415E)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF244C6A),
        collapsedBackgroundColor: Color(0xFF1E415E),
        iconColor: Color(0xFF0088FF),
        collapsedIconColor: Color(0xFF80B5DB),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildMaterialTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF121212),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFBB86FC),
        secondary: Color(0xFF03DAC6),
        surface: Color(0xFF1E1E1E),
        background: Color(0xFF121212),
        error: Color(0xFFCF6679),
        onPrimary: Color(0xFF000000),
        onSecondary: Color(0xFF000000),
        onSurface: Color(0xFFFFFFFF),
        onBackground: Color(0xFFFFFFFF),
        onError: Color(0xFF000000),
        outline: Color(0xFF373737),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF1E1E1E),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFBB86FC),
          foregroundColor: const Color(0xFF000000),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFBB86FC),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF373737)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF373737)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFBB86FC)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF888888)),
        hintStyle: const TextStyle(color: Color(0xFF666666)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2C2C2C),
        selectedColor: const Color(0xFFBB86FC),
        labelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF000000)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF2C2C2C)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF1E1E1E)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF2C2C2C),
        collapsedBackgroundColor: Color(0xFF1E1E1E),
        iconColor: Color(0xFFBB86FC),
        collapsedIconColor: Color(0xFF888888),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildNordTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF2E3440),
      scaffoldBackgroundColor: const Color(0xFF2E3440),
      cardColor: const Color(0xFF3B4252),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF5E81AC),
        secondary: Color(0xFF88C0D0),
        surface: Color(0xFF3B4252),
        background: Color(0xFF2E3440),
        error: Color(0xFFBF616A),
        onPrimary: Color(0xFFECEFF4),
        onSecondary: Color(0xFF2E3440),
        onSurface: Color(0xFFECEFF4),
        onBackground: Color(0xFFECEFF4),
        onError: Color(0xFFECEFF4),
        outline: Color(0xFF434C5E),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2E3440),
        foregroundColor: Color(0xFFECEFF4),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF3B4252),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5E81AC),
          foregroundColor: const Color(0xFFECEFF4),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF5E81AC),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF434C5E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4C566A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4C566A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF5E81AC)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF81A1C1)),
        hintStyle: const TextStyle(color: Color(0xFF616E88)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF434C5E),
        selectedColor: const Color(0xFF5E81AC),
        labelStyle: const TextStyle(color: Color(0xFFECEFF4)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFECEFF4)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF434C5E)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF3B4252)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF434C5E),
        collapsedBackgroundColor: Color(0xFF3B4252),
        iconColor: Color(0xFF5E81AC),
        collapsedIconColor: Color(0xFF81A1C1),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildTokyoNightTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF1A1B26),
      scaffoldBackgroundColor: const Color(0xFF1A1B26),
      cardColor: const Color(0xFF24283B),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF7AA2F7),
        secondary: Color(0xFF9ECE6A),
        surface: Color(0xFF24283B),
        background: Color(0xFF1A1B26),
        error: Color(0xFFF7768E),
        onPrimary: Color(0xFFC0CAF5),
        onSecondary: Color(0xFF1A1B26),
        onSurface: Color(0xFFC0CAF5),
        onBackground: Color(0xFFC0CAF5),
        onError: Color(0xFFC0CAF5),
        outline: Color(0xFF3B4261),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1B26),
        foregroundColor: Color(0xFFC0CAF5),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF24283B),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7AA2F7),
          foregroundColor: const Color(0xFF1A1B26),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF7AA2F7),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF32344A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF414868)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF414868)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF7AA2F7)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF7DCFFF)),
        hintStyle: const TextStyle(color: Color(0xFF565F89)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF32344A),
        selectedColor: const Color(0xFF7AA2F7),
        labelStyle: const TextStyle(color: Color(0xFFC0CAF5)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF1A1B26)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF32344A)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF24283B)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF32344A),
        collapsedBackgroundColor: Color(0xFF24283B),
        iconColor: Color(0xFF7AA2F7),
        collapsedIconColor: Color(0xFF7DCFFF),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildGruvboxTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF1D2021),
      scaffoldBackgroundColor: const Color(0xFF1D2021),
      cardColor: const Color(0xFF282828),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFD79921),
        secondary: Color(0xFF98971A),
        surface: Color(0xFF282828),
        background: Color(0xFF1D2021),
        error: Color(0xFFCC241D),
        onPrimary: Color(0xFF1D2021),
        onSecondary: Color(0xFF1D2021),
        onSurface: Color(0xFFEBDBB2),
        onBackground: Color(0xFFEBDBB2),
        onError: Color(0xFFEBDBB2),
        outline: Color(0xFF3C3836),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1D2021),
        foregroundColor: Color(0xFFEBDBB2),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF282828),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD79921),
          foregroundColor: const Color(0xFF1D2021),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFD79921),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF3C3836),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF504945)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF504945)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD79921)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF83A598)),
        hintStyle: const TextStyle(color: Color(0xFF665C54)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF3C3836),
        selectedColor: const Color(0xFFD79921),
        labelStyle: const TextStyle(color: Color(0xFFEBDBB2)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF1D2021)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF3C3836)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF282828)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF3C3836),
        collapsedBackgroundColor: Color(0xFF282828),
        iconColor: Color(0xFFD79921),
        collapsedIconColor: Color(0xFF83A598),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildCatppuccinTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF1E1E2E),
      scaffoldBackgroundColor: const Color(0xFF1E1E2E),
      cardColor: const Color(0xFF313244),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFCBA6F7),
        secondary: Color(0xFFA6E3A1),
        surface: Color(0xFF313244),
        background: Color(0xFF1E1E2E),
        error: Color(0xFFF38BA8),
        onPrimary: Color(0xFF1E1E2E),
        onSecondary: Color(0xFF1E1E2E),
        onSurface: Color(0xFFCDD6F4),
        onBackground: Color(0xFFCDD6F4),
        onError: Color(0xFFCDD6F4),
        outline: Color(0xFF45475A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E2E),
        foregroundColor: Color(0xFFCDD6F4),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF313244),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFCBA6F7),
          foregroundColor: const Color(0xFF1E1E2E),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFCBA6F7),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF45475A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF585B70)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF585B70)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFCBA6F7)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF89B4FA)),
        hintStyle: const TextStyle(color: Color(0xFF6C7086)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF45475A),
        selectedColor: const Color(0xFFCBA6F7),
        labelStyle: const TextStyle(color: Color(0xFFCDD6F4)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF1E1E2E)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF45475A)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF313244)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF45475A),
        collapsedBackgroundColor: Color(0xFF313244),
        iconColor: Color(0xFFCBA6F7),
        collapsedIconColor: Color(0xFF89B4FA),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildSolarizedTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: const Color(0xFF002B36),
      scaffoldBackgroundColor: const Color(0xFF002B36),
      cardColor: const Color(0xFF073642),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF268BD2),
        secondary: Color(0xFF2AA198),
        surface: Color(0xFF073642),
        background: Color(0xFF002B36),
        error: Color(0xFFDC322F),
        onPrimary: Color(0xFFFDF6E3),
        onSecondary: Color(0xFF002B36),
        onSurface: Color(0xFFFDF6E3),
        onBackground: Color(0xFFFDF6E3),
        onError: Color(0xFFFDF6E3),
        outline: Color(0xFF586E75),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF002B36),
        foregroundColor: Color(0xFFFDF6E3),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF073642),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF268BD2),
          foregroundColor: const Color(0xFFFDF6E3),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF268BD2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF073642),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF586E75)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF586E75)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF268BD2)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF93A1A1)),
        hintStyle: const TextStyle(color: Color(0xFF657B83)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF073642),
        selectedColor: const Color(0xFF268BD2),
        labelStyle: const TextStyle(color: Color(0xFFFDF6E3)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFDF6E3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFF073642)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFF002B36)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF073642),
        collapsedBackgroundColor: Color(0xFF002B36),
        iconColor: Color(0xFF268BD2),
        collapsedIconColor: Color(0xFF93A1A1),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}