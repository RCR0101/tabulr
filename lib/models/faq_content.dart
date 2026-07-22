import 'package:flutter/material.dart';

/// One question and its answer.
///
/// [answer] is a short lead paragraph; [bullets] carry the specifics that are
/// easier to scan as a list. [source] cites the governing clause so a student
/// can verify the claim rather than take the app's word for it.
class FaqEntry {
  const FaqEntry({
    required this.question,
    required this.answer,
    this.bullets = const [],
    this.source,
    this.keywords = const [],
  });

  final String question;
  final String answer;
  final List<String> bullets;
  final String? source;

  /// Extra terms that should match this entry in search but don't appear in
  /// the visible text (synonyms, abbreviations students actually type).
  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return question.toLowerCase().contains(q) ||
        answer.toLowerCase().contains(q) ||
        bullets.any((b) => b.toLowerCase().contains(q)) ||
        keywords.any((k) => k.toLowerCase().contains(q)) ||
        (source?.toLowerCase().contains(q) ?? false);
  }
}

class FaqCategory {
  const FaqCategory({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<FaqEntry> entries;
}

/// Curated answers drawn from the BITS Pilani Academic Regulations (18th
/// printing, March 2023) and the Bulletin 2025-26.
///
/// Deliberately not a transcription: each entry is the short version of a rule
/// students actually ask about, with the clause cited so the full text can be
/// looked up when the detail matters. Keep answers to a few lines — anything
/// longer belongs in the source document, not here.
const List<FaqCategory> faqCategories = [
  FaqCategory(
    title: 'Grades & CGPA',
    icon: Icons.calculate_outlined,
    entries: [
      FaqEntry(
        question: 'What is each grade worth?',
        answer:
            'Letter grades carry the grade points used in every CGPA calculation.',
        bullets: [
          'A — 10  ·  Excellent',
          'A- — 9  ·  Very Good',
          'B — 8  ·  Good',
          'B- — 7  ·  Above Average',
          'C — 6  ·  Fair / Average',
          'C- — 5  ·  Below Average',
          'D — 4  ·  Poor',
          'E — 2  ·  Exposed',
        ],
        source: 'Academic Regulations 4.11',
        keywords: ['grade points', 'marks', 'scale'],
      ),
      FaqEntry(
        question: 'How is CGPA actually calculated?',
        answer:
            'It is the credit-weighted average of grade points across every course you have been awarded a letter grade in, since you joined.',
        bullets: [
          'CGPA = Σ(units × grade points) ÷ Σ(units)',
          'Only letter grades count — reports like NC or W are excluded entirely.',
          'It covers everything from entry up to the latest semester or term.',
        ],
        source: 'Academic Regulations 4.21',
        keywords: ['cg', 'sgpa', 'formula', 'average'],
      ),
      FaqEntry(
        question: 'If I repeat a course, do both grades count?',
        answer:
            'No. The new grade replaces the earlier one in the CGPA — the old attempt stops counting entirely.',
        bullets: [
          'This only applies when a real grade emerges from the repeat.',
          'If the repeat produces just a report (NC, W, RC), your earlier grade stands.',
        ],
        source: 'Academic Regulations 4.21',
        keywords: ['repeat', 'retake', 'again', 'summer'],
      ),
      FaqEntry(
        question: 'What is NC, and does it hurt my CGPA?',
        answer:
            'NC (Not Cleared) is a report, not a grade. It carries no grade points and its units stay out of your CGPA — so it neither raises nor lowers the number.',
        bullets: [
          'It is reported when you stayed registered but gave the instructor no real basis to evaluate you.',
          'For a compulsory course you must register again and earn a valid grade.',
          'For an elective you may repeat it or choose a different elective instead.',
        ],
        source: 'Academic Regulations 4.19, 4.20',
        keywords: ['not cleared', 'fail', 'zero'],
      ),
      FaqEntry(
        question: 'What do W, RC, I and GA mean?',
        answer:
            'All four are reports rather than grades, so none of them affects your CGPA.',
        bullets: [
          'W — Withdrawn from the course.',
          'RC — Registration Cancelled.',
          'I — Incomplete; a temporary report pending a real grade.',
          'GA — Grade Awaited, used when a grade is delayed.',
          'For W and RC the rule is to fall back to your previous performance in that course, if any.',
        ],
        source: 'Academic Regulations 4.13–4.19',
        keywords: ['withdraw', 'incomplete', 'grade awaited', 'reports'],
      ),
      FaqEntry(
        question: 'Do audit courses count toward CGPA?',
        answer:
            'No. Audited courses are graded Satisfactory or Unsatisfactory, which are non-letter grades and sit outside the CGPA.',
        source: 'Academic Regulations 4.11',
        keywords: ['audit', 'atc', 'satisfactory'],
      ),
      FaqEntry(
        question: 'Is there a separate CGPA for a minor?',
        answer:
            'Yes. A first-degree student pursuing a minor is awarded an additional CGPA specifically for that minor, alongside the degree CGPA.',
        bullets: [
          'The minor CGPA does not change how those courses count toward your degree CGPA.',
          'A minor certificate needs at least 4.50 in the courses applied to it.',
        ],
        source: 'Academic Regulations 4.21, 9.01a',
        keywords: ['minor', 'certificate'],
      ),
    ],
  ),
  FaqCategory(
    title: 'Academic Standing',
    icon: Icons.trending_up,
    entries: [
      FaqEntry(
        question: 'What are the minimum requirements each semester?',
        answer:
            'Three standards are checked at the end of every semester. Failing even one is called an "affliction".',
        bullets: [
          'No more than one E grade (integrated first degree); any E counts for a higher degree.',
          'CGPA of at least 4.50 (first degree) or 5.50 (higher degree).',
          'Cleared the courses expected for two-thirds of the semesters you have spent — i.e. never more than 50% extra time.',
        ],
        source: 'Academic Regulations 5.02',
        keywords: ['minimum', 'affliction', 'requirement', 'standing'],
      ),
      FaqEntry(
        question: 'What is ACB?',
        answer:
            'The Academic Counselling Board takes charge of students who fall short of the minimum requirements, with the single objective of steering them back out.',
        bullets: [
          'While under ACB you lose the usual registration freedoms — course choice, repetition, overloading and amendments.',
          'ACB sets a specific course package and time frame each semester.',
          'Meeting clause 5.02 again in a later semester is the minimum condition for release.',
        ],
        source: 'Academic Regulations 5.03, 5.04',
        keywords: ['acb', 'counselling', 'probation', 'backlog'],
      ),
      FaqEntry(
        question: 'How many units can I register for?',
        answer:
            'A first-degree student may register up to 25 units in a semester; a higher-degree student up to 20, excluding any deficiency or audit courses.',
        bullets: [
          'One unit is roughly three hours of total effort per week, including self-study.',
          'A higher-degree student may take at most 2 deficiency or audit courses.',
        ],
        source: 'Academic Regulations 1.01, 1.05',
        keywords: ['units', 'credits', 'overload', 'load'],
      ),
    ],
  ),
  FaqCategory(
    title: 'Exams & Evaluation',
    icon: Icons.assignment_outlined,
    entries: [
      FaqEntry(
        question: 'How is a course evaluated?',
        answer:
            'Every structured course has at least three evaluation components, one of which must be a comprehensive examination covering the whole course, held at the end of the semester.',
        bullets: [
          'At least 20% of evaluation must be open book for a first-degree course; 40% for a higher-degree course.',
          'Components are spread evenly through the semester.',
          'The instructor announces the full scheme within one week of classes starting.',
        ],
        source: 'Academic Regulations 4.05, 4.04',
        keywords: ['compre', 'midsem', 'exam', 'evaluation', 'open book'],
      ),
      FaqEntry(
        question: 'I missed a test — can I get a make-up?',
        answer:
            'Approach the instructor-in-charge immediately. If satisfied it was genuine, they may arrange a make-up as close as possible to the original.',
        bullets: [
          'If you can anticipate the clash, tell the instructor beforehand.',
          'The instructor-in-charge\'s decision on make-ups is final.',
        ],
        source: 'Academic Regulations 4.07',
        keywords: ['makeup', 'make-up', 'missed', 'absent'],
      ),
      FaqEntry(
        question: 'Do I get to see my evaluated answer scripts?',
        answer:
            'Yes. Answer scripts must be promptly evaluated, shown to you for clarification and returned wherever practicable, and performance discussed in class.',
        source: 'Academic Regulations 4.08',
        keywords: ['answer script', 'paper', 'recheck', 'feedback'],
      ),
    ],
  ),
  FaqCategory(
    title: 'Courses & Registration',
    icon: Icons.menu_book_outlined,
    entries: [
      FaqEntry(
        question: 'Can I swap or drop a course after registering?',
        answer:
            'Yes, but the two options have different deadlines and you have to initiate both yourself.',
        bullets: [
          'Substitution (swap one course for another) — within 2 weeks of the semester starting, or 1 week for the summer term.',
          'Withdrawal (drop it entirely) — a formal application within 10 weeks of the semester starting, or 5 weeks for the summer term.',
          'A withdrawal is reported as W, which does not affect your CGPA.',
          'In genuinely exceptional circumstances the Dean may allow withdrawal from any or all courses.',
        ],
        source: 'Academic Regulations 3.26',
        keywords: ['drop', 'withdraw', 'substitute', 'swap', 'deadline', 'add drop'],
      ),
      FaqEntry(
        question: 'Can I repeat a course I already passed to improve my grade?',
        answer:
            'Yes — repeating a cleared course to improve the grade is allowed at your own option, if the Institute has room for it and the course is part of your current prescribed programme.',
        bullets: [
          'The new grade replaces the old one in your CGPA.',
          'It stops being available once you have completed the graduation requirements, or are just short of them via PS or Thesis/Seminar.',
          'Practice School, Thesis, Seminar, Internship and project courses cannot be repeated this way.',
          'You cannot spend a whole semester doing nothing but repeats.',
        ],
        source: 'Academic Regulations 3.25 II',
        keywords: ['repeat', 'improve', 'grade improvement', 'retake'],
      ),
      FaqEntry(
        question: 'Do I have to take electives in the listed semester?',
        answer:
            'No. You may delay or advance an elective relative to where it appears in the semester-wise pattern, planning your whole elective quota yourself — at your own responsibility.',
        source: 'Academic Regulations 3.25 IV',
        keywords: ['electives', 'order', 'sequence', 'plan'],
      ),
      FaqEntry(
        question: 'How does the summer term work?',
        answer:
            'Summer term is an accelerated eight-week term, used to catch up or get ahead.',
        bullets: [
          'You may register for at most 3 courses, totalling no more than 10 units.',
          'Some courses — Practice School II, Thesis, Dissertation — cannot be compressed into it.',
        ],
        source: 'Academic Regulations 1.02, 1.03',
        keywords: ['summer', 'st', 'term', 'accelerated'],
      ),
      FaqEntry(
        question: 'Is a summer course guaranteed to run?',
        answer:
            'No. Summer offerings exist mainly for students who can graduate that term. Others may register if there is room, but a course can be cancelled if the students it was opened for withdraw.',
        bullets: [
          'A higher-level course in summer needs you to have no backlog — or just one you can register for at the same time.',
        ],
        source: 'Academic Regulations 7.06, 7.07',
        keywords: ['summer', 'cancelled', 'guaranteed'],
      ),
      FaqEntry(
        question: 'How many electives do I need?',
        answer:
            'An integrated first-degree student completes at least 12 elective courses, chosen across the elective categories.',
        bullets: [
          'Humanities electives (HEL), Discipline electives (DEL) and Open electives.',
          'Chosen well, they let you go deeper in your discipline or broaden into another area.',
        ],
        source: 'Bulletin 2025-26, Part II',
        keywords: ['electives', 'huel', 'del', 'open elective'],
      ),
      FaqEntry(
        question: 'What is a minor, and which ones exist?',
        answer:
            'A minor lets you build focused depth outside your major, certified separately on completion.',
        bullets: [
          'Offered in areas including Finance, Data Science, Robotics and Automation, Entrepreneurship, Physics, Philosophy Economics and Politics, Public Policy, Materials Science, Supply Chain Analytics and more.',
          'Availability varies by campus.',
          'Needs the core courses, the stipulated electives, and at least 4.50 in those courses.',
        ],
        source: 'Bulletin 2025-26, Part II · Regulations 9.01a',
        keywords: ['minor', 'specialisation', 'specialization'],
      ),
      FaqEntry(
        question: 'What does a prerequisite actually stop me doing?',
        answer:
            'Courses are meant to be taken in the sequence given in the Bulletin. Falling out of that order builds a backlog, which the regulations treat as something to correct quickly rather than carry.',
        bullets: [
          'Left uncorrected, a backlog can create an illusion of progress while costing you time overall.',
          'A large backlog brings you under ACB.',
        ],
        source: 'Academic Regulations 1.10, 3.25',
        keywords: ['prerequisite', 'prereq', 'backlog', 'sequence'],
      ),
    ],
  ),
  FaqCategory(
    title: 'Practice School & Degrees',
    icon: Icons.work_outline,
    entries: [
      FaqEntry(
        question: 'What is Practice School?',
        answer:
            'Practice School is BITS\'s built-in industry immersion, taken as two courses that put you inside a real professional setting.',
        bullets: [
          'PS-I — about two months, in the summer following your second year.',
          'PS-II — about five and a half months, during the final year.',
          'Every integrated first-degree programme has a Practice School option.',
        ],
        source: 'Bulletin 2025-26, Part II',
        keywords: ['ps', 'ps1', 'ps2', 'internship', 'practice school'],
      ),
      FaqEntry(
        question: 'How does the dual degree scheme work?',
        answer:
            'Dual degree students work toward two first degrees at once, typically taking about 5 to 5½ years — roughly 10 to 11 semesters.',
        bullets: [
          'A single degree normally runs 8 semesters over 4 years.',
          'The modular structure means some students finish faster and some slower.',
        ],
        source: 'Bulletin 2025-26, Part II',
        keywords: ['dual degree', 'dual', 'second degree'],
      ),
      FaqEntry(
        question: 'How does a dual degree actually work day to day?',
        answer:
            'Your two programmes are merged into one composite programme with its own semester pattern — not two degrees run side by side.',
        bullets: [
          'Normally one degree carries Practice School and the other carries Thesis.',
          'Core courses common to both degrees are done only once.',
          'A Discipline Core of one degree cannot be counted as a Discipline Elective of the other.',
          'You cannot finish one degree separately — graduation happens for both together, and both receive the same division.',
        ],
        source: 'Academic Regulations 7.11–7.14',
        keywords: ['dual degree', 'dual', 'composite', 'thesis', 'ps'],
      ),
      FaqEntry(
        question: 'Can I leave the dual degree scheme?',
        answer:
            'Yes — you can apply in writing to Dean AUGS to withdraw, and it is handled as a transfer back to your first degree.',
        bullets: [
          'You cannot do the reverse — dropping the first degree and keeping only the second is not allowed.',
          'Departing from the scheme without permission can get the dual degree cancelled outright.',
        ],
        source: 'Academic Regulations 7.15, 7.16',
        keywords: ['dual degree', 'drop', 'quit', 'withdraw', 'exit'],
      ),
      FaqEntry(
        question: 'Can I transfer to a different programme?',
        answer:
            'Transfers exist between programmes in a tier, between the PS and Thesis options, between dual and single degree, and across tiers — always competitive, and only at the start of a semester.',
        bullets: [
          'Your entire academic record, including CGPA, carries over to the new programme.',
          'Courses that cannot be fitted into the new programme become "unaccounted"; those with grades or NC are frozen and can neither be reused nor repeated.',
          'A transfer is impossible while a sanction from your old situation is unresolved.',
        ],
        source: 'Academic Regulations 7.18–7.21',
        keywords: ['transfer', 'change branch', 'switch', 'branch change'],
      ),
      FaqEntry(
        question: 'What does taking a course on audit actually get me?',
        answer:
            'Audit is for updating your knowledge, not for credit. No degree can be earned through audited courses.',
        bullets: [
          'Even a Satisfactory on audit does not automatically count toward any programme requirement, now or later.',
          'Practice School, Thesis, Dissertation and certain other courses cannot be audited at all.',
          'Courses outside your programme can be taken on audit only, and carry an additional fee.',
        ],
        source: 'Academic Regulations 7.32–7.35',
        keywords: ['audit', 'atc', 'casual', 'credit'],
      ),
      FaqEntry(
        question: 'What are the three tiers of education at BITS?',
        answer:
            'Integrated First Degree programmes, Higher Degree programmes, and Doctoral programmes — designed so all three share structural commonality.',
        bullets: [
          'First degrees are grouped A (B.E. / B.Pharm.), B (M.Sc. sciences) and C (M.Sc. General Studies).',
          'Common courses are taught together regardless of the eventual degree.',
        ],
        source: 'Bulletin 2025-26, Part II',
        keywords: ['tier', 'structure', 'programmes', 'be', 'msc'],
      ),
    ],
  ),
  FaqCategory(
    title: 'Graduation',
    icon: Icons.workspace_premium_outlined,
    entries: [
      FaqEntry(
        question: 'What do I need to graduate?',
        answer:
            'Six conditions have to be satisfied together for a first or higher degree.',
        bullets: [
          'Cleared every course prescribed for your programme.',
          'Cleared the unit requirements for Thesis, Seminar and Dissertation where applicable.',
          'CGPA of at least 4.50 (first degree) or 5.50 (higher degree).',
          'Remained outside the purview of ACB, or been declared out of it.',
          'Resolved the consequences of any NC report.',
          'No pending case of indiscipline or unfair means, and no outstanding dues.',
        ],
        source: 'Academic Regulations 9.01, 9.03',
        keywords: ['graduate', 'graduation', 'degree', 'requirements'],
      ),
      FaqEntry(
        question: 'How is Distinction or Division decided?',
        answer:
            'Integrated first degree programmes are classified purely on final CGPA.',
        bullets: [
          'Distinction — CGPA 9.00 or above',
          'First Division — 7.00 up to 9.00',
          'Second Division — 4.50 up to 7.00',
          'No division is awarded for diplomas, higher degrees or Ph.D. programmes.',
        ],
        source: 'Academic Regulations 9.04',
        keywords: ['distinction', 'division', 'honours', 'class'],
      ),
    ],
  ),
];
