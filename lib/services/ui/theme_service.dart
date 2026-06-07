import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';
import '../../models/app_theme.dart';

export '../../models/app_theme.dart';

class _ThemeColors {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color onTertiary;
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
  final Color? surfaceContainerHighest;
  final Color? surfaceContainer;
  final Color? surfaceContainerHigh;
  final Color? surfaceContainerLow;
  final List<Color>? timetableAccents;
  final ThemeGeometry geometry;

  const _ThemeColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.onTertiary,
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
    this.surfaceContainerHighest,
    this.surfaceContainer,
    this.surfaceContainerHigh,
    this.surfaceContainerLow,
    this.timetableAccents,
    this.geometry = const ThemeGeometry(),
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
      tertiary: Color(0xFFD29922),
      onTertiary: Color(0xFF0D1117),
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
      timetableAccents: [
        Color(0xFF58A6FF), Color(0xFF3FB950), Color(0xFFD29922),
        Color(0xFFF778BA), Color(0xFFBC8CFF), Color(0xFF39D2C0),
        Color(0xFFFF7B72), Color(0xFF79C0FF), Color(0xFFFFA657),
        Color(0xFF7EE787),
      ],
      geometry: ThemeGeometry(cardRadius: 6, buttonRadius: 6, dialogRadius: 12, inputRadius: 8, chipRadius: 16, cardBorderWidth: 1),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF6F8FA),
      primary: Color(0xFF0969DA),
      secondary: Color(0xFF1F883D),
      tertiary: Color(0xFF9A6700),
      onTertiary: Color(0xFFFFFFFF),
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
      timetableAccents: [
        Color(0xFF0969DA), Color(0xFF1A7F37), Color(0xFF9A6700),
        Color(0xFFBF3989), Color(0xFF8250DF), Color(0xFF1B7C83),
        Color(0xFFCF222E), Color(0xFF0550AE), Color(0xFFBC4C00),
        Color(0xFF116329),
      ],
      geometry: ThemeGeometry(cardRadius: 6, buttonRadius: 6, dialogRadius: 12, inputRadius: 8, chipRadius: 16, cardBorderWidth: 1),
    ),
  ),
  AppTheme.draculaDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF21222C),
      surface: Color(0xFF343746),
      primary: Color(0xFFBD93F9),
      secondary: Color(0xFF50FA7B),
      tertiary: Color(0xFFFFB86C),
      onTertiary: Color(0xFF282A36),
      error: Color(0xFFFF5555),
      onPrimary: Color(0xFF282A36),
      onSecondary: Color(0xFF282A36),
      onSurface: Color(0xFFF8F8F2),
      onError: Color(0xFF282A36),
      outline: Color(0xFF515470),
      inputFill: Color(0xFF2B2D3A),
      labelColor: Color(0xFF8BE9FD),
      hintColor: Color(0xFF6272A4),
      headingRowColor: Color(0xFF44475A),
      dataRowColor: Color(0xFF282A36),
      collapsedIconColor: Color(0xFF6272A4),
      timetableAccents: [
        Color(0xFFBD93F9), Color(0xFF50FA7B), Color(0xFFFFB86C),
        Color(0xFFFF79C6), Color(0xFF8BE9FD), Color(0xFFF1FA8C),
        Color(0xFFFF5555), Color(0xFF6272A4), Color(0xFFE6ACFF),
        Color(0xFF69FF94),
      ],
      geometry: ThemeGeometry(cardRadius: 14, buttonRadius: 10, dialogRadius: 20, inputRadius: 14, chipRadius: 20, cardElevation: 3),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF0F0E8),
      surface: Color(0xFFFAFAF6),
      primary: Color(0xFF7C4DFF),
      secondary: Color(0xFF1A7F37),
      tertiary: Color(0xFFC4841D),
      onTertiary: Color(0xFFFFFFFF),
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
      timetableAccents: [
        Color(0xFF7C5CBF), Color(0xFF2D8B4E), Color(0xFFC4841D),
        Color(0xFFBF3989), Color(0xFF3A7CA5), Color(0xFF8B8B00),
        Color(0xFFCF222E), Color(0xFF6272A4), Color(0xFF9B59B6),
        Color(0xFF27AE60),
      ],
      geometry: ThemeGeometry(cardRadius: 14, buttonRadius: 10, dialogRadius: 20, inputRadius: 14, chipRadius: 20, cardElevation: 3),
    ),
  ),
  AppTheme.nordDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF242933),
      surface: Color(0xFF353C4A),
      primary: Color(0xFF81A1C1),
      secondary: Color(0xFF88C0D0),
      tertiary: Color(0xFFEBCB8B),
      onTertiary: Color(0xFF2E3440),
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
      timetableAccents: [
        Color(0xFF5E81AC), Color(0xFFA3BE8C), Color(0xFFEBCB8B),
        Color(0xFFB48EAD), Color(0xFF88C0D0), Color(0xFFD4879C),
        Color(0xFFBF616A), Color(0xFF8FBCBB), Color(0xFFD08770),
        Color(0xFFC6AA78),
      ],
      geometry: ThemeGeometry(cardRadius: 10, buttonRadius: 8, dialogRadius: 14, inputRadius: 10, chipRadius: 18, cardBorderWidth: 0.5, headingWeight: FontWeight.w500),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFE5E9F0),
      surface: Color(0xFFF8F9FC),
      primary: Color(0xFF5E81AC),
      secondary: Color(0xFF81A1C1),
      tertiary: Color(0xFFC4A44C),
      onTertiary: Color(0xFF2E3440),
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
      timetableAccents: [
        Color(0xFF4C6A92), Color(0xFF6B8E5E), Color(0xFFC4A44C),
        Color(0xFF8E6B8A), Color(0xFF5A8F9A), Color(0xFFA8657C),
        Color(0xFFA04850), Color(0xFF5F9A98), Color(0xFFAA6B50),
        Color(0xFF9E8458),
      ],
      geometry: ThemeGeometry(cardRadius: 10, buttonRadius: 8, dialogRadius: 14, inputRadius: 10, chipRadius: 18, cardBorderWidth: 0.5, headingWeight: FontWeight.w500),
    ),
  ),
  AppTheme.tokyoNightDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF16161E),
      surface: Color(0xFF292E42),
      primary: Color(0xFF7AA2F7),
      secondary: Color(0xFF9ECE6A),
      tertiary: Color(0xFFE0AF68),
      onTertiary: Color(0xFF1A1B26),
      error: Color(0xFFF7768E),
      onPrimary: Color(0xFF1A1B26),
      onSecondary: Color(0xFF1A1B26),
      onSurface: Color(0xFFC0CAF5),
      onError: Color(0xFFC0CAF5),
      outline: Color(0xFF3D4260),
      inputFill: Color(0xFF1E2030),
      borderColor: Color(0xFF414868),
      labelColor: Color(0xFF7DCFFF),
      hintColor: Color(0xFF565F89),
      headingRowColor: Color(0xFF32344A),
      dataRowColor: Color(0xFF24283B),
      buttonForeground: Color(0xFF1A1B26),
      chipSecondaryLabel: Color(0xFF1A1B26),
      timetableAccents: [
        Color(0xFF7AA2F7), Color(0xFF9ECE6A), Color(0xFFE0AF68),
        Color(0xFFF7768E), Color(0xFFBB9AF7), Color(0xFF7DCFFF),
        Color(0xFFFF9E64), Color(0xFF2AC3DE), Color(0xFFB4F9F8),
        Color(0xFF73DACA),
      ],
      geometry: ThemeGeometry(cardRadius: 12, buttonRadius: 8, dialogRadius: 16, inputRadius: 12, chipRadius: 20, cardElevation: 1, cardBorderWidth: 0.5),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF0F0F5),
      surface: Color(0xFFFCFCFF),
      primary: Color(0xFF3D59A1),
      secondary: Color(0xFF33635C),
      tertiary: Color(0xFF8F5E15),
      onTertiary: Color(0xFFFFFFFF),
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
      timetableAccents: [
        Color(0xFF3D59A1), Color(0xFF33635C), Color(0xFF8F5E15),
        Color(0xFFCC517A), Color(0xFF7847BD), Color(0xFF166775),
        Color(0xFFB15C2B), Color(0xFF2E7DE9), Color(0xFF188B8D),
        Color(0xFF38919F),
      ],
      geometry: ThemeGeometry(cardRadius: 12, buttonRadius: 8, dialogRadius: 16, inputRadius: 12, chipRadius: 20, cardElevation: 1, cardBorderWidth: 0.5),
    ),
  ),
  AppTheme.gruvboxDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF1A1C1D),
      surface: Color(0xFF2C2E2B),
      primary: Color(0xFFFABD2F),
      secondary: Color(0xFF98971A),
      tertiary: Color(0xFF458588),
      onTertiary: Color(0xFFEBDBB2),
      error: Color(0xFFCC241D),
      onPrimary: Color(0xFF1D2021),
      onSecondary: Color(0xFF1D2021),
      onSurface: Color(0xFFEBDBB2),
      onError: Color(0xFFEBDBB2),
      outline: Color(0xFF3C3836),
      inputFill: Color(0xFF222423),
      borderColor: Color(0xFF504945),
      labelColor: Color(0xFF83A598),
      hintColor: Color(0xFF665C54),
      headingRowColor: Color(0xFF3C3836),
      dataRowColor: Color(0xFF282828),
      timetableAccents: [
        Color(0xFFD79921), Color(0xFF98971A), Color(0xFF458588),
        Color(0xFFCC241D), Color(0xFFB16286), Color(0xFF689D6A),
        Color(0xFFD65D0E), Color(0xFF83A598), Color(0xFFFABD2F),
        Color(0xFFB8BB26),
      ],
      geometry: ThemeGeometry(cardRadius: 8, buttonRadius: 6, dialogRadius: 12, inputRadius: 8, chipRadius: 14, cardElevation: 0, cardBorderWidth: 1.5, headingWeight: FontWeight.w700),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFF2E5BC),
      surface: Color(0xFFFBF1C7),
      primary: Color(0xFFB57614),
      secondary: Color(0xFF79740E),
      tertiary: Color(0xFF076678),
      onTertiary: Color(0xFFFBF1C7),
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
      timetableAccents: [
        Color(0xFFB57614), Color(0xFF79740E), Color(0xFF076678),
        Color(0xFF9D0006), Color(0xFF8F3F71), Color(0xFF427B58),
        Color(0xFFAF3A03), Color(0xFF458588), Color(0xFF8B7A26),
        Color(0xFF6A8538),
      ],
      geometry: ThemeGeometry(cardRadius: 8, buttonRadius: 6, dialogRadius: 12, inputRadius: 8, chipRadius: 14, cardElevation: 0, cardBorderWidth: 1.5, headingWeight: FontWeight.w700),
    ),
  ),
  AppTheme.catppuccinDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF181825),
      surface: Color(0xFF313244),
      primary: Color(0xFFCBA6F7),
      secondary: Color(0xFFA6E3A1),
      tertiary: Color(0xFFF9E2AF),
      onTertiary: Color(0xFF1E1E2E),
      error: Color(0xFFF38BA8),
      onPrimary: Color(0xFF1E1E2E),
      onSecondary: Color(0xFF1E1E2E),
      onSurface: Color(0xFFCDD6F4),
      onError: Color(0xFFCDD6F4),
      outline: Color(0xFF45475A),
      inputFill: Color(0xFF232336),
      borderColor: Color(0xFF585B70),
      labelColor: Color(0xFF89B4FA),
      hintColor: Color(0xFF6C7086),
      headingRowColor: Color(0xFF45475A),
      dataRowColor: Color(0xFF313244),
      timetableAccents: [
        Color(0xFFCBA6F7), Color(0xFFA6E3A1), Color(0xFFF9E2AF),
        Color(0xFFF38BA8), Color(0xFF89B4FA), Color(0xFF94E2D5),
        Color(0xFFFAB387), Color(0xFF74C7EC), Color(0xFFEBA0AC),
        Color(0xFFF2CDCD),
      ],
      geometry: ThemeGeometry(cardRadius: 16, buttonRadius: 12, dialogRadius: 24, inputRadius: 16, chipRadius: 24, cardElevation: 0, cardBorderWidth: 1),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFE6E9EF),
      surface: Color(0xFFF5F5FA),
      primary: Color(0xFF8839EF),
      secondary: Color(0xFF40A02B),
      tertiary: Color(0xFFDF8E1D),
      onTertiary: Color(0xFFFFFFFF),
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
      timetableAccents: [
        Color(0xFF8839EF), Color(0xFF40A02B), Color(0xFFDF8E1D),
        Color(0xFFD20F39), Color(0xFF1E66F5), Color(0xFF179299),
        Color(0xFFFE640B), Color(0xFF04A5E5), Color(0xFFE64553),
        Color(0xFF7287FD),
      ],
      geometry: ThemeGeometry(cardRadius: 16, buttonRadius: 12, dialogRadius: 24, inputRadius: 16, chipRadius: 24, cardElevation: 0, cardBorderWidth: 1),
    ),
  ),
  AppTheme.solarizedDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF00212B),
      surface: Color(0xFF0A3847),
      primary: Color(0xFF2E9CDB),
      secondary: Color(0xFF2AA198),
      tertiary: Color(0xFFB58900),
      onTertiary: Color(0xFF002B36),
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
      timetableAccents: [
        Color(0xFF268BD2), Color(0xFF859900), Color(0xFFB58900),
        Color(0xFFD33682), Color(0xFF6C71C4), Color(0xFF2AA198),
        Color(0xFFCB4B16), Color(0xFF839496), Color(0xFFDC322F),
        Color(0xFF93A1A1),
      ],
      geometry: ThemeGeometry(cardRadius: 8, buttonRadius: 6, dialogRadius: 12, inputRadius: 8, chipRadius: 16, cardElevation: 1, cardBorderWidth: 0.5),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFFDF6E3),
      surface: Color(0xFFEEE8D5),
      primary: Color(0xFF2078B8),
      secondary: Color(0xFF2AA198),
      tertiary: Color(0xFFB58900),
      onTertiary: Color(0xFFFFFFFF),
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
      timetableAccents: [
        Color(0xFF268BD2), Color(0xFF859900), Color(0xFFB58900),
        Color(0xFFD33682), Color(0xFF6C71C4), Color(0xFF2AA198),
        Color(0xFFCB4B16), Color(0xFF586E75), Color(0xFFDC322F),
        Color(0xFF657B83),
      ],
      geometry: ThemeGeometry(cardRadius: 8, buttonRadius: 6, dialogRadius: 12, inputRadius: 8, chipRadius: 16, cardElevation: 1, cardBorderWidth: 0.5),
    ),
  ),
  AppTheme.arcticFrost: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF070F18),
      surface: Color(0xFF142538),
      primary: Color(0xFF8CD0E0),
      secondary: Color(0xFF81A1C1),
      tertiary: Color(0xFFEBCB8B),
      onTertiary: Color(0xFF0B1621),
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
      timetableAccents: [
        Color(0xFF88C0D0), Color(0xFFA3BE8C), Color(0xFFEBCB8B),
        Color(0xFFB48EAD), Color(0xFF81A1C1), Color(0xFF8FBCBB),
        Color(0xFFBF616A), Color(0xFFC6AA78), Color(0xFFD08770),
        Color(0xFFD4879C),
      ],
      geometry: ThemeGeometry(cardRadius: 14, buttonRadius: 10, dialogRadius: 20, inputRadius: 14, chipRadius: 22, cardElevation: 2),
    ),
    light: _ThemeColors(
      brightness: Brightness.light,
      background: Color(0xFFE8F0F6),
      surface: Color(0xFFF8FBFF),
      primary: Color(0xFF3E7D90),
      secondary: Color(0xFF5E81AC),
      tertiary: Color(0xFFC4A44C),
      onTertiary: Color(0xFF2E3440),
      error: Color(0xFFBF616A),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onSurface: Color(0xFF2E3440),
      onError: Color(0xFFFFFFFF),
      outline: Color(0xFFD0DBE6),
      inputFill: Color(0xFFF5F9FC),
      labelColor: Color(0xFF4A90A4),
      hintColor: Color(0xFF94A8BC),
      timetableAccents: [
        Color(0xFF4A90A4), Color(0xFF5A8F6A), Color(0xFFC4A44C),
        Color(0xFF8E6B8A), Color(0xFF5E81AC), Color(0xFF5F9A98),
        Color(0xFFA04850), Color(0xFF9E8458), Color(0xFFAA6B50),
        Color(0xFFA8657C),
      ],
      geometry: ThemeGeometry(cardRadius: 14, buttonRadius: 10, dialogRadius: 20, inputRadius: 14, chipRadius: 22, cardElevation: 2),
    ),
  ),
  AppTheme.amoledDark: (
    dark: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF000000),
      surface: Color(0xFF141414),
      primary: Color(0xFF6CB4EE),
      secondary: Color(0xFF4ADE80),
      tertiary: Color(0xFFFBBF24),
      onTertiary: Color(0xFF000000),
      error: Color(0xFFFF6B6B),
      onPrimary: Color(0xFF000000),
      onSecondary: Color(0xFF000000),
      onSurface: Color(0xFFE8E8E8),
      onError: Color(0xFF000000),
      outline: Color(0xFF252525),
      cardElevation: 0,
      buttonElevation: 0,
      inputFill: Color(0xFF0A0A0A),
      labelColor: Color(0xFF8A8A8A),
      hintColor: Color(0xFF555555),
      headingRowColor: Color(0xFF0D0D0D),
      dataRowColor: Color(0xFF050505),
      surfaceContainerHighest: Color(0xFF1F1F1F),
      surfaceContainer: Color(0xFF141414),
      surfaceContainerHigh: Color(0xFF1A1A1A),
      surfaceContainerLow: Color(0xFF070707),
      timetableAccents: [
        Color(0xFF6CB4EE), Color(0xFF4ADE80), Color(0xFFFBBF24),
        Color(0xFFF472B6), Color(0xFFA78BFA), Color(0xFF22D3EE),
        Color(0xFFFB923C), Color(0xFF38BDF8), Color(0xFFF87171),
        Color(0xFF34D399),
      ],
      geometry: ThemeGeometry(cardRadius: 4, buttonRadius: 4, dialogRadius: 8, inputRadius: 6, chipRadius: 12, cardElevation: 0, cardBorderWidth: 1),
    ),
    light: _ThemeColors(
      brightness: Brightness.dark,
      background: Color(0xFF000000),
      surface: Color(0xFF141414),
      primary: Color(0xFF6CB4EE),
      secondary: Color(0xFF4ADE80),
      tertiary: Color(0xFFFBBF24),
      onTertiary: Color(0xFF000000),
      error: Color(0xFFFF6B6B),
      onPrimary: Color(0xFF000000),
      onSecondary: Color(0xFF000000),
      onSurface: Color(0xFFE8E8E8),
      onError: Color(0xFF000000),
      outline: Color(0xFF252525),
      cardElevation: 0,
      buttonElevation: 0,
      inputFill: Color(0xFF0A0A0A),
      labelColor: Color(0xFF8A8A8A),
      hintColor: Color(0xFF555555),
      headingRowColor: Color(0xFF0D0D0D),
      dataRowColor: Color(0xFF050505),
      surfaceContainerHighest: Color(0xFF1F1F1F),
      surfaceContainer: Color(0xFF141414),
      surfaceContainerHigh: Color(0xFF1A1A1A),
      surfaceContainerLow: Color(0xFF070707),
      timetableAccents: [
        Color(0xFF6CB4EE), Color(0xFF4ADE80), Color(0xFFFBBF24),
        Color(0xFFF472B6), Color(0xFFA78BFA), Color(0xFF22D3EE),
        Color(0xFFFB923C), Color(0xFF38BDF8), Color(0xFFF87171),
        Color(0xFF34D399),
      ],
      geometry: ThemeGeometry(cardRadius: 4, buttonRadius: 4, dialogRadius: 8, inputRadius: 6, chipRadius: 12, cardElevation: 0, cardBorderWidth: 1),
    ),
  ),
};

TextTheme _buildTextTheme(Color onSurface) {
  final base = GoogleFonts.interTextTheme();
  return base.copyWith(
    displayLarge: base.displayLarge!.copyWith(fontSize: 57, fontWeight: FontWeight.w400, color: onSurface, letterSpacing: -1.5, height: 1.12),
    displayMedium: base.displayMedium!.copyWith(fontSize: 45, fontWeight: FontWeight.w400, color: onSurface, letterSpacing: -0.5, height: 1.16),
    displaySmall: base.displaySmall!.copyWith(fontSize: 36, fontWeight: FontWeight.w400, color: onSurface, letterSpacing: -0.25, height: 1.22),
    headlineLarge: base.headlineLarge!.copyWith(fontSize: 32, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: -0.25, height: 1.25),
    headlineMedium: base.headlineMedium!.copyWith(fontSize: 28, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: 0, height: 1.29),
    headlineSmall: base.headlineSmall!.copyWith(fontSize: 24, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: 0, height: 1.33),
    titleLarge: base.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: 0, height: 1.4),
    titleMedium: base.titleMedium!.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: 0.1, height: 1.5),
    titleSmall: base.titleSmall!.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: 0.1, height: 1.43),
    bodyLarge: base.bodyLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w400, color: onSurface, letterSpacing: 0.15, height: 1.5),
    bodyMedium: base.bodyMedium!.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface, letterSpacing: 0.25, height: 1.43),
    bodySmall: base.bodySmall!.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: onSurface, letterSpacing: 0.4, height: 1.33),
    labelLarge: base.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: onSurface, letterSpacing: 0.1, height: 1.43),
    labelMedium: base.labelMedium!.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: onSurface, letterSpacing: 0.5, height: 1.33),
    labelSmall: base.labelSmall!.copyWith(fontSize: 11, fontWeight: FontWeight.w500, color: onSurface, letterSpacing: 0.5, height: 1.45),
  );
}

ThemeData _buildTheme(_ThemeColors c) {
  final isDark = c.brightness == Brightness.dark;
  final base = isDark ? ThemeData.dark() : ThemeData.light();
  final effectiveBorderColor = c.borderColor ?? c.outline;
  final g = c.geometry;
  final textTheme = _buildTextTheme(c.onSurface);

  return base.copyWith(
    textTheme: textTheme,
    primaryColor: c.background,
    scaffoldBackgroundColor: c.background,
    cardColor: c.surface,
    colorScheme:
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
      primary: c.primary,
      secondary: c.secondary,
      tertiary: c.tertiary,
      onTertiary: c.onTertiary,
      surface: c.surface,
      error: c.error,
      onPrimary: c.onPrimary,
      onSecondary: c.onSecondary,
      onSurface: c.onSurface,
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
      scrolledUnderElevation: 1,
      centerTitle: true,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.dialogRadius)),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: g.headingWeight,
        color: c.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: g.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(g.cardRadius),
        side: g.cardBorderWidth > 0
            ? BorderSide(color: c.outline.withValues(alpha: 0.3), width: g.cardBorderWidth)
            : BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.buttonForeground ?? c.onPrimary,
        elevation: c.buttonElevation,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.buttonRadius)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.buttonRadius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.buttonRadius)),
      ),
    ),
    inputDecorationTheme: c.inputFill != null
        ? InputDecorationTheme(
            filled: true,
            fillColor: c.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(g.inputRadius),
              borderSide: BorderSide(color: effectiveBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(g.inputRadius),
              borderSide: BorderSide(color: effectiveBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(g.inputRadius),
              borderSide:
                  BorderSide(color: c.primary, width: c.focusedBorderWidth),
            ),
            labelStyle: TextStyle(color: c.labelColor),
            hintStyle: TextStyle(color: c.hintColor),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                borderRadius: BorderRadius.circular(g.chipRadius)),
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
    extensions: [
      g,
      if (c.timetableAccents != null) TimetableTheme(c.timetableAccents!),
    ],
  );
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  AppTheme _currentTheme = AppTheme.githubDark;
  ThemeMode _currentThemeMode = ThemeMode.system;
  AppTheme get currentTheme => _currentTheme;
  ThemeMode get currentThemeMode => _currentThemeMode;
  bool get isLightMode => _currentThemeMode == ThemeMode.light;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(StorageKeys.selectedThemeName);

    if (themeName != null) {
      _currentTheme = AppTheme.values.firstWhere(
        (e) => e.name == themeName,
        orElse: () => AppTheme.githubDark,
      );
    } else {
      // Migrate from old integer-based storage
      final oldIndex = prefs.getInt(StorageKeys.selectedTheme);
      if (oldIndex != null) {
        _currentTheme = _migrateOldThemeIndex(oldIndex);
        await prefs.setString(StorageKeys.selectedThemeName, _currentTheme.name);
        await prefs.remove(StorageKeys.selectedTheme);
      }
    }

    final themeModeIndex = prefs.getInt(StorageKeys.themeMode) ?? 2;
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

  static AppTheme _migrateOldThemeIndex(int oldIndex) {
    // Old enum order before curation:
    // 0=githubDark, 1=dracula, 2=oceanic, 3=cobalt, 4=material,
    // 5=nord, 6=tokyoNight, 7=gruvbox, 8=catppuccin, 9=solarized,
    // 10=sunset, 11=forest, 12=royalPurple, 13=crimson, 14=electric,
    // 15=blackGold, 16=midnight, 17=roseQuartz, 18=arcticFrost, 19=espresso
    const oldToNew = <int, AppTheme>{
      0: AppTheme.githubDark,
      1: AppTheme.draculaDark,
      5: AppTheme.nordDark,
      6: AppTheme.tokyoNightDark,
      7: AppTheme.gruvboxDark,
      8: AppTheme.catppuccinDark,
      9: AppTheme.solarizedDark,
      18: AppTheme.arcticFrost,
    };
    return oldToNew[oldIndex] ?? AppTheme.githubDark;
  }

  Future<void> setTheme(AppTheme theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.selectedThemeName, theme.name);
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

    await prefs.setInt(StorageKeys.themeMode, modeIndex);
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

  ThemeData getLightThemeData(AppTheme theme) {
    final pair = _themeColors[theme]!;
    return _buildTheme(pair.light);
  }

  ThemeData getDarkThemeData(AppTheme theme) {
    final pair = _themeColors[theme]!;
    return _buildTheme(pair.dark);
  }
}
