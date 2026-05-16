import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  githubDark('GitHub Dark', Icons.code),
  draculaDark('Dracula', Icons.brightness_2),
  oceanicDark('Oceanic', Icons.waves),
  cobaltDark('Cobalt Blue', Icons.blur_on),
  materialDark('Material Dark', Icons.android),
  nordDark('Nord', Icons.ac_unit),
  tokyoNightDark('Tokyo Night', Icons.nightlight_round),
  gruvboxDark('Gruvbox', Icons.grain),
  catppuccinDark('Catppuccin', Icons.pets),
  solarizedDark('Solarized Dark', Icons.wb_sunny),
  sunsetOrange('Sunset Orange', Icons.wb_twilight),
  forestGreen('Forest Green', Icons.forest),
  royalPurple('Royal Purple', Icons.diamond),
  crimsonRed('Crimson Red', Icons.local_fire_department),
  electricBlue('Electric Blue', Icons.flash_on),
  blackGold('Black Gold', Icons.auto_awesome),
  midnightTerminal('Midnight Terminal', Icons.computer),
  roseQuartz('Rose Quartz', Icons.spa),
  arcticFrost('Arctic Frost', Icons.severe_cold),
  espresso('Espresso', Icons.coffee),
  ;

  const AppTheme(this.displayName, this.icon);
  final String displayName;
  final IconData icon;
}

class _ThemeColors {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color error;
  final Color onPrimary;
  final Color onSecondary;
  final Color onSurface;
  final Color onError;
  final Color outline;
  final double cardElevation;
  final double buttonElevation;
  final Color? inputFill;
  final Color? borderColor;
  final Color? labelColor;
  final Color? hintColor;
  final double focusedBorderWidth;
  final Color? chipBgColor;
  final Color? headingRowColor;
  final Color? dataRowColor;
  final Color? collapsedIconColor;
  final Color? buttonForeground;
  final Color? chipSecondaryLabel;
  final Color? appBarForeground;
  final Color? cardShadowColor;
  final Color? buttonShadowColor;
  final Color? surfaceContainerHighest;
  final Color? surfaceContainer;
  final Color? surfaceContainerHigh;
  final Color? surfaceContainerLow;

  const _ThemeColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.error,
    required this.onPrimary,
    required this.onSecondary,
    required this.onSurface,
    required this.onError,
    required this.outline,
    this.cardElevation = 2,
    this.buttonElevation = 1,
    this.inputFill,
    this.borderColor,
    this.labelColor,
    this.hintColor,
    this.focusedBorderWidth = 1.0,
    this.chipBgColor,
    this.headingRowColor,
    this.dataRowColor,
    this.collapsedIconColor,
    this.buttonForeground,
    this.chipSecondaryLabel,
    this.appBarForeground,
    this.cardShadowColor,
    this.buttonShadowColor,
    this.surfaceContainerHighest,
    this.surfaceContainer,
    this.surfaceContainerHigh,
    this.surfaceContainerLow,
  });
}

const _themeColors = <AppTheme, ({_ThemeColors dark, _ThemeColors light})>{
  AppTheme.githubDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF0D1117),
      surface: Color(0xFF161B22),
      primary: Color(0xFF58A6FF),
      secondary: Color(0xFF56D364),
      error: Color(0xFFFF6B6B),
      onPrimary: Color(0xFF0D1117),
      onSecondary: Color(0xFF0D1117),
      onSurface: Color(0xFFF0F6FC),
      onError: Color(0xFF0D1117),
      outline: Color(0xFF30363D),
      inputFill: Color(0xFF21262D),
      labelColor: Color(0xFF8B949E),
      hintColor: Color(0xFF6E7681),
      headingRowColor: Color(0xFF21262D),
      dataRowColor: Color(0xFF161B22),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF6F8FA),
      primary: Color(0xFF0969DA),
      secondary: Color(0xFF1F883D),
      error: Color(0xFFDA3633),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF24292F),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFD0D7DE),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF656D76),
      hintColor: Color(0xFF8C959F),
      chipBgColor: Color(0xFFF6F8FA),
      headingRowColor: Color(0xFFF6F8FA),
      dataRowColor: Color(0xFFFFFFFF),
    ),
  ),
  AppTheme.draculaDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF282A36),
      surface: Color(0xFF44475A),
      primary: Color(0xFFBD93F9),
      secondary: Color(0xFF50FA7B),
      error: Color(0xFFFF5555),
      onPrimary: Color(0xFF282A36),
      onSecondary: Color(0xFF282A36),
      onSurface: Color(0xFFF8F8F2),
      onError: Color(0xFF282A36),
      outline: Color(0xFF6272A4),
      inputFill: Color(0xFF44475A),
      labelColor: Color(0xFF8BE9FD),
      hintColor: Color(0xFF6272A4),
      headingRowColor: Color(0xFF44475A),
      dataRowColor: Color(0xFF282A36),
      collapsedIconColor: Color(0xFF6272A4),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF8F8F2),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF6272A4),
      secondary: Color(0xFF50FA7B),
      error: Color(0xFFFF5555),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF282A36),
      onSurface: Color(0xFF282A36),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF44475A),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF6272A4),
      hintColor: Color(0xFF44475A),
      headingRowColor: Color(0xFFFFFFFF),
      dataRowColor: Color(0xFFF8F8F2),
      collapsedIconColor: Color(0xFF44475A),
    ),
  ),
  AppTheme.oceanicDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF263238),
      surface: Color(0xFF37474F),
      primary: Color(0xFF80CBC4),
      secondary: Color(0xFF4FC3F7),
      error: Color(0xFFFF8A80),
      onPrimary: Color(0xFF263238),
      onSecondary: Color(0xFF263238),
      onSurface: Color(0xFFECEFF1),
      onError: Color(0xFF263238),
      outline: Color(0xFF546E7A),
      inputFill: Color(0xFF455A64),
      labelColor: Color(0xFF90A4AE),
      hintColor: Color(0xFF607D8B),
      headingRowColor: Color(0xFF455A64),
      dataRowColor: Color(0xFF37474F),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFECEFF1),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF00695C),
      secondary: Color(0xFF00ACC1),
      error: Color(0xFFD32F2F),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF263238),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF90A4AE),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF546E7A),
      hintColor: Color(0xFF90A4AE),
      headingRowColor: Color(0xFFFFFFFF),
      dataRowColor: Color(0xFFECEFF1),
    ),
  ),
  AppTheme.cobaltDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF193549),
      surface: Color(0xFF1E415E),
      primary: Color(0xFF0088FF),
      secondary: Color(0xFFFFAA3E),
      error: Color(0xFFFF628C),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF193549),
      onSurface: Color(0xFFFFFFFF),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF335971),
      inputFill: Color(0xFF244C6A),
      labelColor: Color(0xFF80B5DB),
      hintColor: Color(0xFF5A7A92),
      headingRowColor: Color(0xFF244C6A),
      dataRowColor: Color(0xFF1E415E),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF5F9FC),
      primary: Color(0xFF0969DA),
      secondary: Color(0xFFFF8800),
      error: Color(0xFFDA1E28),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF193549),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF8FA4B3),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF5A7A92),
      hintColor: Color(0xFF8FA4B3),
      headingRowColor: Color(0xFFF5F9FC),
      dataRowColor: Color(0xFFFFFFFF),
    ),
  ),
  AppTheme.materialDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF121212),
      surface: Color(0xFF1E1E1E),
      primary: Color(0xFFBB86FC),
      secondary: Color(0xFF03DAC6),
      error: Color(0xFFCF6679),
      onPrimary: Color(0xFF000000),
      onSecondary: Color(0xFF000000),
      onSurface: Color(0xFFFFFFFF),
      onError: Color(0xFF000000),
      outline: Color(0xFF373737),
      inputFill: Color(0xFF2C2C2C),
      labelColor: Color(0xFF888888),
      hintColor: Color(0xFF666666),
      headingRowColor: Color(0xFF2C2C2C),
      dataRowColor: Color(0xFF1E1E1E),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFAFAFA),
      primary: Color(0xFF6200EE),
      secondary: Color(0xFF018786),
      error: Color(0xFFB00020),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF000000),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFE0E0E0),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF757575),
      hintColor: Color(0xFF9E9E9E),
      headingRowColor: Color(0xFFFAFAFA),
      dataRowColor: Color(0xFFFFFFFF),
    ),
  ),
  AppTheme.nordDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF2E3440),
      surface: Color(0xFF3B4252),
      primary: Color(0xFF5E81AC),
      secondary: Color(0xFF88C0D0),
      error: Color(0xFFBF616A),
      onPrimary: Color(0xFFECEFF4),
      onSecondary: Color(0xFF2E3440),
      onSurface: Color(0xFFECEFF4),
      onError: Color(0xFFECEFF4),
      outline: Color(0xFF434C5E),
      inputFill: Color(0xFF434C5E),
      borderColor: Color(0xFF4C566A),
      labelColor: Color(0xFF81A1C1),
      hintColor: Color(0xFF616E88),
      headingRowColor: Color(0xFF434C5E),
      dataRowColor: Color(0xFF3B4252),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFECEFF4),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF5E81AC),
      secondary: Color(0xFF81A1C1),
      error: Color(0xFFBF616A),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF2E3440),
      onSurface: Color(0xFF2E3440),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFD8DEE9),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF4C566A),
      hintColor: Color(0xFFD8DEE9),
      headingRowColor: Color(0xFFFFFFFF),
      dataRowColor: Color(0xFFECEFF4),
    ),
  ),
  AppTheme.tokyoNightDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1A1B26),
      surface: Color(0xFF24283B),
      primary: Color(0xFF7AA2F7),
      secondary: Color(0xFF9ECE6A),
      error: Color(0xFFF7768E),
      onPrimary: Color(0xFFC0CAF5),
      onSecondary: Color(0xFF1A1B26),
      onSurface: Color(0xFFC0CAF5),
      onError: Color(0xFFC0CAF5),
      outline: Color(0xFF3B4261),
      inputFill: Color(0xFF32344A),
      borderColor: Color(0xFF414868),
      labelColor: Color(0xFF7DCFFF),
      hintColor: Color(0xFF565F89),
      headingRowColor: Color(0xFF32344A),
      dataRowColor: Color(0xFF24283B),
      buttonForeground: Color(0xFF1A1B26),
      chipSecondaryLabel: Color(0xFF1A1B26),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF7F7F7),
      primary: Color(0xFF3D59A1),
      secondary: Color(0xFF33635C),
      error: Color(0xFFCC517A),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1A1B26),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFE1E2E7),
      inputFill: Color(0xFFFFFFFF),
      labelColor: Color(0xFF6172B0),
      hintColor: Color(0xFFA9B1D6),
      headingRowColor: Color(0xFFF7F7F7),
      dataRowColor: Color(0xFFFFFFFF),
    ),
  ),
  AppTheme.gruvboxDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1D2021),
      surface: Color(0xFF282828),
      primary: Color(0xFFD79921),
      secondary: Color(0xFF98971A),
      error: Color(0xFFCC241D),
      onPrimary: Color(0xFF1D2021),
      onSecondary: Color(0xFF1D2021),
      onSurface: Color(0xFFEBDBB2),
      onError: Color(0xFFEBDBB2),
      outline: Color(0xFF3C3836),
      inputFill: Color(0xFF3C3836),
      borderColor: Color(0xFF504945),
      labelColor: Color(0xFF83A598),
      hintColor: Color(0xFF665C54),
      headingRowColor: Color(0xFF3C3836),
      dataRowColor: Color(0xFF282828),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFBF1C7),
      surface: Color(0xFFF2E5BC),
      primary: Color(0xFFB57614),
      secondary: Color(0xFF79740E),
      error: Color(0xFF9D0006),
      onPrimary: Color(0xFFFBF1C7),
      onSecondary: Color(0xFFFBF1C7),
      onSurface: Color(0xFF3C3836),
      onError: Color(0xFFFBF1C7),
      outline: Color(0xFFD5C4A1),
      inputFill: Color(0xFFF2E5BC),
      labelColor: Color(0xFF076678),
      hintColor: Color(0xFFBDAE93),
      headingRowColor: Color(0xFFF2E5BC),
      dataRowColor: Color(0xFFFBF1C7),
    ),
  ),
  AppTheme.catppuccinDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1E1E2E),
      surface: Color(0xFF313244),
      primary: Color(0xFFCBA6F7),
      secondary: Color(0xFFA6E3A1),
      error: Color(0xFFF38BA8),
      onPrimary: Color(0xFF1E1E2E),
      onSecondary: Color(0xFF1E1E2E),
      onSurface: Color(0xFFCDD6F4),
      onError: Color(0xFFCDD6F4),
      outline: Color(0xFF45475A),
      inputFill: Color(0xFF45475A),
      borderColor: Color(0xFF585B70),
      labelColor: Color(0xFF89B4FA),
      hintColor: Color(0xFF6C7086),
      headingRowColor: Color(0xFF45475A),
      dataRowColor: Color(0xFF313244),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFEFF1F5),
      surface: Color(0xFFE6E9EF),
      primary: Color(0xFF7C7F93),
      secondary: Color(0xFF40A02B),
      error: Color(0xFFD20F39),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF4C4F69),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFDCE0E8),
      inputFill: Color(0xFFE6E9EF),
      labelColor: Color(0xFF1E66F5),
      hintColor: Color(0xFF9CA0B0),
      headingRowColor: Color(0xFFE6E9EF),
      dataRowColor: Color(0xFFEFF1F5),
    ),
  ),
  AppTheme.solarizedDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF002B36),
      surface: Color(0xFF073642),
      primary: Color(0xFF268BD2),
      secondary: Color(0xFF2AA198),
      error: Color(0xFFDC322F),
      onPrimary: Color(0xFFFDF6E3),
      onSecondary: Color(0xFF002B36),
      onSurface: Color(0xFFFDF6E3),
      onError: Color(0xFFFDF6E3),
      outline: Color(0xFF586E75),
      inputFill: Color(0xFF073642),
      labelColor: Color(0xFF93A1A1),
      hintColor: Color(0xFF657B83),
      headingRowColor: Color(0xFF073642),
      dataRowColor: Color(0xFF002B36),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFDF6E3),
      surface: Color(0xFFEEE8D5),
      primary: Color(0xFF268BD2),
      secondary: Color(0xFF2AA198),
      error: Color(0xFFDC322F),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF002B36),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF93A1A1),
      inputFill: Color(0xFFEEE8D5),
      labelColor: Color(0xFF586E75),
      hintColor: Color(0xFF93A1A1),
      headingRowColor: Color(0xFFEEE8D5),
      dataRowColor: Color(0xFFFDF6E3),
    ),
  ),
  AppTheme.sunsetOrange: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1A0F0A),
      surface: Color(0xFF2D1B10),
      primary: Color(0xFFFF8A50),
      secondary: Color(0xFFFFAB40),
      error: Color(0xFFFF6B6B),
      onPrimary: Color(0xFF1A0F0A),
      onSecondary: Color(0xFF1A0F0A),
      onSurface: Color(0xFFFFF8F0),
      onError: Color(0xFF1A0F0A),
      outline: Color(0xFF5C3D28),
      cardElevation: 3,
      buttonElevation: 2,
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFF8F0),
      surface: Color(0xFFFEF2E4),
      primary: Color(0xFFFF6B35),
      secondary: Color(0xFFFF8C42),
      error: Color(0xFFE53E3E),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF2D1B0D),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFD4A574),
      cardElevation: 3,
      buttonElevation: 2,
      inputFill: Color(0xFFFEF2E4),
      labelColor: Color(0xFFCC5500),
      hintColor: Color(0xFFD4A574),
      focusedBorderWidth: 2,
    ),
  ),
  AppTheme.forestGreen: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF0A1A0A),
      surface: Color(0xFF1B2D1B),
      primary: Color(0xFF66BB6A),
      secondary: Color(0xFF81C784),
      error: Color(0xFFEF5350),
      onPrimary: Color(0xFF0A1A0A),
      onSecondary: Color(0xFF0A1A0A),
      onSurface: Color(0xFFF0F8F0),
      onError: Color(0xFF0A1A0A),
      outline: Color(0xFF2E5C2E),
      cardElevation: 3,
      buttonElevation: 2,
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF0F8F0),
      surface: Color(0xFFE8F5E8),
      primary: Color(0xFF2E7D32),
      secondary: Color(0xFF4CAF50),
      error: Color(0xFFC62828),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1B5E20),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF81C784),
      cardElevation: 3,
      buttonElevation: 2,
    ),
  ),
  AppTheme.royalPurple: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1A0A1A),
      surface: Color(0xFF2D1B2D),
      primary: Color(0xFFBA68C8),
      secondary: Color(0xFFCE93D8),
      error: Color(0xFFF06292),
      onPrimary: Color(0xFF1A0A1A),
      onSecondary: Color(0xFF1A0A1A),
      onSurface: Color(0xFFF8F0FF),
      onError: Color(0xFF1A0A1A),
      outline: Color(0xFF5C285C),
      cardElevation: 3,
      buttonElevation: 2,
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF8F0FF),
      surface: Color(0xFFF0E4FF),
      primary: Color(0xFF7B1FA2),
      secondary: Color(0xFF9C27B0),
      error: Color(0xFFAD1457),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF4A148C),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFBA68C8),
      cardElevation: 3,
      buttonElevation: 2,
    ),
  ),
  AppTheme.crimsonRed: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1A0A0A),
      surface: Color(0xFF2D1010),
      primary: Color(0xFFEF5350),
      secondary: Color(0xFFE57373),
      error: Color(0xFFFF5722),
      onPrimary: Color(0xFF1A0A0A),
      onSecondary: Color(0xFF1A0A0A),
      onSurface: Color(0xFFFFF0F0),
      onError: Color(0xFF1A0A0A),
      outline: Color(0xFF5C2828),
      cardElevation: 3,
      buttonElevation: 2,
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFF0F0),
      surface: Color(0xFFFFE4E4),
      primary: Color(0xFFD32F2F),
      secondary: Color(0xFFE57373),
      error: Color(0xFFB71C1C),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF8B0000),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFEF9A9A),
      cardElevation: 3,
      buttonElevation: 2,
    ),
  ),
  AppTheme.electricBlue: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF0A0F1A),
      surface: Color(0xFF101B2D),
      primary: Color(0xFF64B5F6),
      secondary: Color(0xFF90CAF9),
      error: Color(0xFF2196F3),
      onPrimary: Color(0xFF0A0F1A),
      onSecondary: Color(0xFF0A0F1A),
      onSurface: Color(0xFFF0F8FF),
      onError: Color(0xFF0A0F1A),
      outline: Color(0xFF28385C),
      cardElevation: 3,
      buttonElevation: 2,
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF0F8FF),
      surface: Color(0xFFE4F2FF),
      primary: Color(0xFF1976D2),
      secondary: Color(0xFF42A5F5),
      error: Color(0xFF1565C0),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0D47A1),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFF90CAF9),
      cardElevation: 3,
      buttonElevation: 2,
    ),
  ),
  AppTheme.blackGold: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF000000),
      surface: Color(0xFF1A1A1A),
      primary: Color(0xFFD4AF37),
      secondary: Color(0xFFD4A574),
      error: Color(0xFFCF6679),
      onPrimary: Color(0xFF000000),
      onSecondary: Color(0xFF000000),
      onSurface: Color(0xFFFFFFFF),
      onError: Color(0xFF000000),
      outline: Color(0xFF333333),
      cardElevation: 6,
      buttonElevation: 4,
      inputFill: Color(0xFF1A1A1A),
      labelColor: Color(0xFFD4A574),
      hintColor: Color(0xFF666666),
      focusedBorderWidth: 2,
      headingRowColor: Color(0xFF2C2C2C),
      dataRowColor: Color(0xFF1A1A1A),
      appBarForeground: Color(0xFFD4AF37),
      cardShadowColor: Color(0x33D4AF37),
      buttonShadowColor: Color(0x66D4AF37),
      surfaceContainerHighest: Color(0xFF2C2C2C),
      surfaceContainer: Color(0xFF1F1F1F),
      surfaceContainerHigh: Color(0xFF262626),
      surfaceContainerLow: Color(0xFF141414),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFFDF7),
      surface: Color(0xFFFFFAF0),
      primary: Color(0xFFD4A574),
      secondary: Color(0xFFD4AF37),
      error: Color(0xFFB00020),
      onPrimary: Color(0xFF1A1A1A),
      onSecondary: Color(0xFF1A1A1A),
      onSurface: Color(0xFF2C2C2C),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFE6C68A),
      cardElevation: 4,
      buttonElevation: 3,
      inputFill: Color(0xFFFFFAF0),
      labelColor: Color(0xFFB8860B),
      hintColor: Color(0xFFE6C68A),
      focusedBorderWidth: 2,
      cardShadowColor: Color(0x4DD4A574),
      buttonShadowColor: Color(0x80D4A574),
    ),
  ),
  AppTheme.midnightTerminal: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF0A0E14),
      surface: Color(0xFF111921),
      primary: Color(0xFF39BAE6),
      secondary: Color(0xFF59C2FF),
      error: Color(0xFFFF3333),
      onPrimary: Color(0xFF0A0E14),
      onSecondary: Color(0xFF0A0E14),
      onSurface: Color(0xFFB3B1AD),
      onError: Color(0xFF0A0E14),
      outline: Color(0xFF1D2B3A),
      cardElevation: 0,
      buttonElevation: 0,
      inputFill: Color(0xFF0D1117),
      labelColor: Color(0xFF39BAE6),
      hintColor: Color(0xFF475B6E),
      focusedBorderWidth: 1,
      headingRowColor: Color(0xFF131B24),
      dataRowColor: Color(0xFF0D1117),
      appBarForeground: Color(0xFF39BAE6),
      surfaceContainerHighest: Color(0xFF1D2B3A),
      surfaceContainer: Color(0xFF151D27),
      surfaceContainerHigh: Color(0xFF19232F),
      surfaceContainerLow: Color(0xFF0D1117),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF0F4F8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF0D7FA5),
      secondary: Color(0xFF1A8FC4),
      error: Color(0xFFD32F2F),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1A2B3C),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFCCD6E0),
      inputFill: Color(0xFFF5F8FA),
      labelColor: Color(0xFF0D7FA5),
      hintColor: Color(0xFF8A99A8),
    ),
  ),
  AppTheme.roseQuartz: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1A1018),
      surface: Color(0xFF241A22),
      primary: Color(0xFFE8A0BF),
      secondary: Color(0xFFD4A0C0),
      error: Color(0xFFFF6B6B),
      onPrimary: Color(0xFF1A1018),
      onSecondary: Color(0xFF1A1018),
      onSurface: Color(0xFFE8D5E0),
      onError: Color(0xFF1A1018),
      outline: Color(0xFF3D2A38),
      cardElevation: 2,
      buttonElevation: 1,
      inputFill: Color(0xFF201620),
      labelColor: Color(0xFFE8A0BF),
      hintColor: Color(0xFF6B4E64),
      focusedBorderWidth: 1.5,
      headingRowColor: Color(0xFF2A1E28),
      dataRowColor: Color(0xFF201620),
      appBarForeground: Color(0xFFE8A0BF),
      cardShadowColor: Color(0x33E8A0BF),
      surfaceContainerHighest: Color(0xFF3D2A38),
      surfaceContainer: Color(0xFF2A1E28),
      surfaceContainerHigh: Color(0xFF33242F),
      surfaceContainerLow: Color(0xFF1D131B),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFF5F9),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFBF5A7E),
      secondary: Color(0xFFAD6B8E),
      error: Color(0xFFD32F2F),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF3D2A38),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFE8C5D5),
      inputFill: Color(0xFFFFF0F5),
      labelColor: Color(0xFFBF5A7E),
      hintColor: Color(0xFFC9A0B5),
      cardShadowColor: Color(0x33BF5A7E),
    ),
  ),
  AppTheme.arcticFrost: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF0B1621),
      surface: Color(0xFF122032),
      primary: Color(0xFF88C0D0),
      secondary: Color(0xFF81A1C1),
      error: Color(0xFFBF616A),
      onPrimary: Color(0xFF0B1621),
      onSecondary: Color(0xFF0B1621),
      onSurface: Color(0xFFD8DEE9),
      onError: Color(0xFF0B1621),
      outline: Color(0xFF2E4057),
      cardElevation: 1,
      buttonElevation: 0,
      inputFill: Color(0xFF0F1C2A),
      labelColor: Color(0xFF88C0D0),
      hintColor: Color(0xFF4C6A85),
      focusedBorderWidth: 1,
      headingRowColor: Color(0xFF172638),
      dataRowColor: Color(0xFF0F1C2A),
      appBarForeground: Color(0xFF88C0D0),
      surfaceContainerHighest: Color(0xFF2E4057),
      surfaceContainer: Color(0xFF1A2D42),
      surfaceContainerHigh: Color(0xFF24374D),
      surfaceContainerLow: Color(0xFF0D1925),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF2F7FB),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF4A90A4),
      secondary: Color(0xFF5E81AC),
      error: Color(0xFFBF616A),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF2E3440),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFD0DBE6),
      inputFill: Color(0xFFF5F9FC),
      labelColor: Color(0xFF4A90A4),
      hintColor: Color(0xFF94A8BC),
    ),
  ),
  AppTheme.espresso: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1B1210),
      surface: Color(0xFF261B17),
      primary: Color(0xFFD4A574),
      secondary: Color(0xFFC49A6C),
      error: Color(0xFFE57373),
      onPrimary: Color(0xFF1B1210),
      onSecondary: Color(0xFF1B1210),
      onSurface: Color(0xFFE8DDD5),
      onError: Color(0xFF1B1210),
      outline: Color(0xFF3E2E26),
      cardElevation: 3,
      buttonElevation: 2,
      inputFill: Color(0xFF211815),
      labelColor: Color(0xFFD4A574),
      hintColor: Color(0xFF6B5246),
      focusedBorderWidth: 1.5,
      headingRowColor: Color(0xFF2C211D),
      dataRowColor: Color(0xFF211815),
      appBarForeground: Color(0xFFD4A574),
      cardShadowColor: Color(0x33D4A574),
      buttonShadowColor: Color(0x44D4A574),
      surfaceContainerHighest: Color(0xFF3E2E26),
      surfaceContainer: Color(0xFF2C211D),
      surfaceContainerHigh: Color(0xFF352821),
      surfaceContainerLow: Color(0xFF1E1513),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFAF5F0),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF8B5E3C),
      secondary: Color(0xFFA47551),
      error: Color(0xFFD32F2F),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF3E2E26),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFDBC8B8),
      inputFill: Color(0xFFF7F0E8),
      labelColor: Color(0xFF8B5E3C),
      hintColor: Color(0xFFB8A090),
      cardShadowColor: Color(0x338B5E3C),
    ),
  ),
};

ThemeData _buildTheme(_ThemeColors c) {
  final isDark = c.brightness == Brightness.dark;
  final base = isDark ? ThemeData.dark() : ThemeData.light();
  final effectiveBorderColor = c.borderColor ?? c.outline;

  return base.copyWith(
    primaryColor: c.background,
    scaffoldBackgroundColor: c.background,
    cardColor: c.surface,
    colorScheme:
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
      primary: c.primary,
      secondary: c.secondary,
      surface: c.surface,
      background: c.background,
      error: c.error,
      onPrimary: c.onPrimary,
      onSecondary: c.onSecondary,
      onSurface: c.onSurface,
      onBackground: c.onSurface,
      onError: c.onError,
      outline: c.outline,
      surfaceContainerHighest: c.surfaceContainerHighest,
      surfaceContainer: c.surfaceContainer,
      surfaceContainerHigh: c.surfaceContainerHigh,
      surfaceContainerLow: c.surfaceContainerLow,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.appBarForeground ?? c.onSurface,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: c.cardElevation,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      shadowColor: c.cardShadowColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.buttonForeground ?? c.onPrimary,
        elevation: c.buttonElevation,
        shadowColor: c.buttonShadowColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: c.inputFill != null
        ? TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: c.primary),
          )
        : null,
    inputDecorationTheme: c.inputFill != null
        ? InputDecorationTheme(
            filled: true,
            fillColor: c.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: effectiveBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: effectiveBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: c.primary, width: c.focusedBorderWidth),
            ),
            labelStyle: TextStyle(color: c.labelColor),
            hintStyle: TextStyle(color: c.hintColor),
          )
        : null,
    chipTheme: c.inputFill != null
        ? ChipThemeData(
            backgroundColor: c.chipBgColor ?? c.inputFill,
            selectedColor: c.primary,
            labelStyle: TextStyle(color: c.onSurface),
            secondaryLabelStyle:
                TextStyle(color: c.chipSecondaryLabel ?? c.onPrimary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          )
        : null,
    dataTableTheme: c.headingRowColor != null
        ? DataTableThemeData(
            headingRowColor: WidgetStateProperty.all(c.headingRowColor!),
            dataRowColor: WidgetStateProperty.all(c.dataRowColor!),
            dividerThickness: 1,
          )
        : null,
    expansionTileTheme: c.headingRowColor != null
        ? ExpansionTileThemeData(
            backgroundColor: c.headingRowColor!,
            collapsedBackgroundColor: c.dataRowColor!,
            iconColor: c.primary,
            collapsedIconColor: c.collapsedIconColor ?? c.labelColor,
          )
        : null,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  AppTheme _currentTheme = AppTheme.githubDark;
  ThemeMode _currentThemeMode = ThemeMode.system;
  static const String _themeKey = 'selected_theme';
  static const String _themeModeKey = 'theme_mode';

  AppTheme get currentTheme => _currentTheme;
  ThemeMode get currentThemeMode => _currentThemeMode;
  bool get isLightMode => _currentThemeMode == ThemeMode.light;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    final themeModeIndex = prefs.getInt(_themeModeKey) ?? 2;
    _currentTheme = AppTheme.values[themeIndex];

    switch (themeModeIndex) {
      case 0:
        _currentThemeMode = ThemeMode.dark;
        break;
      case 1:
        _currentThemeMode = ThemeMode.light;
        break;
      default:
        _currentThemeMode = ThemeMode.system;
        break;
    }

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

    int modeIndex;
    switch (mode) {
      case ThemeMode.dark:
        modeIndex = 0;
        break;
      case ThemeMode.light:
        modeIndex = 1;
        break;
      case ThemeMode.system:
        modeIndex = 2;
        break;
    }

    await prefs.setInt(_themeModeKey, modeIndex);
    notifyListeners();
  }

  Future<void> toggleThemeMode() async {
    final newMode =
        _currentThemeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  String getThemeName(AppTheme theme) => theme.displayName;

  IconData getThemeIcon(AppTheme theme) => theme.icon;

  ThemeData getThemeData(AppTheme theme) {
    final pair = _themeColors[theme]!;
    return _buildTheme(isLightMode ? pair.light : pair.dark);
  }
}
