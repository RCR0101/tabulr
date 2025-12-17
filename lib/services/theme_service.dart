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

enum ThemeMode {
  dark,
  light,
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  AppTheme _currentTheme = AppTheme.githubDark;
  ThemeMode _currentThemeMode = ThemeMode.dark;
  static const String _themeKey = 'selected_theme';
  static const String _themeModeKey = 'theme_mode';

  AppTheme get currentTheme => _currentTheme;
  ThemeMode get currentThemeMode => _currentThemeMode;
  bool get isLightMode => _currentThemeMode == ThemeMode.light;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    final themeModeIndex = prefs.getInt(_themeModeKey) ?? 0;
    _currentTheme = AppTheme.values[themeIndex];
    _currentThemeMode = ThemeMode.values[themeModeIndex];
    notifyListeners();
  }

  Future<void> setTheme(AppTheme theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, theme.index);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _currentThemeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> toggleThemeMode() async {
    final newMode = _currentThemeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
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
        return isLightMode ? _buildGitHubLightTheme() : _buildGitHubTheme();
      case AppTheme.draculaDark:
        return isLightMode ? _buildDraculaLightTheme() : _buildDraculaTheme();
      case AppTheme.oceanicDark:
        return isLightMode ? _buildOceanicLightTheme() : _buildOceanicTheme();
      case AppTheme.cobaltDark:
        return isLightMode ? _buildCobaltLightTheme() : _buildCobaltTheme();
      case AppTheme.materialDark:
        return isLightMode ? _buildMaterialLightTheme() : _buildMaterialTheme();
      case AppTheme.nordDark:
        return isLightMode ? _buildNordLightTheme() : _buildNordTheme();
      case AppTheme.tokyoNightDark:
        return isLightMode ? _buildTokyoNightLightTheme() : _buildTokyoNightTheme();
      case AppTheme.gruvboxDark:
        return isLightMode ? _buildGruvboxLightTheme() : _buildGruvboxTheme();
      case AppTheme.catppuccinDark:
        return isLightMode ? _buildCatppuccinLightTheme() : _buildCatppuccinTheme();
      case AppTheme.solarizedDark:
        return isLightMode ? _buildSolarizedLightTheme() : _buildSolarizedTheme();
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
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

  // Light theme variants
  ThemeData _buildGitHubLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFFFFFFF),
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      cardColor: const Color(0xFFF6F8FA),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0969DA),
        secondary: Color(0xFF1F883D),
        surface: Color(0xFFF6F8FA),
        background: Color(0xFFFFFFFF),
        error: Color(0xFFDA3633),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF24292F),
        onBackground: Color(0xFF24292F),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFFD0D7DE),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF24292F),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFF6F8FA),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0969DA),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF0969DA),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD0D7DE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD0D7DE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0969DA)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF656D76)),
        hintStyle: const TextStyle(color: Color(0xFF8C959F)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF6F8FA),
        selectedColor: const Color(0xFF0969DA),
        labelStyle: const TextStyle(color: Color(0xFF24292F)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFF6F8FA)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFF6F8FA),
        collapsedBackgroundColor: Color(0xFFFFFFFF),
        iconColor: Color(0xFF0969DA),
        collapsedIconColor: Color(0xFF656D76),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildDraculaLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFF8F8F2),
      scaffoldBackgroundColor: const Color(0xFFF8F8F2),
      cardColor: const Color(0xFFFFFFFF),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6272A4),
        secondary: Color(0xFF50FA7B),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFF8F8F2),
        error: Color(0xFFFF5555),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFF282A36),
        onSurface: Color(0xFF282A36),
        onBackground: Color(0xFF282A36),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFF44475A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF8F8F2),
        foregroundColor: Color(0xFF282A36),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6272A4),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6272A4),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF44475A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF44475A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6272A4)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF6272A4)),
        hintStyle: const TextStyle(color: Color(0xFF44475A)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: const Color(0xFF6272A4),
        labelStyle: const TextStyle(color: Color(0xFF282A36)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFF8F8F2)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        collapsedBackgroundColor: Color(0xFFF8F8F2),
        iconColor: Color(0xFF6272A4),
        collapsedIconColor: Color(0xFF44475A),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildOceanicLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFECEFF1),
      scaffoldBackgroundColor: const Color(0xFFECEFF1),
      cardColor: const Color(0xFFFFFFFF),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF00695C),
        secondary: Color(0xFF00ACC1),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFECEFF1),
        error: Color(0xFFD32F2F),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF263238),
        onBackground: Color(0xFF263238),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFF90A4AE),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFECEFF1),
        foregroundColor: Color(0xFF263238),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00695C),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF00695C),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF90A4AE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF90A4AE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF00695C)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF546E7A)),
        hintStyle: const TextStyle(color: Color(0xFF90A4AE)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: const Color(0xFF00695C),
        labelStyle: const TextStyle(color: Color(0xFF263238)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFECEFF1)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        collapsedBackgroundColor: Color(0xFFECEFF1),
        iconColor: Color(0xFF00695C),
        collapsedIconColor: Color(0xFF546E7A),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildCobaltLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFFFFFFF),
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      cardColor: const Color(0xFFF5F9FC),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0969DA),
        secondary: Color(0xFFFF8800),
        surface: Color(0xFFF5F9FC),
        background: Color(0xFFFFFFFF),
        error: Color(0xFFDA1E28),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF193549),
        onBackground: Color(0xFF193549),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFF8FA4B3),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF193549),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFF5F9FC),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0969DA),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF0969DA),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF8FA4B3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF8FA4B3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0969DA)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF5A7A92)),
        hintStyle: const TextStyle(color: Color(0xFF8FA4B3)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: const Color(0xFF0969DA),
        labelStyle: const TextStyle(color: Color(0xFF193549)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFF5F9FC)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFF5F9FC),
        collapsedBackgroundColor: Color(0xFFFFFFFF),
        iconColor: Color(0xFF0969DA),
        collapsedIconColor: Color(0xFF5A7A92),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildMaterialLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFFFFFFF),
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      cardColor: const Color(0xFFFAFAFA),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6200EE),
        secondary: Color(0xFF018786),
        surface: Color(0xFFFAFAFA),
        background: Color(0xFFFFFFFF),
        error: Color(0xFFB00020),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF000000),
        onBackground: Color(0xFF000000),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFFE0E0E0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF000000),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFAFAFA),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6200EE),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6200EE),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6200EE)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF757575)),
        hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: const Color(0xFF6200EE),
        labelStyle: const TextStyle(color: Color(0xFF000000)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFFAFAFA)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFFAFAFA),
        collapsedBackgroundColor: Color(0xFFFFFFFF),
        iconColor: Color(0xFF6200EE),
        collapsedIconColor: Color(0xFF757575),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildNordLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFECEFF4),
      scaffoldBackgroundColor: const Color(0xFFECEFF4),
      cardColor: const Color(0xFFFFFFFF),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF5E81AC),
        secondary: Color(0xFF81A1C1),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFECEFF4),
        error: Color(0xFFBF616A),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFF2E3440),
        onSurface: Color(0xFF2E3440),
        onBackground: Color(0xFF2E3440),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFFD8DEE9),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFECEFF4),
        foregroundColor: Color(0xFF2E3440),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5E81AC),
          foregroundColor: const Color(0xFFFFFFFF),
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
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD8DEE9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD8DEE9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF5E81AC)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF4C566A)),
        hintStyle: const TextStyle(color: Color(0xFFD8DEE9)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: const Color(0xFF5E81AC),
        labelStyle: const TextStyle(color: Color(0xFF2E3440)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFECEFF4)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        collapsedBackgroundColor: Color(0xFFECEFF4),
        iconColor: Color(0xFF5E81AC),
        collapsedIconColor: Color(0xFF4C566A),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildTokyoNightLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFFFFFFF),
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      cardColor: const Color(0xFFF7F7F7),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF3D59A1),
        secondary: Color(0xFF33635C),
        surface: Color(0xFFF7F7F7),
        background: Color(0xFFFFFFFF),
        error: Color(0xFFCC517A),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1A1B26),
        onBackground: Color(0xFF1A1B26),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFFE1E2E7),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF1A1B26),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFF7F7F7),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3D59A1),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF3D59A1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE1E2E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE1E2E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3D59A1)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF6172B0)),
        hintStyle: const TextStyle(color: Color(0xFFA9B1D6)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: const Color(0xFF3D59A1),
        labelStyle: const TextStyle(color: Color(0xFF1A1B26)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFF7F7F7)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFFFFFFF)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFF7F7F7),
        collapsedBackgroundColor: Color(0xFFFFFFFF),
        iconColor: Color(0xFF3D59A1),
        collapsedIconColor: Color(0xFF6172B0),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildGruvboxLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFFBF1C7),
      scaffoldBackgroundColor: const Color(0xFFFBF1C7),
      cardColor: const Color(0xFFF2E5BC),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFB57614),
        secondary: Color(0xFF79740E),
        surface: Color(0xFFF2E5BC),
        background: Color(0xFFFBF1C7),
        error: Color(0xFF9D0006),
        onPrimary: Color(0xFFFBF1C7),
        onSecondary: Color(0xFFFBF1C7),
        onSurface: Color(0xFF3C3836),
        onBackground: Color(0xFF3C3836),
        onError: Color(0xFFFBF1C7),
        outline: Color(0xFFD5C4A1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFBF1C7),
        foregroundColor: Color(0xFF3C3836),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFF2E5BC),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB57614),
          foregroundColor: const Color(0xFFFBF1C7),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFB57614),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2E5BC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD5C4A1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD5C4A1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFB57614)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF076678)),
        hintStyle: const TextStyle(color: Color(0xFFBDAE93)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF2E5BC),
        selectedColor: const Color(0xFFB57614),
        labelStyle: const TextStyle(color: Color(0xFF3C3836)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFBF1C7)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFF2E5BC)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFFBF1C7)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFF2E5BC),
        collapsedBackgroundColor: Color(0xFFFBF1C7),
        iconColor: Color(0xFFB57614),
        collapsedIconColor: Color(0xFF076678),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildCatppuccinLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFEFF1F5),
      scaffoldBackgroundColor: const Color(0xFFEFF1F5),
      cardColor: const Color(0xFFE6E9EF),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF7C7F93),
        secondary: Color(0xFF40A02B),
        surface: Color(0xFFE6E9EF),
        background: Color(0xFFEFF1F5),
        error: Color(0xFFD20F39),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF4C4F69),
        onBackground: Color(0xFF4C4F69),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFFDCE0E8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFEFF1F5),
        foregroundColor: Color(0xFF4C4F69),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFE6E9EF),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C7F93),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF7C7F93),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFE6E9EF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDCE0E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDCE0E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF7C7F93)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF1E66F5)),
        hintStyle: const TextStyle(color: Color(0xFF9CA0B0)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE6E9EF),
        selectedColor: const Color(0xFF7C7F93),
        labelStyle: const TextStyle(color: Color(0xFF4C4F69)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFE6E9EF)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFEFF1F5)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFE6E9EF),
        collapsedBackgroundColor: Color(0xFFEFF1F5),
        iconColor: Color(0xFF7C7F93),
        collapsedIconColor: Color(0xFF1E66F5),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildSolarizedLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFFDF6E3),
      scaffoldBackgroundColor: const Color(0xFFFDF6E3),
      cardColor: const Color(0xFFEEE8D5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF268BD2),
        secondary: Color(0xFF2AA198),
        surface: Color(0xFFEEE8D5),
        background: Color(0xFFFDF6E3),
        error: Color(0xFFDC322F),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF002B36),
        onBackground: Color(0xFF002B36),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFF93A1A1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFDF6E3),
        foregroundColor: Color(0xFF002B36),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFEEE8D5),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF268BD2),
          foregroundColor: const Color(0xFFFFFFFF),
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
        fillColor: const Color(0xFFEEE8D5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF93A1A1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF93A1A1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF268BD2)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF586E75)),
        hintStyle: const TextStyle(color: Color(0xFF93A1A1)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEEE8D5),
        selectedColor: const Color(0xFF268BD2),
        labelStyle: const TextStyle(color: Color(0xFF002B36)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFEEE8D5)),
        dataRowColor: MaterialStateProperty.all(const Color(0xFFFDF6E3)),
        dividerThickness: 1,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFFEEE8D5),
        collapsedBackgroundColor: Color(0xFFFDF6E3),
        iconColor: Color(0xFF268BD2),
        collapsedIconColor: Color(0xFF586E75),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}