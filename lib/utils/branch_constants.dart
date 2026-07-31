/// A BITS-RMIT student's ERP branch is the plain A3 or AA, but their first-year
/// package is not their branchmates' — it drops BITS U103 and adds PHY U101,
/// PHY U110 and BITS F234. The Course Guide keys everything on a branch code
/// and a dual degree is a union of two lists, which cannot express a removal,
/// so the programme gets codes of its own.
const Map<String, String> branchCodeToName = {
  'A1': 'Chemical',
  'A2': 'Civil',
  'A3': 'Electrical and Electronics',
  'A3RMIT': 'Electrical and Electronics (BITS-RMIT)',
  'A4': 'Mechanical',
  'A5': 'Pharma',
  'A7': 'Computer Science',
  'A8': 'Electronics and Instrumentation',
  'AA': 'Electronics and Communication',
  'AARMIT': 'Electronics and Communication (BITS-RMIT)',
  'AB': 'Manufacturing',
  'AC': 'Electronics and Computer',
  'AD': 'Math and Computing',
  'AJ': 'Environmental and Sustainability Engineering',
  'AL': 'Pharmaceutical Engineering',
  'B1': 'MSc Biology',
  'B2': 'MSc Chemistry',
  'B3': 'MSc Economics',
  'B4': 'MSc Mathematics',
  'B5': 'MSc Physics',
  'B7': 'Semiconductors and Nanoscience',
};

bool isMscBranch(String branchCode) =>
    branchCode.startsWith('B');

bool isBeBranch(String branchCode) =>
    branchCode.startsWith('A');

/// The MSc and BE halves of a dual degree, or null when the pair is not one.
///
/// Order-independent: a student may nominate either half as their primary
/// branch, and both orderings describe the same degree. Callers need the roles
/// resolved because the CDC merge is asymmetric — BE courses shift two years
/// later, so swapping the arguments would produce a different, wrong list.
({String msc, String be})? dualDegreePair(
  String primaryBranch,
  String? secondaryBranch,
) {
  if (secondaryBranch == null || secondaryBranch == primaryBranch) return null;
  if (isMscBranch(primaryBranch) && isBeBranch(secondaryBranch)) {
    return (msc: primaryBranch, be: secondaryBranch);
  }
  if (isMscBranch(secondaryBranch) && isBeBranch(primaryBranch)) {
    return (msc: secondaryBranch, be: primaryBranch);
  }
  return null;
}

/// Display label for a branch: `"A7 — Computer Science"`.
///
/// The three elective browsers each showed half of this — Humanities the bare
/// code, Discipline and Open the bare name — so the same branch read
/// differently depending on which screen you were on. Students use both halves:
/// the code is what appears on registration forms, the name is what they'd
/// recognise. Falls back to the code alone when it isn't in [branchCodeToName],
/// so an unknown branch still renders something meaningful.
String branchLabel(String code) {
  final name = branchCodeToName[code];
  return name == null || name.isEmpty ? code : '$code — $name';
}
