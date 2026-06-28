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
