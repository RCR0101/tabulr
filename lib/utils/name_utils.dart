/// Capitalises the first letter of each word and lowercases the rest, so a name
/// renders the same whether the source shouted it or not.
///
/// Instructor names are *stored* upper-cased — that is the app's canonical
/// professor key, set by `normalizeInstructorNames` in `functions/admin.js` —
/// and "PARDHA SARADHI GURUGUBELLI V" in a list reads as shouting. Identity
/// stays upper case; only the display passes through here.
String titleCaseName(String name) => name
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
    .join(' ');
