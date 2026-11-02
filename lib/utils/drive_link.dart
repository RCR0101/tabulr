/// Reading Google Drive links the way the Acad Drives crawler does
/// (`extractDriveId` in scripts/acad-drives/acad-drive-master.js), so a link
/// the sync cannot use is caught when it is submitted, not weeks later.
library;

final _patterns = [
  RegExp(r'folders/([a-zA-Z0-9_-]+)'),
  RegExp(r'file/d/([a-zA-Z0-9_-]+)'),
  RegExp(r'[?&]id=([a-zA-Z0-9_-]+)'),
];

/// The folder or file id in a Drive link, or null when [link] is not a
/// Google Drive link the crawler can read. Two links to the same drive
/// ("…?usp=sharing", "…?usp=drive_link") give the same id.
String? driveIdOf(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host != 'drive.google.com' && uri.host != 'docs.google.com') return null;
  for (final p in _patterns) {
    final m = p.firstMatch(link);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Why [link] cannot be submitted, in words a student can act on, or null
/// when it is fine.
String? driveLinkProblem(String link) {
  final text = link.trim();
  if (text.isEmpty) return 'Paste a Google Drive link';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return 'That is not a link. Copy it from Drive → Share → Copy link';
  if (uri.host != 'drive.google.com' && uri.host != 'docs.google.com') {
    return 'Only Google Drive links can be synced';
  }
  if (driveIdOf(text) == null) {
    return 'Link to a Drive folder or file (drive.google.com/drive/folders/… or /file/d/…)';
  }
  return null;
}
