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
