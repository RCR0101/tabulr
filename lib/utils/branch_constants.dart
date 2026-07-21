const Map<String, String> branchCodeToName = {
  'A1': 'Chemical',
  'A2': 'Civil',
  'A3': 'Electrical and Electronics',
  'A4': 'Mechanical',
  'A5': 'Pharma',
  'A7': 'Computer Science',
  'A8': 'Electronics and Instrumentation',
  'AA': 'Electronics and Communication',
  'AB': 'Manufacturing',
  'AC': 'Electronics and Computer',
  'AD': 'Math and Computing',
  'AJ': 'Environmental and Sustainability Engineering',
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
