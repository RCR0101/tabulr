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
