/// What a shared drive file is, as sorted by the crawler
/// (`scripts/acad-drives/classify.js` writes `resource_type`). Keep the keys
/// in sync with it.
enum AcadResourceType {
  pyq('pyq', 'Past papers'),
  solutions('solutions', 'Solutions'),
  lectures('lectures', 'Slides & lectures'),
  notes('notes', 'Notes'),
  assignments('assignments', 'Labs & tutorials'),
  books('books', 'Books'),
  handout('handout', 'Handouts'),
  other('other', 'Other');

  const AcadResourceType(this.key, this.label);

  final String key;
  final String label;

  static AcadResourceType fromKey(String? key) => values.firstWhere(
        (t) => t.key == key,
        orElse: () => AcadResourceType.other,
      );
}

/// Exam a past paper or solution belongs to (`exam` on a file doc).
String? acadExamLabel(String? exam) => switch (exam) {
      'midsem' => 'Mid-sem',
      'compre' => 'Compre',
      'quiz' => 'Quiz',
      'test' => 'Test',
      _ => null,
    };
