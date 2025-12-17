class ExportOptions {
  final bool showCourseCode;
  final bool showCourseTitle;
  final bool showSectionId;
  final bool showInstructor;
  final bool showRoom;
  final bool showTimeSlots;

  const ExportOptions({
    this.showCourseCode = true,
    this.showCourseTitle = true,
    this.showSectionId = true,
    this.showInstructor = true,
    this.showRoom = true,
    this.showTimeSlots = true,
  });

  ExportOptions copyWith({
    bool? showCourseCode,
    bool? showCourseTitle,
    bool? showSectionId,
    bool? showInstructor,
    bool? showRoom,
    bool? showTimeSlots,
  }) {
    return ExportOptions(
      showCourseCode: showCourseCode ?? this.showCourseCode,
      showCourseTitle: showCourseTitle ?? this.showCourseTitle,
      showSectionId: showSectionId ?? this.showSectionId,
      showInstructor: showInstructor ?? this.showInstructor,
      showRoom: showRoom ?? this.showRoom,
      showTimeSlots: showTimeSlots ?? this.showTimeSlots,
    );
  }
}