/// Which courses Acad Drives is thin on, for Admin → Acad Drives Quality:
/// courses running this semester (the timetable) set against what has been
/// synced (the drives index) and what students have asked for.
library;

class CoverageRow {
  CoverageRow({
    required this.code,
    required this.title,
    required this.running,
    required this.files,
    required this.pastPapers,
    required this.requestsByType,
    required this.requesters,
    required this.notes,
  });

  final String code;
  final String title;

  /// Offered this semester (in the live timetable).
  final bool running;
  final int files;
  final int pastPapers;

  /// Requests per resource type key ("pyq", "notes", …).
  final Map<String, int> requestsByType;

  /// Distinct students who asked for anything in this course.
  final int requesters;
  final List<String> notes;

  int get requests => requestsByType.values.fold(0, (a, b) => a + b);
  bool get noFiles => files == 0;
  bool get noPastPapers => pastPapers == 0;
  bool get isGap => requests > 0 || (running && (noFiles || noPastPapers));
}

enum CoverageFilter { gaps, noFiles, noPastPapers, requested }

String _norm(String code) => code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

/// [courses]: timetable rows ({course_code, title}). [index]: drives index
/// entries ({code, fileCount, typeCounts}). [requests]: request docs
/// ({course, type, requestedBy, note}). Sorted most-asked first, then
/// emptiest first, then by code.
List<CoverageRow> buildCoverage(
  List<Map<String, dynamic>> courses,
  List<Map<String, dynamic>> index,
  List<Map<String, dynamic>> requests,
) {
  final byCode = {for (final e in index) _norm('${e['code'] ?? ''}'): e};
  final titles = <String, String>{};
  final running = <String>{};
  for (final c in courses) {
    final code = _norm('${c['course_code'] ?? ''}');
    if (code.isEmpty) continue;
    running.add(code);
    titles[code] = '${c['title'] ?? ''}';
  }
  final asked = <String, Map<String, int>>{};
  final who = <String, Set<String>>{};
  final notes = <String, List<String>>{};
  for (final r in requests) {
    final code = _norm('${r['course'] ?? ''}');
    if (code.isEmpty) continue;
    final type = '${r['type'] ?? 'any'}';
    (asked[code] ??= {})[type] = (asked[code]![type] ?? 0) + 1;
    (who[code] ??= {}).add('${r['requestedBy'] ?? ''}');
    final note = '${r['note'] ?? ''}'.trim();
    if (note.isNotEmpty) (notes[code] ??= []).add(note);
  }

  final rows = [
    for (final code in {...running, ...asked.keys})
      CoverageRow(
        code: code,
        title: titles[code] ?? '',
        running: running.contains(code),
        files: (byCode[code]?['fileCount'] as num?)?.toInt() ?? 0,
        pastPapers: ((byCode[code]?['typeCounts'] as Map?)?['pyq'] as num?)?.toInt() ?? 0,
        requestsByType: asked[code] ?? const {},
        requesters: who[code]?.length ?? 0,
        notes: notes[code] ?? const [],
      ),
  ];
  rows.sort((a, b) {
    final r = b.requesters.compareTo(a.requesters);
    if (r != 0) return r;
    final f = a.files.compareTo(b.files);
    if (f != 0) return f;
    return a.code.compareTo(b.code);
  });
  return rows;
}

List<CoverageRow> filterCoverage(List<CoverageRow> rows, CoverageFilter filter) => [
      for (final r in rows)
        if (switch (filter) {
          CoverageFilter.gaps => r.isGap,
          CoverageFilter.noFiles => r.running && r.noFiles,
          CoverageFilter.noPastPapers => r.running && r.noPastPapers,
          CoverageFilter.requested => r.requests > 0,
        })
          r,
    ];
