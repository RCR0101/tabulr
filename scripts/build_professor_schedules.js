import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from parent directory (.env in project root)
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// Initialize Firebase Admin
const serviceAccount = {
  type: "service_account",
  project_id: process.env.FIREBASE_PROJECT_ID,
  private_key_id: process.env.FIREBASE_PRIVATE_KEY_ID,
  private_key: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  client_email: process.env.FIREBASE_CLIENT_EMAIL,
  client_id: process.env.FIREBASE_CLIENT_ID,
  auth_uri: process.env.FIREBASE_AUTH_URI,
  token_uri: process.env.FIREBASE_TOKEN_URI,
  auth_provider_x509_cert_url: process.env.FIREBASE_AUTH_PROVIDER_X509_CERT_URL,
  client_x509_cert_url: process.env.FIREBASE_CLIENT_X509_CERT_URL
};

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();

/**
 * Calculates Levenshtein distance between two strings
 * @param {string} a - First string
 * @param {string} b - Second string
 * @returns {number} - Edit distance
 */
function levenshteinDistance(a, b) {
  const matrix = [];

  for (let i = 0; i <= b.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1, // substitution
          matrix[i][j - 1] + 1,     // insertion
          matrix[i - 1][j] + 1      // deletion
        );
      }
    }
  }

  return matrix[b.length][a.length];
}

/**
 * Calculates similarity score between two strings (0-1)
 * @param {string} a - First string
 * @param {string} b - Second string
 * @returns {number} - Similarity score (1 = identical, 0 = completely different)
 */
function similarityScore(a, b) {
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1;
  const distance = levenshteinDistance(a, b);
  return 1 - (distance / maxLen);
}

/**
 * Normalizes a name for comparison
 * - Uppercase
 * - Remove extra spaces
 * - Remove common titles/suffixes
 * @param {string} name - Raw name
 * @returns {string} - Normalized name
 */
function normalizeName(name) {
  return name
    .toUpperCase()
    .trim()
    .replace(/\s+/g, ' ')  // Multiple spaces to single
    .replace(/\bDR\.?\s*/gi, '')  // Remove Dr.
    .replace(/\bPROF\.?\s*/gi, '')  // Remove Prof.
    .replace(/\bMR\.?\s*/gi, '')  // Remove Mr.
    .replace(/\bMS\.?\s*/gi, '')  // Remove Ms.
    .replace(/\bMRS\.?\s*/gi, '')  // Remove Mrs.
    .trim();
}

/**
 * Extracts initials and last name pattern from a name
 * e.g., "Srinivasa P" -> { initials: ['P'], mainParts: ['SRINIVASA'] }
 * e.g., "P Srinivasa" -> { initials: ['P'], mainParts: ['SRINIVASA'] }
 */
function extractNameParts(name) {
  const normalized = normalizeName(name);
  const parts = normalized.split(' ').filter(p => p.length > 0);

  const initials = [];
  const mainParts = [];

  for (const part of parts) {
    // Single letter (possibly with dot) is an initial
    if (part.length === 1 || (part.length === 2 && part.endsWith('.'))) {
      initials.push(part.replace('.', ''));
    } else {
      mainParts.push(part);
    }
  }

  return { initials, mainParts };
}

/**
 * Checks if two names likely refer to the same person using fuzzy matching
 * @param {string} name1 - First name (from profs.json)
 * @param {string} name2 - Second name (from courses)
 * @returns {{ match: boolean, score: number, reason: string }}
 */
function fuzzyNameMatch(name1, name2) {
  const n1 = normalizeName(name1);
  const n2 = normalizeName(name2);

  // Exact match
  if (n1 === n2) {
    return { match: true, score: 1.0, reason: 'exact' };
  }

  // Direct similarity check
  const directSimilarity = similarityScore(n1, n2);
  if (directSimilarity >= 0.85) {
    return { match: true, score: directSimilarity, reason: 'high_similarity' };
  }

  // Extract name parts
  const parts1 = extractNameParts(name1);
  const parts2 = extractNameParts(name2);

  // Check if main parts match closely
  // IMPORTANT: We need to ensure that MOST parts match, not just one
  // E.g., "RISITA SAHU" should NOT match "PRASANTA KUMAR SAHU" just because "SAHU" matches
  if (parts1.mainParts.length > 0 && parts2.mainParts.length > 0) {
    const minParts = Math.min(parts1.mainParts.length, parts2.mainParts.length);
    const maxParts = Math.max(parts1.mainParts.length, parts2.mainParts.length);

    // Count how many main parts match between the two names
    let matchedParts = 0;
    const usedParts2 = new Set();

    for (const mp1 of parts1.mainParts) {
      for (const mp2 of parts2.mainParts) {
        if (!usedParts2.has(mp2) && similarityScore(mp1, mp2) >= 0.85) {
          matchedParts++;
          usedParts2.add(mp2);
          break;
        }
      }
    }

    // Require at least 50% of parts to match, AND at least the shorter name's parts count
    // This prevents "RISITA SAHU" from matching "PRASANTA KUMAR SAHU" (only 1 of 2 parts match)
    const matchRatio = matchedParts / maxParts;

    // For names with only one main part each, they must match directly
    if (minParts === 1 && maxParts === 1) {
      if (matchedParts === 1) {
        const initialsCompatible = checkInitialsCompatible(parts1, parts2);
        if (initialsCompatible) {
          return { match: true, score: 0.9, reason: 'single_main_part_match' };
        }
      }
    }
    // For names with multiple parts, require most parts to match
    else if (matchedParts >= minParts && matchRatio >= 0.5) {
      const initialsCompatible = checkInitialsCompatible(parts1, parts2);
      if (initialsCompatible) {
        const score = 0.85 * (matchedParts / maxParts);
        return { match: true, score: Math.max(0.7, score), reason: 'main_parts_match_with_initials' };
      }
    }
  }

  // Check if one name's initial matches another's full name start
  // e.g., "P SRINIVASA" matches "PHANINDRA SRINIVASA" (P = Phanindra)
  // VERY STRICT: Only allow this for simple cases where:
  // - One name has 1 initial + 1 main part
  // - Other name has 2+ main parts where one starts with the initial
  // - The main parts must match
  if (parts1.initials.length === 1 && parts1.mainParts.length === 1 && parts2.mainParts.length >= 2 && parts2.initials.length === 0) {
    const init = parts1.initials[0];
    const mainPart = parts1.mainParts[0];

    // Find a part in parts2 that starts with the initial
    for (const mp of parts2.mainParts) {
      if (mp.startsWith(init) && mp !== mainPart) {
        // Check if mainPart matches one of the remaining parts
        const remainingParts2 = parts2.mainParts.filter(p => p !== mp);
        for (const rp2 of remainingParts2) {
          if (similarityScore(mainPart, rp2) >= 0.85) {
            return { match: true, score: 0.8, reason: 'initial_expansion_match' };
          }
        }
      }
    }
  }

  // Reverse check - same strict logic
  if (parts2.initials.length === 1 && parts2.mainParts.length === 1 && parts1.mainParts.length >= 2 && parts1.initials.length === 0) {
    const init = parts2.initials[0];
    const mainPart = parts2.mainParts[0];

    for (const mp of parts1.mainParts) {
      if (mp.startsWith(init) && mp !== mainPart) {
        const remainingParts1 = parts1.mainParts.filter(p => p !== mp);
        for (const rp1 of remainingParts1) {
          if (similarityScore(mainPart, rp1) >= 0.85) {
            return { match: true, score: 0.8, reason: 'initial_expansion_match_reverse' };
          }
        }
      }
    }
  }

  // Subset match - DISABLED as it causes too many false positives
  // Names like "JAYESH A K" matching "PANCHAL KANAN JAYESH PANNA" just because JAYESH appears in both
  // If needed, this could be re-enabled with much stricter criteria

  return { match: false, score: directSimilarity, reason: 'no_match' };
}

/**
 * Check if initials between two name part sets are compatible
 */
function checkInitialsCompatible(parts1, parts2) {
  // If either has no initials, they're compatible
  if (parts1.initials.length === 0 || parts2.initials.length === 0) {
    return true;
  }

  // Check if any initials match
  for (const i1 of parts1.initials) {
    for (const i2 of parts2.initials) {
      if (i1 === i2) return true;
    }
    // Check if initial matches start of other's main part
    for (const mp2 of parts2.mainParts) {
      if (mp2.startsWith(i1)) return true;
    }
  }

  for (const i2 of parts2.initials) {
    for (const mp1 of parts1.mainParts) {
      if (mp1.startsWith(i2)) return true;
    }
  }

  return false;
}

// Minimum score threshold for fuzzy matches to be accepted
const FUZZY_MATCH_THRESHOLD = 0.7;

/**
 * Finds the best matching professor name from profs.json for a course instructor name
 * @param {string} courseProfName - Instructor name from course data
 * @param {string[]} profsJsonNames - Array of professor names from profs.json
 * @returns {{ match: string | null, score: number, reason: string }}
 */
function findBestMatch(courseProfName, profsJsonNames) {
  let bestMatch = null;
  let bestScore = 0;
  let bestReason = 'no_match';

  for (const profName of profsJsonNames) {
    const result = fuzzyNameMatch(profName, courseProfName);
    if (result.match && result.score > bestScore) {
      bestMatch = profName;
      bestScore = result.score;
      bestReason = result.reason;
    }
  }

  // Only return match if score meets the threshold
  if (bestScore >= FUZZY_MATCH_THRESHOLD) {
    return { match: bestMatch, score: bestScore, reason: bestReason };
  }

  return { match: null, score: bestScore, reason: 'below_threshold' };
}

/**
 * Normalizes instructor name: uppercase, trim, handle multiple instructors
 * @param {string} instructor - Raw instructor string from course data
 * @returns {string[]} - Array of normalized instructor names
 */
function normalizeInstructorNames(instructor) {
  if (!instructor || instructor.toString().trim() === '') {
    return [];
  }

  // Split by comma or forward slash, trim each, convert to uppercase
  return instructor
    .toString()
    .split(/[,\/]/)
    .map(name => name.trim().toUpperCase())
    .filter(name => name !== '');
}

/**
 * Builds a map of professor name -> schedule entries
 * Each schedule entry contains: courseCode, courseTitle, sectionId, room, days, hours
 */
async function buildProfessorScheduleMap() {
  console.log('📚 Fetching courses from hyd-courses collection...');

  const coursesSnapshot = await db.collection('hyd-courses').get();
  console.log(`📖 Found ${coursesSnapshot.size} courses`);

  // Map: professorName (uppercase) -> array of schedule entries
  const professorScheduleMap = {};

  coursesSnapshot.forEach(doc => {
    const course = doc.data();
    const courseCode = course.courseCode;
    const courseTitle = course.courseTitle;

    if (!course.sections || !Array.isArray(course.sections)) {
      return;
    }

    course.sections.forEach(section => {
      const instructorNames = normalizeInstructorNames(section.instructor);
      const room = section.room || '';
      const sectionId = section.sectionId || '';
      const schedule = section.schedule || [];

      // For each instructor in this section
      instructorNames.forEach(profName => {
        if (!professorScheduleMap[profName]) {
          professorScheduleMap[profName] = [];
        }

        // For each schedule entry (day-hour combination)
        schedule.forEach(scheduleEntry => {
          const days = scheduleEntry.days || [];
          const hours = scheduleEntry.hours || [];

          professorScheduleMap[profName].push({
            courseCode,
            courseTitle,
            sectionId,
            room,
            days, // e.g., ['DayOfWeek.M', 'DayOfWeek.W', 'DayOfWeek.F']
            hours, // e.g., [1, 2]
          });
        });
      });
    });
  });

  console.log(`👨‍🏫 Built schedule map for ${Object.keys(professorScheduleMap).length} unique professors`);

  return professorScheduleMap;
}

/**
 * Updates the professors collection with schedule data
 */
async function updateProfessorsWithSchedules() {
  try {
    console.log('🚀 Starting professor schedule update...');

    // Step 1: Build the professor schedule map from courses
    const professorScheduleMap = await buildProfessorScheduleMap();

    // Step 2: Read existing professors from profs.json
    const profsJsonPath = path.join(__dirname, 'profs.json');
    if (!fs.existsSync(profsJsonPath)) {
      throw new Error('profs.json not found');
    }

    const professorData = JSON.parse(fs.readFileSync(profsJsonPath, 'utf8'));
    console.log(`📖 Loaded ${professorData.profs.length} professors from profs.json`);

    // Get all professor names from profs.json for fuzzy matching
    const profsJsonNames = professorData.profs
      .filter(p => p.name)
      .map(p => p.name.trim().toUpperCase());

    // Step 3: Build fuzzy match mapping from course names to profs.json names
    console.log('🔍 Building fuzzy match mapping...');
    const courseToJsonNameMap = {}; // courseProfName -> profsJsonName
    const fuzzyMatches = []; // For logging
    const courseProfsNotMatched = []; // Course profs that couldn't be matched

    for (const courseProfName of Object.keys(professorScheduleMap)) {
      // First try exact match
      if (profsJsonNames.includes(courseProfName)) {
        courseToJsonNameMap[courseProfName] = courseProfName;
        continue;
      }

      // Try fuzzy match
      const bestMatch = findBestMatch(courseProfName, profsJsonNames);
      if (bestMatch.match) {
        courseToJsonNameMap[courseProfName] = bestMatch.match;
        fuzzyMatches.push({
          course: courseProfName,
          json: bestMatch.match,
          score: bestMatch.score,
          reason: bestMatch.reason
        });
      } else {
        courseProfsNotMatched.push(courseProfName);
      }
    }

    console.log(`✅ Exact matches: ${Object.keys(professorScheduleMap).length - fuzzyMatches.length - courseProfsNotMatched.length}`);
    console.log(`🔗 Fuzzy matches: ${fuzzyMatches.length}`);
    console.log(`❌ Unmatched course profs: ${courseProfsNotMatched.length}`);

    if (fuzzyMatches.length > 0) {
      console.log('\n📋 Fuzzy matches found:');
      fuzzyMatches.forEach(m => {
        console.log(`   "${m.course}" → "${m.json}" (${(m.score * 100).toFixed(0)}%, ${m.reason})`);
      });
    }

    // Step 4: Build merged schedule map using profs.json names as keys
    const mergedScheduleMap = {};
    for (const [courseProfName, schedule] of Object.entries(professorScheduleMap)) {
      const jsonName = courseToJsonNameMap[courseProfName];
      if (jsonName) {
        if (!mergedScheduleMap[jsonName]) {
          mergedScheduleMap[jsonName] = [];
        }
        mergedScheduleMap[jsonName].push(...schedule);
      }
    }

    // Step 5: Clear existing professors collection
    console.log('\n🔄 Clearing existing professor data...');
    const professorsRef = db.collection('professors');
    const existingSnapshot = await professorsRef.get();

    const deletePromises = [];
    existingSnapshot.forEach(doc => {
      deletePromises.push(doc.ref.delete());
    });

    if (deletePromises.length > 0) {
      await Promise.all(deletePromises);
      console.log(`🗑️ Deleted ${deletePromises.length} existing professor records`);
    }

    // Step 6: Upload professors with schedule data
    console.log('⬆️ Uploading professors with schedule data...');
    const uploadPromises = [];
    let matchedCount = 0;
    let unmatchedCount = 0;

    professorData.profs.forEach((prof, index) => {
      if (!prof.name || !prof.chamber) {
        console.warn(`⚠️ Skipping invalid professor at index ${index}:`, prof);
        return;
      }

      const profNameNormalized = prof.name.trim().toUpperCase();
      const schedule = mergedScheduleMap[profNameNormalized] || [];

      if (schedule.length > 0) {
        matchedCount++;
      } else {
        unmatchedCount++;
      }

      const docRef = professorsRef.doc();
      const professorDoc = {
        id: docRef.id,
        name: prof.name.trim(),
        chamber: prof.chamber.trim(),
        nameSearch: prof.name.trim().toLowerCase(),
        chamberSearch: prof.chamber.trim().toLowerCase(),
        // New schedule field
        schedule: schedule,
        createdAt: new Date(),
        updatedAt: new Date()
      };

      uploadPromises.push(docRef.set(professorDoc));
    });

    await Promise.all(uploadPromises);
    console.log(`✅ Successfully uploaded ${uploadPromises.length} professor records`);
    console.log(`📊 Professors with schedule: ${matchedCount}`);
    console.log(`📊 Professors without schedule: ${unmatchedCount}`);

    // Step 7: Update metadata
    const metadataRef = db.collection('metadata').doc('professors');
    await metadataRef.set({
      totalProfessors: uploadPromises.length,
      professorsWithSchedule: matchedCount,
      professorsWithoutSchedule: unmatchedCount,
      fuzzyMatchesApplied: fuzzyMatches.length,
      lastUpdated: new Date(),
      version: '2.1.0', // Bumped version for fuzzy matching support
      uploadedBy: 'admin_script'
    });

    console.log('📝 Metadata updated successfully');
    console.log('🎉 Professor schedule update completed!');

    // Step 8: Output unmatched course professors
    if (courseProfsNotMatched.length > 0) {
      console.log('\n⚠️ Professors found in courses but could not be matched to profs.json:');
      courseProfsNotMatched.slice(0, 30).forEach(p => console.log(`   - ${p}`));
      if (courseProfsNotMatched.length > 30) {
        console.log(`   ... and ${courseProfsNotMatched.length - 30} more`);
      }
    }

  } catch (error) {
    console.error('❌ Error updating professor schedules:', error);
    process.exit(1);
  }
}

// Run the update
updateProfessorsWithSchedules().then(() => {
  console.log('🏁 Script finished');
  process.exit(0);
}).catch(error => {
  console.error('💥 Script failed:', error);
  process.exit(1);
});
