/// Row density for the timetable grid.
///
/// These no longer control column *width* — columns always divide the available
/// width so the grid never scrolls sideways on a desktop-sized viewport. They
/// set row height only, which is what actually decides how much of a class fits
/// in a cell.
enum TimetableSize {
  compact,
  medium,
  large,
  extraLarge,

  /// Row height is derived from the viewport so every visible hour is on screen
  /// at once. Appended last: [TimetableSettings.fromJson] matches on
  /// `toString()`, so position is not persisted, but appending keeps any
  /// index-based reader safe.
  fit,
}

enum TimetableLayout {
  horizontal, // Days on Y-axis, hours on X-axis
  vertical, // Hours on Y-axis, days on X-axis (default)
  agenda, // Chronological list grouped by day — the mobile-friendly view
}

extension TimetableSizeLabel on TimetableSize {
  String get label => switch (this) {
    TimetableSize.compact => 'Compact',
    TimetableSize.medium => 'Medium',
    TimetableSize.large => 'Large',
    TimetableSize.extraLarge => 'Extra Large',
    TimetableSize.fit => 'Fit to screen',
  };

  /// Fixed row height in logical pixels. [TimetableSize.fit] has none — it is
  /// measured against the viewport instead — so callers must handle null.
  double? get fixedRowHeight => switch (this) {
    TimetableSize.compact => 64.0,
    TimetableSize.medium => 84.0,
    TimetableSize.large => 106.0,
    TimetableSize.extraLarge => 132.0,
    TimetableSize.fit => null,
  };
}

extension TimetableLayoutLabel on TimetableLayout {
  String get label => switch (this) {
    TimetableLayout.vertical => 'Week',
    TimetableLayout.horizontal => 'Day rows',
    TimetableLayout.agenda => 'Agenda',
  };
}
