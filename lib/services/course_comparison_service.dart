import '../models/course.dart';

/// Service for comparing courses based on time similarity
/// Considers lecture timings, tutorial timings, practical timings, and exam times
class CourseComparisonService {
  static const double _lectureWeight = 0.4;
  static const double _tutorialWeight = 0.3;
  static const double _practicalWeight = 0.3;
  static const double _midSemWeight = 0.4;
  static const double _endSemWeight = 0.6;

  /// Calculates similarity score between two courses
  /// Returns a score between 0 and 1, where 1 is most similar
  static double calculateSimilarityScore(Course referenceCourse, Course compareCourse) {
    double totalScore = 0.0;
    double totalWeight = 0.0;

    // Get sections by type for both courses
    final refLectures = referenceCourse.sections.where((s) => s.type == SectionType.L).toList();
    final refTutorials = referenceCourse.sections.where((s) => s.type == SectionType.T).toList();
    final refPracticals = referenceCourse.sections.where((s) => s.type == SectionType.P).toList();

    final compLectures = compareCourse.sections.where((s) => s.type == SectionType.L).toList();
    final compTutorials = compareCourse.sections.where((s) => s.type == SectionType.T).toList();
    final compPracticals = compareCourse.sections.where((s) => s.type == SectionType.P).toList();

    // Compare lecture timings
    if (refLectures.isNotEmpty && compLectures.isNotEmpty) {
      double lectureScore = _calculateSectionsSimilarity(refLectures, compLectures);
      totalScore += lectureScore * _lectureWeight;
      totalWeight += _lectureWeight;
    }

    // Compare tutorial timings (only if both courses have tutorials)
    if (refTutorials.isNotEmpty && compTutorials.isNotEmpty) {
      double tutorialScore = _calculateSectionsSimilarity(refTutorials, compTutorials);
      totalScore += tutorialScore * _tutorialWeight;
      totalWeight += _tutorialWeight;
    }

    // Compare practical timings (only if both courses have practicals)
    if (refPracticals.isNotEmpty && compPracticals.isNotEmpty) {
      double practicalScore = _calculateSectionsSimilarity(refPracticals, compPracticals);
      totalScore += practicalScore * _practicalWeight;
      totalWeight += _practicalWeight;
    }

    // Compare exam timings
    double examScore = _calculateExamSimilarity(referenceCourse, compareCourse);
    double examWeight = _midSemWeight + _endSemWeight;
    totalScore += examScore * examWeight;
    totalWeight += examWeight;

    // Return normalized score (avoid division by zero)
    return totalWeight > 0 ? totalScore / totalWeight : 0.0;
  }

  /// Calculates similarity between sections of the same type
  static double _calculateSectionsSimilarity(List<Section> refSections, List<Section> compSections) {
    double maxSimilarity = 0.0;

    // For each reference section, find the most similar comparison section
    for (var refSection in refSections) {
      for (var compSection in compSections) {
        double similarity = _calculateTimingSimilarity(refSection, compSection);
        if (similarity > maxSimilarity) {
          maxSimilarity = similarity;
        }
      }
    }

    return maxSimilarity;
  }

  /// Calculates timing similarity between two sections
  static double _calculateTimingSimilarity(Section refSection, Section compSection) {
    double dayOverlap = _calculateDayOverlap(refSection, compSection);
    double timeOverlap = _calculateTimeOverlap(refSection, compSection);
    
    // Weight day overlap more heavily than exact time overlap
    return (dayOverlap * 0.7) + (timeOverlap * 0.3);
  }

  /// Calculates day overlap similarity between two sections
  static double _calculateDayOverlap(Section refSection, Section compSection) {
    Set<DayOfWeek> refDays = {};
    Set<DayOfWeek> compDays = {};

    for (var entry in refSection.schedule) {
      refDays.addAll(entry.days);
    }
    for (var entry in compSection.schedule) {
      compDays.addAll(entry.days);
    }

    if (refDays.isEmpty || compDays.isEmpty) return 0.0;

    int overlap = refDays.intersection(compDays).length;
    int union = refDays.union(compDays).length;
    
    return overlap / union;
  }

  /// Calculates time overlap similarity between two sections
  static double _calculateTimeOverlap(Section refSection, Section compSection) {
    Set<int> refHours = {};
    Set<int> compHours = {};

    for (var entry in refSection.schedule) {
      refHours.addAll(entry.hours);
    }
    for (var entry in compSection.schedule) {
      compHours.addAll(entry.hours);
    }

    if (refHours.isEmpty || compHours.isEmpty) return 0.0;

    int overlap = refHours.intersection(compHours).length;
    int union = refHours.union(compHours).length;
    
    return overlap / union;
  }

  /// Calculates exam timing similarity between two courses
  static double _calculateExamSimilarity(Course referenceCourse, Course compareCourse) {
    double midSemScore = 0.0;
    double endSemScore = 0.0;

    // Compare mid-sem exams
    if (referenceCourse.midSemExam != null && compareCourse.midSemExam != null) {
      midSemScore = _calculateExamTimeSimilarity(
        referenceCourse.midSemExam!, 
        compareCourse.midSemExam!
      );
    }

    // Compare end-sem exams
    if (referenceCourse.endSemExam != null && compareCourse.endSemExam != null) {
      endSemScore = _calculateExamTimeSimilarity(
        referenceCourse.endSemExam!, 
        compareCourse.endSemExam!
      );
    }

    // Return weighted average of exam scores
    double totalExamWeight = 0.0;
    double totalExamScore = 0.0;

    if (referenceCourse.midSemExam != null && compareCourse.midSemExam != null) {
      totalExamScore += midSemScore * _midSemWeight;
      totalExamWeight += _midSemWeight;
    }

    if (referenceCourse.endSemExam != null && compareCourse.endSemExam != null) {
      totalExamScore += endSemScore * _endSemWeight;
      totalExamWeight += _endSemWeight;
    }

    return totalExamWeight > 0 ? totalExamScore / totalExamWeight : 0.0;
  }

  /// Calculates similarity between two exam schedules
  static double _calculateExamTimeSimilarity(ExamSchedule refExam, ExamSchedule compExam) {
    // Same date and same time slot = perfect match
    if (refExam.date.isAtSameMomentAs(compExam.date) && refExam.timeSlot == compExam.timeSlot) {
      return 1.0;
    }

    // Same date, different time slot = high similarity
    if (refExam.date.isAtSameMomentAs(compExam.date)) {
      return 0.7;
    }

    // Different date, same time slot = medium similarity
    if (refExam.timeSlot == compExam.timeSlot) {
      // Calculate date proximity (within a week is better)
      int daysDifference = refExam.date.difference(compExam.date).inDays.abs();
      if (daysDifference <= 7) {
        return 0.5 - (daysDifference * 0.05); // Decreasing similarity with more days apart
      }
      return 0.3;
    }

    // Different date and time slot but check if they're close
    int daysDifference = refExam.date.difference(compExam.date).inDays.abs();
    if (daysDifference <= 3) {
      return 0.2;
    }

    return 0.0;
  }

  /// Returns the top similar courses sorted by similarity score
  static List<CourseComparison> findSimilarCourses(
    Course referenceCourse, 
    List<Course> availableCourses, 
    {int limit = 30}
  ) {
    List<CourseComparison> comparisons = [];

    for (var course in availableCourses) {
      // Skip the reference course itself
      if (course.courseCode == referenceCourse.courseCode) continue;

      double score = calculateSimilarityScore(referenceCourse, course);
      comparisons.add(CourseComparison(
        course: course,
        similarityScore: score,
        referenceCourse: referenceCourse,
      ));
    }

    // Sort by similarity score (descending)
    comparisons.sort((a, b) => b.similarityScore.compareTo(a.similarityScore));

    // Return top results
    return comparisons.take(limit).toList();
  }

  /// Check if a course has only lecture sections
  static bool hasOnlyLectureSections(Course course) {
    final hasLectures = course.sections.any((s) => s.type == SectionType.L);
    final hasNonLectures = course.sections.any((s) => s.type != SectionType.L);
    return hasLectures && !hasNonLectures;
  }
}

/// Data class to hold course comparison results
class CourseComparison {
  final Course course;
  final double similarityScore;
  final Course referenceCourse;

  CourseComparison({
    required this.course,
    required this.similarityScore,
    required this.referenceCourse,
  });
}