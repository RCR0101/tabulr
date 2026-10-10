// Sorts a drive file into a resource type from its name and folder path.
// The app reads `resource_type` / `exam` / `year`; keep the type keys in sync
// with `AcadResourceType` in lib/models/acad_resource_type.dart.

// Checked in this order within one path segment, so "quiz-1_solutions" is a
// solution, not a paper. MSE/ESE and L1/L2 are left out on purpose: they are
// course nicknames and section names as often as exam or lecture labels.
const TYPE_RULES = [
  // Course admin (seating charts, notices) sits in folders named after the
  // exam it concerns, so it must be caught before "quiz"/"compre" make it a paper.
  ['other', /\b(seating|notices?|announcements?|attendance)\b/],
  ['handout', /\bhandouts?\b/],
  ['solutions', /\b(sol|soln|solns|solutions?|solved|answers?|ans|answer ?keys?)\b/],
  ['pyq', /\b(pyqs?|qp|question ?papers?|papers?|mid ?sem|midsem|midterm|compre|comprehensive|end ?sem|endsem|pre ?compre|pre ?mid ?sem|quiz(zes)?|qz|exams?|(open|closed) ?book)\b/],
  ['lectures', /\b(slides?|ppts?|lec(ture)?s?(slides?)?|lecures?|recordings?|videos?)\b/],
  ['notes', /\b(notes?|handwritten|summary|cheat ?sheets?|study ?materials?)\b/],
  ['books', /\b(books?|textbooks?|tb|rb|reference ?books?|references?|edition|reading ?materials?)\b/],
  ['assignments', /\b(assignments?|assingments?|asignments?|assign|hw|homework|labs?|labsheets?|experiments?|tutorials?|tuts?|tutsheets?|workbooks?|practi[cs]e|problem ?sets?|worksheets?|sheets?)\b/],
];

const LECTURE_EXTENSIONS = new Set(['.ppt', '.pptx', '.key', '.mp4', '.mkv', '.mov', '.webm', '.avi']);

const EXAM_RULES = [
  ['midsem', /\b(mid ?sem|midsem|midterm|mid)\b/],
  ['compre', /\b(compre|comprehensive|end ?sem|endsem|finals?)\b/],
  ['quiz', /\b(quiz(zes)?|qz)\b/],
  // Older courses ran Test 1 / Test 2 in place of quizzes.
  ['test', /\btests?\b/],
];

// A year later than next year is a number in a file name, not a year.
const MAX_YEAR = new Date().getFullYear() + 1;

// Underscores, dots, hyphens and camelCase count as word breaks, so
// "MMP_Midsem_QP" and "DSAmidsemSlides" split.
function normalise(segment) {
  return segment.replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase().replace(/[_.+\-()[\]]+/g, ' ');
}

function classifyResource(fileName, filePath = '') {
  const ext = (fileName.match(/\.[^.]+$/) || [''])[0].toLowerCase();
  const stem = ext ? fileName.slice(0, -ext.length) : fileName;
  const folders = filePath.split('/').slice(0, -1);
  // Nearest first: the file's own name, then its folder, then that folder's parent.
  const segments = [stem, ...folders.reverse()].map(normalise);

  let type = null;
  for (const segment of segments) {
    const hit = TYPE_RULES.find(([, re]) => re.test(segment));
    if (hit) { type = hit[0]; break; }
  }
  if (!type) type = LECTURE_EXTENSIONS.has(ext) ? 'lectures' : 'other';

  const result = { resource_type: type };
  if (type === 'pyq' || type === 'solutions') {
    for (const segment of segments) {
      const exam = EXAM_RULES.find(([, re]) => re.test(segment));
      if (exam) { result.exam = exam[0]; break; }
    }
  }
  // Nearest year wins: "2022 batch/2024 Midsem.pdf" is the 2024 paper.
  for (const segment of segments) {
    const years = (segment.match(/\b20[0-3]\d\b/g) || []).map(Number).filter(y => y <= MAX_YEAR);
    if (years.length) { result.year = years[years.length - 1]; break; }
  }
  return result;
}

module.exports = { classifyResource };

if (require.main === module) {
  const assert = require('assert');
  const check = (name, p, expected) =>
    assert.deepStrictEqual(classifyResource(name, p), expected, `${p}`);

  check('MMP_Midsem_Solutions.pdf', 'MMP/PYQs/MMP_Midsem_Solutions.pdf',
    { resource_type: 'solutions', exam: 'midsem' });
  check('MMP Compre.pdf', 'MMP/PYQs/MMP Compre.pdf', { resource_type: 'pyq', exam: 'compre' });
  check('quiz-1_solutions.pdf', 'MMP/PYQs/quiz-1_solutions.pdf',
    { resource_type: 'solutions', exam: 'quiz' });
  // The folder decides when the file name says nothing.
  check('Practice Sheet-2.pdf', 'MMP/Practice Sheets/Practice Sheet-2.pdf',
    { resource_type: 'assignments' });
  check('1-intro.pdf', 'CS F469/Slides/1-intro.pdf', { resource_type: 'lectures' });
  check('DAA-Notes.pdf', '3-2/CS F364/DAA-Notes.pdf', { resource_type: 'notes' });
  check('TOR Handout.docx', 'Theory of Relativity/TOR Handout.docx', { resource_type: 'handout' });
  check('week3.pptx', 'CS F211/week3.pptx', { resource_type: 'lectures' });
  check('random.pdf', 'CS F211/random.pdf', { resource_type: 'other' });
  check('2024 Midsem.pdf', 'DSA/2022-23/2024 Midsem.pdf',
    { resource_type: 'pyq', exam: 'midsem', year: 2024 });
  check('Midsem 2023.pdf', 'CS F211/PYQs/2021/Midsem 2023.pdf',
    { resource_type: 'pyq', exam: 'midsem', year: 2023 });
  // "Labs" must not swallow a solution file inside it.
  check('Lab 3 solution.pdf', 'CS F111/Labs/Lab 3 solution.pdf', { resource_type: 'solutions' });
  // Admin pages filed under an exam folder are not papers.
  check('Seating chart.xlsx', 'HSS F340/Compre-Seating Chart/Seating chart.xlsx', { resource_type: 'other' });
  check('Comp+-+closed+book.docx', 'OPAC/Question Papers/ME F311/Comp+-+closed+book.docx', { resource_type: 'pyq' });
  check('Test+2.docx', 'OPAC/Question Papers/HSS F337/Test+2.docx', { resource_type: 'pyq', exam: 'test' });
  check('DSA-L10.pdf', 'Drive/DSAmidsemSlides/DSA-L10.pdf', { resource_type: 'lectures' });
  check('TCP.pdf', 'CN/Assingment/TCP.pdf', { resource_type: 'assignments' });
  check('precompre-M3.pdf', 'M3/precompre-M3.pdf', { resource_type: 'pyq' });
  console.log('classify.js self-check passed');
}
