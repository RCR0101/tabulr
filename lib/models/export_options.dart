class ExportOptions {
  final bool showCourseCode;
  final bool showCourseTitle;
  final bool showSectionId;
  final bool showInstructor;
  final bool showRoom;
  final bool showTimeSlots;
  final bool showExamDates;

  /// PNG only: render the capture against the dark variant of the current
  /// theme. Defaults to dark — the export used to come out with a transparent
  /// background, which reads as black on most viewers anyway.
  final bool darkBackground;

  const ExportOptions({
    this.showCourseCode = true,
    this.showCourseTitle = true,
    this.showSectionId = true,
    this.showInstructor = true,
    this.showRoom = true,
    this.showTimeSlots = true,
    this.showExamDates = true,
    this.darkBackground = true,
  });

  ExportOptions copyWith({
    bool? showCourseCode,
    bool? showCourseTitle,
    bool? showSectionId,
    bool? showInstructor,
    bool? showRoom,
    bool? showTimeSlots,
    bool? showExamDates,
    bool? darkBackground,
  }) {
    return ExportOptions(
      showCourseCode: showCourseCode ?? this.showCourseCode,
      showCourseTitle: showCourseTitle ?? this.showCourseTitle,
      showSectionId: showSectionId ?? this.showSectionId,
      showInstructor: showInstructor ?? this.showInstructor,
      showRoom: showRoom ?? this.showRoom,
      showTimeSlots: showTimeSlots ?? this.showTimeSlots,
      showExamDates: showExamDates ?? this.showExamDates,
      darkBackground: darkBackground ?? this.darkBackground,
    );
  }
}