/// Canonical form for comparing course codes across sources.
///
/// The same course is written "CS F320" in the Bulletin, "CSF320" on a pasted
/// performance sheet, and occasionally with a double space in scraped data.
/// Anything matching codes from two different origins has to compare this form
/// rather than the raw strings.
String normalizeCourseCode(String code) =>
    code.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Firestore document id for a course code: `"CS F211"` -> `"CS_F211"`.
///
/// Course documents are keyed by code with spaces replaced by underscores,
/// because `/` is the only character Firestore actually forbids but spaces in
/// ids are miserable to work with in the console and in URLs.
///
/// This pairs with [docIdToCourseCode]; use them rather than open-coding the
/// `replaceAll`, which was inlined in eight places across services, the
/// prerequisites repository and two admin screens — the same shape of
/// duplication that let the two copies of the user-doc-id derivation drift
/// apart until one of them let an unrelated account read another student's data.
String courseCodeToDocId(String courseCode) => courseCode.replaceAll(' ', '_');

/// Inverse of [courseCodeToDocId]: `"CS_F211"` -> `"CS F211"`.
String docIdToCourseCode(String docId) => docId.replaceAll('_', ' ');

/// The individual course codes inside a combined exam code, in order.
///
/// The seating sheet writes combined exams two ways, and the upload turns the
/// slash into a dash: "CS F407-CS U407" (full codes) and "ECE-EEE F211" (shared
/// number). A lone prefix borrows the next part's number, and a lone number
/// ("MATH F424-U424") borrows the previous part's prefix.
List<String> examCourseCodes(String code) {
  final parts = code
      .toUpperCase()
      .split(RegExp(r'[-/]'))
      .map((p) => RegExp(r'^\s*([A-Z]+(?=\s|$))?\s*([A-Z]?\d{3}[A-Z]?)?\s*$').firstMatch(p))
      .toList();
  if (parts.any((m) => m == null)) return [code.trim()];

  String? near(Iterable<RegExpMatch?> ms, int group) =>
      ms.map((m) => m!.group(group)).firstWhere((g) => g != null, orElse: () => null);

  final codes = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final prefix = parts[i]!.group(1) ?? near(parts.take(i).toList().reversed, 1);
    final number = parts[i]!.group(2) ?? near(parts.skip(i + 1), 2);
    if (prefix != null && number != null) codes.add('$prefix $number');
  }
  return codes.isEmpty ? [code.trim()] : codes;
}
