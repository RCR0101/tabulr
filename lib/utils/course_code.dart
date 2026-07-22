/// Canonical form for comparing course codes across sources.
///
/// The same course is written "CS F320" in the Bulletin, "CSF320" on a pasted
/// performance sheet, and occasionally with a double space in scraped data.
/// Anything matching codes from two different origins has to compare this form
/// rather than the raw strings.
String normalizeCourseCode(String code) =>
    code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
