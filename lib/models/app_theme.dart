import 'package:flutter/material.dart';

enum AppTheme {
  githubDark('GitHub Dark', Icons.code),
  draculaDark('Dracula', Icons.brightness_2),
  nordDark('Nord', Icons.ac_unit),
  tokyoNightDark('Tokyo Night', Icons.nightlight_round),
  gruvboxDark('Gruvbox', Icons.grain),
  catppuccinDark('Catppuccin', Icons.pets),
  solarizedDark('Solarized Dark', Icons.wb_sunny),
  arcticFrost('Arctic Frost', Icons.severe_cold),
  amoledDark('AMOLED Dark', Icons.brightness_1),
  ;

  const AppTheme(this.displayName, this.icon);
  final String displayName;
  final IconData icon;
}

class ThemeGeometry extends ThemeExtension<ThemeGeometry> {
  final double cardRadius;
  final double buttonRadius;
  final double dialogRadius;
  final double inputRadius;
  final double chipRadius;
  final double cardElevation;
  final double cardBorderWidth;
  final FontWeight headingWeight;
  final FontWeight bodyWeight;

  const ThemeGeometry({
    this.cardRadius = 12,
    this.buttonRadius = 8,
    this.dialogRadius = 16,
    this.inputRadius = 12,
    this.chipRadius = 20,
    this.cardElevation = 2,
    this.cardBorderWidth = 0,
    this.headingWeight = FontWeight.w600,
    this.bodyWeight = FontWeight.w400,
  });

  @override
  ThemeGeometry copyWith({
    double? cardRadius,
    double? buttonRadius,
    double? dialogRadius,
    double? inputRadius,
    double? chipRadius,
    double? cardElevation,
    double? cardBorderWidth,
    FontWeight? headingWeight,
    FontWeight? bodyWeight,
  }) =>
      ThemeGeometry(
        cardRadius: cardRadius ?? this.cardRadius,
        buttonRadius: buttonRadius ?? this.buttonRadius,
        dialogRadius: dialogRadius ?? this.dialogRadius,
        inputRadius: inputRadius ?? this.inputRadius,
        chipRadius: chipRadius ?? this.chipRadius,
        cardElevation: cardElevation ?? this.cardElevation,
        cardBorderWidth: cardBorderWidth ?? this.cardBorderWidth,
        headingWeight: headingWeight ?? this.headingWeight,
        bodyWeight: bodyWeight ?? this.bodyWeight,
      );

  @override
  ThemeGeometry lerp(covariant ThemeGeometry? other, double t) {
    if (other == null) return this;
    return ThemeGeometry(
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      buttonRadius: lerpDouble(buttonRadius, other.buttonRadius, t)!,
      dialogRadius: lerpDouble(dialogRadius, other.dialogRadius, t)!,
      inputRadius: lerpDouble(inputRadius, other.inputRadius, t)!,
      chipRadius: lerpDouble(chipRadius, other.chipRadius, t)!,
      cardElevation: lerpDouble(cardElevation, other.cardElevation, t)!,
      cardBorderWidth: lerpDouble(cardBorderWidth, other.cardBorderWidth, t)!,
      headingWeight: t < 0.5 ? headingWeight : other.headingWeight,
      bodyWeight: t < 0.5 ? bodyWeight : other.bodyWeight,
    );
  }

  static ThemeGeometry of(BuildContext context) {
    return Theme.of(context).extension<ThemeGeometry>() ?? const ThemeGeometry();
  }

  static double? lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class TimetableTheme extends ThemeExtension<TimetableTheme> {
  final List<Color> accents;
  const TimetableTheme(this.accents);

  @override
  TimetableTheme copyWith({List<Color>? accents}) =>
      TimetableTheme(accents ?? this.accents);

  @override
  TimetableTheme lerp(covariant TimetableTheme? other, double t) {
    if (other == null) return this;
    return TimetableTheme(
      List.generate(
        accents.length,
        (i) => Color.lerp(accents[i], i < other.accents.length ? other.accents[i] : accents[i], t)!,
      ),
    );
  }
}
