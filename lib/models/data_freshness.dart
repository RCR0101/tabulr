/// When the data for the term now underway should have been uploaded by.
///
/// Odd-semester booklets come out in July and even-semester ones in December,
/// so anything last touched before then is left over from the previous term.
DateTime currentTermStart(DateTime now) {
  if (now.month == 12) return DateTime(now.year, 12);
  if (now.month >= 7) return DateTime(now.year, 7);
  return DateTime(now.year - 1, 12);
}

/// Calendar year the coming exams fall in, the admin upload's "exam year".
/// A December upload is for the even semester, whose exams are next year.
/// Mirrors `default_exam_year` in functions-python/main.py.
int defaultExamYear(DateTime now) => now.month == 12 ? now.year + 1 : now.year;

enum Freshness { current, stale, missing }

Freshness freshnessOf(DateTime? updated, DateTime now) {
  if (updated == null) return Freshness.missing;
  return updated.isBefore(currentTermStart(now)) ? Freshness.stale : Freshness.current;
}

/// Upload markers are written as ISO strings by Python, as `Date`s by Node
/// (Timestamps once read back) and as epoch-ms strings in `version`.
DateTime? parseUploadStamp(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  try {
    return (value as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}
