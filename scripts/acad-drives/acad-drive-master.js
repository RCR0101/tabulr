#!/usr/bin/env node

const admin = require('firebase-admin');
const { S3Client, ListObjectsV2Command, DeleteObjectsCommand, PutObjectCommand, HeadObjectCommand, DeleteObjectCommand, CopyObjectCommand } = require('@aws-sdk/client-s3');
const { google } = require('googleapis');
const Fuse = require('fuse.js');
const stringSimilarity = require('string-similarity');
const fs = require('fs').promises;
const fsSync = require('fs');
const path = require('path');
const readline = require('readline');
const crypto = require('crypto');
const { execFile } = require('child_process');
const { promisify } = require('util');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const { classifyResource } = require('./classify');

const execFileAsync = promisify(execFile);

class AcadDriveMaster {
  constructor() {
    this.db = null;
    this.s3 = null;
    this.drive = null;
    this.courseData = { codes: new Map(), names: new Map(), abbreviations: new Map() };
    this.courseFuse = null; // Fuse.js instance for fuzzy course name matching
    this.nicknameFuse = null; // Fuse.js instance for fuzzy nickname matching
    this.nicknames = new Map();
    this.duplicateCourses = {};
    this.courseAliases = {};
    this.credits = {};

    this.config = {
      serviceAccountPath: process.env.SERVICE_ACCOUNT_PATH || path.join(__dirname, 'serviceAccountKey.json'),
      nicknamesFile: path.join(__dirname, 'nicknames.json'),
      tokenPath: path.join(__dirname, 'gdrive-token.json'),
      downloadsDir: process.env.DOWNLOADS_DIR || path.join(__dirname, 'downloads'),
      r2: {
        accountId: process.env.CLOUDFLARE_ACCOUNT_ID,
        accessKeyId: process.env.CLOUDFLARE_R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY,
        bucketName: process.env.CLOUDFLARE_R2_BUCKET_NAME,
        endpoint: process.env.CLOUDFLARE_R2_ENDPOINT,
        publicUrl: process.env.CLOUDFLARE_R2_PUBLIC_URL,
        customDomain: process.env.CLOUDFLARE_R2_CUSTOM_DOMAIN
      },
      compressionThreshold: 500 * 1024 * 1024,
      basePath: 'tabulr_drives',
      concurrency: 3,
      driveConcurrency: 2,
    };

    this.SCOPES = ['https://www.googleapis.com/auth/drive.readonly'];
    this.stats = { processed: 0, uploaded: 0, skipped: 0, errors: [] };
    this.driveStats = {};
    this.verbose = process.argv.includes('--verbose');
    this.ignoredExtensions = new Set(['.ini', '.tmp', '.log', '.bak', '.cache', '.lock', '.crdownload', '.part', '.partial', '.pyc', '.pyo', '.class', '.o', '.obj', '.dll', '.so', '.dylib']);
    this.ignoredFiles = new Set(['.ds_store', 'thumbs.db', 'desktop.ini', '.gitkeep', '.gitignore']);
    this.ignoredFolders = new Set(['completed', '.git', '__macosx']);
    // Code-environment folders students sync along with an assignment. One
    // drive's .venv alone put ~19k pandas/numpy files into the catalogue.
    this.junkFolders = new Set(['.venv', 'venv', 'site-packages', '__pycache__', 'node_modules',
      '.ipynb_checkpoints', '.idea', '.vscode', '.git', '__macosx']);
    for (const f of this.junkFolders) this.ignoredFolders.add(f);
    this.nonAcademicExtensions = new Set([
      '.exe', '.msi', '.hlp', '.dat', '.shk', '.dll', '.sys', '.bat',
      '.bin', '.iso', '.dmg',
    ]);

    // Exam/academic terms that collide with course abbreviations or nicknames
    this.examTerms = new Set([
      'MSE', 'ESE', 'MTE', 'ETE',           // Mid-Sem / End-Sem exam abbreviations
      'MIDSEM', 'ENDSEM', 'MIDTERM',         // Full exam names
      'COMPRE', 'COMPREHENSIVE',              // Comprehensive exam
      'QZ', 'QUIZ', 'QUIZZES',               // Quiz
      'PYQ', 'PYQS',                          // Previous Year Questions
      'SOLN', 'SOLNS', 'SOLUTION', 'SOLUTIONS', 'ANS', 'ANSWER', 'KEY', 'KEYS',
      'PAPER', 'PAPERS', 'QUESTION',         // Exam papers
      'ASSIGN', 'ASSIGNMENT', 'ASSIGNMENTS', 'HW', 'HOMEWORK',
      'LAB', 'TUTORIAL', 'TUT',              // Class types
      'NOTES', 'NOTE', 'SLIDES', 'SLIDE', 'LECTURE', 'LECTURES',
      'BOOK', 'TEXTBOOK', 'REF', 'REFERENCE',
      'SEM', 'SEMESTER', 'EVEN', 'ODD',
      'MINOR', 'MAJOR',
    ]);

    // Department keywords → course code prefixes for context scoring
    this.deptKeywords = {
      'CS': ['CS ', 'IS '],
      'COMPUTER': ['CS ', 'IS '],
      'COMPUTING': ['CS ', 'IS '],
      'ECE': ['ECE ', 'EEE '],
      'ELECTRICAL': ['ECE ', 'EEE '],
      'ELECTRONICS': ['ECE ', 'EEE '],
      'EEE': ['ECE ', 'EEE '],
      'ME': ['ME ', 'MF '],
      'MECH': ['ME ', 'MF '],
      'MECHANICAL': ['ME ', 'MF '],
      'MANUFACTURING': ['MF '],
      'CHEMICAL': ['CHE '],
      'CHE': ['CHE '],
      'CHEM': ['CHEM ', 'CHE '],
      'CHEMISTRY': ['CHEM '],
      'CIVIL': ['CE '],
      'CE': ['CE '],
      'BIO': ['BIO '],
      'BIOLOGY': ['BIO '],
      'BIOTECH': ['BIO '],
      'PHARMA': ['PHA ', 'PHARMA '],
      'PHARMACY': ['PHA ', 'PHARMA '],
      'PHYSICS': ['PHY '],
      'PHY': ['PHY '],
      'MATH': ['MATH '],
      'MATHEMATICS': ['MATH '],
      'ECON': ['ECON '],
      'ECONOMICS': ['ECON '],
      'FINANCE': ['ECON ', 'FIN '],
      'MANAGEMENT': ['MGTS ', 'GS '],
      'HUMANITIES': ['BITS ', 'GS '],
    };
  }

  async runBatch(tasks, concurrency) {
    const results = [];
    let i = 0;
    async function next() {
      const idx = i++;
      if (idx >= tasks.length) return;
      try {
        results[idx] = await tasks[idx]();
      } catch (err) {
        results[idx] = { error: err };
      }
      await next();
    }
    const workers = Array.from({ length: Math.min(concurrency, tasks.length) }, () => next());
    await Promise.all(workers);
    return results;
  }

  // Logging helpers
  dim(text) { return `\x1b[2m${text}\x1b[0m`; }
  green(text) { return `\x1b[32m${text}\x1b[0m`; }
  red(text) { return `\x1b[31m${text}\x1b[0m`; }
  yellow(text) { return `\x1b[33m${text}\x1b[0m`; }
  cyan(text) { return `\x1b[36m${text}\x1b[0m`; }
  bold(text) { return `\x1b[1m${text}\x1b[0m`; }

  initDriveStats(driveName) {
    this.driveStats[driveName] = { processed: 0, uploaded: 0, skipped: 0, errors: 0, unclassified: 0, startTime: Date.now() };
  }

  driveProgress(driveName) {
    const s = this.driveStats[driveName];
    if (!s) return '';
    const total = s.uploaded + s.skipped + s.errors;
    return this.dim(`[${total}/${s.processed} done]`);
  }

  printDriveSummary(driveName) {
    const s = this.driveStats[driveName];
    if (!s) return;
    const elapsed = ((Date.now() - s.startTime) / 1000).toFixed(1);
    const parts = [];
    if (s.processed > 0) parts.push(`${s.processed} files`);
    if (s.uploaded > 0) parts.push(this.green(`${s.uploaded} uploaded`));
    if (s.skipped > 0) parts.push(this.dim(`${s.skipped} skipped`));
    if (s.errors > 0) parts.push(this.red(`${s.errors} errors`));
    if (s.unclassified > 0) parts.push(this.yellow(`${s.unclassified} unclassified`));
    console.log(`  └─ ${parts.join(' · ')} ${this.dim(`(${elapsed}s)`)}`);
  }

  async initialize() {
    console.log('🚀 Initializing Acad Drive Master...');
    await this.initializeFirebase();
    await this.loadCourseNumbers();
    await this.loadNicknames();
    await this.loadSources();
    console.log(`✅ Loaded ${this.courseData.codes.size} courses, ${this.courseData.abbreviations.size} abbreviations, ${this.nicknames.size} nicknames`);
  }

  async initializeFirebase() {
    if (this.db) return;
    const serviceAccount = JSON.parse(await fs.readFile(this.config.serviceAccountPath, 'utf8'));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    this.db = admin.firestore();
    console.log('✅ Firebase initialized');
    await this.loadDuplicateCourses();
    await this.loadCourseAliases();
  }

  async initializeR2() {
    if (this.s3) return;
    this.s3 = new S3Client({
      endpoint: this.config.r2.endpoint,
      credentials: {
        accessKeyId: this.config.r2.accessKeyId,
        secretAccessKey: this.config.r2.secretAccessKey
      },
      region: 'auto'
    });
    console.log('✅ R2 initialized');
  }

  async initializeGoogleDrive() {
    if (this.drive) return;
    const credentials = this.loadGDriveCredentials();
    const credType = credentials.web || credentials.installed;
    const { client_secret, client_id, redirect_uris } = credType;
    const oAuth2Client = new google.auth.OAuth2(client_id, client_secret, redirect_uris[0]);

    if (fsSync.existsSync(this.config.tokenPath)) {
      const token = JSON.parse(await fs.readFile(this.config.tokenPath, 'utf8'));
      oAuth2Client.setCredentials(token);
    } else {
      await this.getGDriveAccessToken(oAuth2Client);
    }

    this.drive = google.drive({ version: 'v3', auth: oAuth2Client });
    console.log('✅ Google Drive initialized');
  }

  loadGDriveCredentials() {
    const clientId = process.env.GOOGLE_DRIVE_CLIENT_ID;
    const clientSecret = process.env.GOOGLE_DRIVE_CLIENT_SECRET;
    const redirectUri = process.env.GOOGLE_DRIVE_REDIRECT_URI || 'urn:ietf:wg:oauth:2.0:oob';

    if (!clientId || !clientSecret) {
      throw new Error('Google Drive credentials not found in .env file');
    }

    return {
      web: {
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uris: [redirectUri]
      }
    };
  }

  async getGDriveAccessToken(oAuth2Client) {
    const authUrl = oAuth2Client.generateAuthUrl({ access_type: 'offline', scope: this.SCOPES });
    console.log('Authorize this app by visiting:', authUrl);

    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const code = await new Promise(resolve => rl.question('Enter the code: ', resolve));
    rl.close();

    const { tokens } = await oAuth2Client.getToken(code);
    oAuth2Client.setCredentials(tokens);
    await fs.writeFile(this.config.tokenPath, JSON.stringify(tokens));
    console.log('Token stored');
  }

  async loadCourseNumbers() {
    const snapshot = await this.db.collection('campuses/hyderabad/courses_master').get();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const code = (data.course_code || '').trim();
      const name = (data.title || '').trim();
      if (!code || !name) continue;

      this.courseData.codes.set(code.toUpperCase(), { code, name });
      this.courseData.names.set(name.toUpperCase(), { code, name });

      const abbrev = this.generateAbbreviation(name);
      if (abbrev.length >= 2) {
        this.courseData.abbreviations.set(abbrev.toUpperCase(), { code, name });
      }
    }

    // Initialize Fuse.js for fuzzy course name matching
    const courseList = Array.from(this.courseData.names.values()).map(d => ({
      code: d.code,
      name: d.name
    }));
    this.courseFuse = new Fuse(courseList, {
      keys: ['name'],
      threshold: 0.2,
      minMatchCharLength: 5,
      ignoreLocation: true,
      includeScore: true,
      findAllMatches: false,
      distance: 50
    });
  }

  generateAbbreviation(name) {
    const stopWords = new Set(['and', 'of', 'the', 'in', 'for', 'to', 'a', 'an', '&']);
    const words = name.split(/\s+/).filter(w => !stopWords.has(w.toLowerCase()));
    return words.map(w => w[0]).join('').toUpperCase();
  }

  async loadDuplicateCourses() {
    try {
      const doc = await this.db.collection('reference').doc('duplicate_courses').get();
      if (doc.exists) {
        this.duplicateCourses = doc.data().codeMap || {};
        console.log(`✅ Loaded ${Object.keys(this.duplicateCourses).length} duplicate course mappings from Firebase`);
      }
    } catch (err) {
      console.log(`⚠️  Could not load duplicate courses from Firebase: ${err.message}`);
      this.duplicateCourses = {};
    }
  }

  async loadCourseAliases() {
    try {
      const doc = await this.db.collection('reference').doc('course_aliases').get();
      if (doc.exists) {
        this.courseAliases = doc.data().aliasMap || {};
        console.log(`✅ Loaded ${Object.keys(this.courseAliases).length} course aliases from Firebase`);
      }
    } catch (err) {
      console.log(`⚠️  Could not load course aliases from Firebase: ${err.message}`);
      this.courseAliases = {};
    }
  }

  async loadNicknames() {
    try {
      const content = await fs.readFile(this.config.nicknamesFile, 'utf8');
      const data = JSON.parse(content);
      // nicknames.json format:
      // - Simple: { "disco": "CS F222" }
      // - Ambiguous: { "fm": [{ "course": "ME F212", "context": ["mech", "fluid"] }, ...] }
      const nicknameList = [];
      for (const [nickname, value] of Object.entries(data)) {
        const upperNick = nickname.toUpperCase();
        if (typeof value === 'string') {
          // Simple nickname -> single course
          this.nicknames.set(upperNick, value);
          nicknameList.push({ nickname: upperNick, code: value });
        } else if (Array.isArray(value)) {
          // Ambiguous nickname -> array of {course, context}
          // Store as array for context-aware resolution
          this.nicknames.set(upperNick, value);
          // Add each possibility to Fuse list
          for (const opt of value) {
            nicknameList.push({ nickname: upperNick, code: opt.course, context: opt.context });
          }
        }
      }
      // Initialize Fuse.js for very strict nickname matching (1 char tolerance)
      this.nicknameFuse = new Fuse(nicknameList, {
        keys: ['nickname'],
        threshold: 0.15,       // Very strict - allows ~1 char difference for short words
        minMatchCharLength: 3,
        includeScore: true
      });
    } catch {
      // File doesn't exist, use empty map
      this.nicknames = new Map();
      this.nicknameFuse = null;
    }
  }

  // The drive registry lives in Firestore (admin-only), not a JSON file, so
  // approving a submission in the app is all it takes to get a drive synced.
  async loadSources() {
    const snapshot = await this.db.collection('acad_drives_sources').get();
    for (const doc of snapshot.docs) {
      const s = doc.data();
      if (!s.name || s.disabled) continue;
      this.credits[s.name] = {
        name: s.name,
        properties: { drive_link: s.driveLink || 'NA', contributor: s.contributor || 'Unknown' },
        courseCode: s.courseCode || null,
      };
    }
  }

  static sourceDocId(name) {
    return name.replace(/\//g, '-').trim();
  }

  // One-shot seed from the old credits.json. Delete this command once run.
  async importSources(file, dryRun) {
    const data = JSON.parse(await fs.readFile(file, 'utf8'));
    const entries = Object.entries(data);
    console.log(`\n${dryRun ? '[DRY RUN] ' : ''}Importing ${entries.length} drive sources from ${file}`);
    let batch = this.db.batch();
    let n = 0;
    for (const [name, d] of entries) {
      const doc = {
        name,
        driveLink: d.properties?.drive_link || 'NA',
        contributor: d.properties?.contributor || 'Unknown',
        addedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      const exists = this.credits[name] ? 'update' : 'add';
      console.log(`  ${exists.padEnd(6)} ${name}  ←  ${doc.driveLink}  (${doc.contributor})`);
      if (dryRun) continue;
      batch.set(this.db.collection('acad_drives_sources').doc(AcadDriveMaster.sourceDocId(name)), doc, { merge: true });
      if (++n % 450 === 0) { await batch.commit(); batch = this.db.batch(); }
    }
    if (!dryRun) await batch.commit();
    console.log(dryRun ? '\nRe-run with --apply to write.' : `\n✓ Wrote ${entries.length} sources`);
  }

  // One-shot: uploads used to write one doc per code in a file's equivalence
  // cluster, each carrying the whole cluster in course_codes, so a course page
  // listed every file up to 8 times. Keeps the copy whose storagePath is the
  // object in R2 and deletes the rest. Delete this command once run.
  async collapseCopies(dryRun) {
    await this.initializeR2();
    const r2Keys = new Set();
    let token;
    do {
      const res = await this.s3.send(new ListObjectsV2Command({
        Bucket: this.config.r2.bucketName, MaxKeys: 1000, ContinuationToken: token,
      }));
      for (const o of res.Contents || []) r2Keys.add(o.Key);
      token = res.NextContinuationToken;
    } while (token);

    const snapshot = await this.db.collection('acad_drives_files').get();
    const groups = new Map();
    for (const doc of snapshot.docs) {
      const d = doc.data();
      const key = d.driveFileId || d.localFileId;
      if (!key) continue;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(doc);
    }

    const urlKey = (url) => decodeURIComponent((url || '').replace(/^https?:\/\/[^/]+\//, ''));
    const ops = [];
    let noObject = 0;
    for (const docs of groups.values()) {
      if (docs.length < 2) continue;
      const keeper = docs.find(d => r2Keys.has(d.data().storagePath))
        || docs.find(d => r2Keys.has(urlKey(d.data().url)));
      if (!keeper) { noObject++; continue; }
      const codes = [...new Set(docs.flatMap(d => d.data().course_codes || []))];
      const k = keeper.data();
      const update = { course_codes: codes };
      if (!r2Keys.has(k.storagePath)) update.storagePath = urlKey(k.url);
      ops.push({ keeper, update, drop: docs.filter(d => d !== keeper) });
    }

    const dropped = ops.reduce((n, o) => n + o.drop.length, 0);
    console.log(`\n${dryRun ? '[DRY RUN] ' : ''}${snapshot.size} docs, ${groups.size} files, ${r2Keys.size} R2 objects`);
    console.log(`Collapse ${ops.length} files: keep 1 doc each, delete ${dropped} copies.`);
    console.log(`Skipped ${noObject} files with no copy pointing at an R2 object.`);
    for (const { keeper, update, drop } of ops.slice(0, 5)) {
      console.log(`  keep ${keeper.id} ${keeper.data().storagePath}  codes=${update.course_codes.length}  drop ${drop.length}`);
    }
    if (dryRun) { console.log('\nRe-run with --apply to write.'); return; }

    let batch = this.db.batch();
    let n = 0;
    const add = async (fn) => { fn(batch); if (++n % 450 === 0) { await batch.commit(); batch = this.db.batch(); } };
    for (const { keeper, update, drop } of ops) {
      await add(b => b.update(keeper.ref, update));
      for (const d of drop) await add(b => b.delete(d.ref));
    }
    await batch.commit();
    console.log(`✓ Kept ${ops.length}, deleted ${dropped}`);
  }

  // Saved Moodle pages from "CMS/LMS Rips" folders: announcement bodies and
  // link stubs (median 327 bytes), not course material. HTML elsewhere is kept.
  isMoodleStub(filePath) {
    return /\.html?$/i.test(filePath) && /\b(cms|lms)[ _]*rips\b/i.test(filePath);
  }

  sanitizePath(str) {
    return str.replace(/[^\w\-\.]/g, '_').replace(/\.{2,}/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
  }

  findCourseMatches(text, fullPath = '') {
    // Returns array of { code, score } where lower score = better match
    // Score tiers: 0 = exact course code, 0.005 = exact name, 0.008 = alias,
    //   0.01 = nickname, 0.02 = abbreviation, 0.1+ = fuzzy nickname,
    //   0.15+ = Jaccard/Dice name match, 0.2+ = Fuse fuzzy name
    const matches = new Map(); // code -> score
    const preSplit = text.replace(/([a-z]{3,})([A-Z])/g, '$1 $2');
    // ":" and "," too, so "GS F221: Business Communications" still finds its code.
    const normalized = preSplit.toUpperCase().replace(/[_\-\.\(\)\[\]\+\{\}:,;]/g, ' ');
    const words = normalized.split(/\s+/).filter(w => w.length > 0);
    const rawWords = preSplit.replace(/[_\-\.\(\)\[\]\+\{\}:,;]/g, ' ').split(/\s+/).filter(w => w.length > 0);
    const fullPathNorm = fullPath.toUpperCase().replace(/[_\-\.\(\)\[\]\+\{\}\/\\:,;]/g, ' ');

    // Pre-compute context signals for this text + path
    const examContext = this.isExamContext(words);
    const deptPrefixes = this.extractDeptPrefixes(fullPathNorm);

    // Check course codes (e.g., CS F222, CSF222) - highest priority (score = 0)
    for (const [code, data] of this.courseData.codes) {
      const codeNorm = code.replace(/\s+/g, '');
      const codeSpaced = code;
      const boundaryCheck = (text, target) => {
        const idx = text.indexOf(target);
        if (idx === -1) return false;
        const atStart = idx === 0 || /\s/.test(text[idx - 1]);
        const atEnd = idx + target.length >= text.length || /\s/.test(text[idx + target.length]);
        return atStart && atEnd;
      };
      if (boundaryCheck(normalized, codeNorm) || boundaryCheck(normalized, codeSpaced)) {
        matches.set(data.code, 0);
      }
    }

    // Check exact course name match with word boundaries (score = 0.005)
    for (const [name, data] of this.courseData.names) {
      const nameNorm = name.replace(/[_\-\.\(\)\[\]\+\{\}]/g, ' ').replace(/\s+/g, ' ').trim();
      const escapedName = nameNorm.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const wordBoundaryRegex = new RegExp(`(^|\\s)${escapedName}(\\s|$)`);
      if (wordBoundaryRegex.test(normalized)) {
        if (!matches.has(data.code) || matches.get(data.code) > 0.005) {
          matches.set(data.code, 0.005);
        }
      }
    }

    // Check course aliases from Firebase (score = 0.008)
    for (const [alias, codes] of Object.entries(this.courseAliases)) {
      if (alias.length < 3) continue;
      const aliasUpper = alias.toUpperCase();
      const escapedAlias = aliasUpper.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const aliasRegex = new RegExp(`(^|\\s)${escapedAlias}(\\s|$)`);
      if (aliasRegex.test(normalized)) {
        for (const code of codes) {
          if (!matches.has(code) || matches.get(code) > 0.008) {
            matches.set(code, 0.008);
          }
        }
      }
    }

    // Check multi-word nicknames — more specific than single-word, so score better (0.009)
    for (let i = 0; i < words.length - 1; i++) {
      for (let len = 2; len <= Math.min(6, words.length - i); len++) {
        const phrase = words.slice(i, i + len).join(' ');
        if (!this.nicknames.has(phrase)) continue;
        const nicknameValue = this.nicknames.get(phrase);
        if (typeof nicknameValue === 'string') {
          if (!matches.has(nicknameValue) || matches.get(nicknameValue) > 0.009) {
            matches.set(nicknameValue, 0.009);
          }
        } else if (Array.isArray(nicknameValue)) {
          const resolved = this.resolveAmbiguousNickname(nicknameValue, fullPathNorm);
          if (resolved && (!matches.has(resolved) || matches.get(resolved) > 0.009)) {
            matches.set(resolved, 0.009);
          }
        }
      }
    }

    // Check nicknames — skip tokens that are exam terms to avoid
    // "MSE paper.pdf" matching ME F213 instead of staying with folder context
    for (let wi = 0; wi < words.length; wi++) {
      const word = words[wi];
      if (this.examTerms.has(word)) continue;

      // Try exact match, then try combining with next word if it's a single digit
      // e.g. "QM" + "1" → "QM1", "M" + "3" → "M3"
      let nicknameValue = this.nicknames.get(word);
      let usedCombo = false;
      if (!nicknameValue && wi + 1 < words.length) {
        const next = words[wi + 1];
        // Combine with single digit: "QM" + "1" → "QM1"
        if (/^\d$/.test(next)) {
          nicknameValue = this.nicknames.get(word + next);
          if (nicknameValue) usedCombo = true;
        }
        // Combine with roman numeral: "MATH" + "III" → "MATH3", "M" + "II" → "M2"
        if (!nicknameValue && /^[IVX]+$/.test(next)) {
          const arabic = { 'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5 }[next];
          if (arabic) {
            nicknameValue = this.nicknames.get(word + arabic);
            if (nicknameValue) usedCombo = true;
          }
        }
      }

      if (nicknameValue) {
        if (typeof nicknameValue === 'string') {
          if (!matches.has(nicknameValue)) {
            matches.set(nicknameValue, 0.01);
          }
        } else if (Array.isArray(nicknameValue)) {
          const resolved = this.resolveAmbiguousNickname(nicknameValue, fullPathNorm);
          if (resolved && !matches.has(resolved)) {
            matches.set(resolved, 0.01);
          }
        }
        if (usedCombo) wi++;
        continue;
      }

      // Fuzzy nickname match — also block exam terms
      const blockedFuzzyWords = new Set([
        'COMP', 'FILE', 'DATA', 'INFO', 'TEMP', 'TEST', 'COPY', 'MAIN',
        'PART', 'UNIT', 'MISC', 'THE', 'FOR', 'ALL', 'AND', 'NOT', 'NEW',
        'OLD', 'SET', 'GET', 'NET', 'POP', 'TOP', 'HOW', 'LOW', 'RUN',
        'END', 'OUT', 'KEY', 'ART', 'ACT', 'AGE', 'USE', 'WAR', 'LAW',
        'OUR', 'GRAPH', 'OVERVIEW', 'BOOK', 'CHAPTER', 'CASE', 'FULL',
        'OPEN', 'BLOG', 'WEEK', 'TYPE', 'LINK', 'FORM', 'CODE', 'STEP',
      ]);
      if (this.nicknameFuse && word.length >= 4 && /^[A-Z]+$/.test(word)
          && !blockedFuzzyWords.has(word) && !this.examTerms.has(word)) {
        const fuseResults = this.nicknameFuse.search(word);
        for (const result of fuseResults) {
          if (result.score < 0.1 && result.item.nickname[0] === word[0]) {
            const code = result.item.code;
            const score = 0.1 + result.score;
            if (!matches.has(code) || matches.get(code) > score) {
              matches.set(code, score);
            }
          }
        }
      }
    }

    // Check if any known nickname appears as a prefix of a compound word
    // e.g. "DSAmidsemSlides" → "DSA" + "midsem" — boundary confirmed by case change
    // Requires a case or digit boundary in the original text at the split point
    for (let wi = 0; wi < words.length; wi++) {
      const word = words[wi];
      if (word.length <= 3) continue;
      const raw = rawWords[wi] || '';
      for (const [nick, nicknameValue] of this.nicknames) {
        const minNickLen = /\d/.test(nick) ? 2 : 3;
        if (nick.length < minNickLen || nick.length >= word.length) continue;
        if (!word.startsWith(nick)) continue;
        const remainder = word.slice(nick.length);
        if (remainder.length < 3) continue;
        // Verify a real boundary exists in the original text at the split point
        if (raw.length > nick.length) {
          const charBefore = raw[nick.length - 1];
          const charAfter = raw[nick.length];
          const hasBoundary = (charBefore !== charAfter.toUpperCase() || charBefore !== charBefore.toLowerCase())
            && (/[A-Z]/.test(charBefore) && /[a-z]/.test(charAfter)
                || /[a-z]/.test(charBefore) && /[A-Z]/.test(charAfter)
                || /\d/.test(charBefore) || /\d/.test(charAfter));
          if (!hasBoundary) continue;
        }
        const code = typeof nicknameValue === 'string' ? nicknameValue : null;
        if (code && (!matches.has(code) || matches.get(code) > 0.01)) {
          matches.set(code, 0.01);
        }
      }
    }

    // Check auto-generated abbreviations — also blocked by exam terms
    for (const [abbrev, data] of this.courseData.abbreviations) {
      if (abbrev.length >= 3 && this.matchAbbreviation(normalized, abbrev)) {
        if (!matches.has(data.code) || matches.get(data.code) > 0.02) {
          matches.set(data.code, 0.02);
        }
      }
    }

    // Jaccard + Dice course name matching (score = 0.15 + penalty)
    // Pre-filter with Jaccard on word sets, then rank with Dice on character bigrams
    const nameStopWords = new Set(['AND', 'OF', 'THE', 'IN', 'FOR', 'TO', 'A', 'AN', '&',
      ...this.examTerms]);
    const contentWords = words.filter(w => w.length >= 3 && /^[A-Z]+$/.test(w) && !nameStopWords.has(w));
    if (contentWords.length >= 2) {
      const searchText = contentWords.join(' ');
      for (const [name, data] of this.courseData.names) {
        if (matches.has(data.code) && matches.get(data.code) <= 0.01) continue;
        const nameNorm = name.replace(/[_\-\.\(\)\[\]\+\{\}&]/g, ' ').replace(/\s+/g, ' ').trim();
        const jaccard = this.jaccardSimilarity(searchText, nameNorm);
        if (jaccard >= 0.35) {
          const dice = this.diceScore(searchText, nameNorm);
          if (dice >= 0.4) {
            const score = 0.15 + (1 - dice) * 0.1;
            if (!matches.has(data.code) || matches.get(data.code) > score) {
              matches.set(data.code, score);
            }
          }
        }
      }
    }

    // Fuse.js fuzzy matching as final fallback (score = 0.2 + fuse score)
    const fuseStopWords = new Set(['MECH', 'MINOR', 'MAJOR', 'PART', 'DRIVE',
      ...this.examTerms]);
    const meaningfulWords = words.filter(w => w.length >= 5 && /^[A-Z]+$/.test(w) && !fuseStopWords.has(w));
    if (meaningfulWords.length >= 2 && this.courseFuse) {
      const searchText = meaningfulWords.join(' ');
      const fuseResults = this.courseFuse.search(searchText);
      for (const result of fuseResults) {
        if (result.score < 0.1) {
          const code = result.item.code;
          const score = 0.2 + result.score;
          if (!matches.has(code) || matches.get(code) > score) {
            matches.set(code, score);
          }
        }
      }
    }

    // Department context scoring — boost matches whose department aligns with
    // the path, penalize mismatches (only for fuzzy/nickname/abbreviation tiers)
    if (deptPrefixes.size > 0) {
      for (const [code, score] of matches) {
        if (score <= 0.005) continue; // don't touch exact code or exact name matches
        const matchesDept = [...deptPrefixes].some(prefix => code.startsWith(prefix));
        if (matchesDept) {
          matches.set(code, score * 0.8); // boost: 20% lower score
        } else if (score >= 0.01) {
          matches.set(code, score * 1.5); // penalize: 50% higher score
        }
      }
    }

    // Exam context penalty — if the filename has exam keywords alongside an
    // alias/nickname/abbreviation match, demote it so inherited folder matches win
    if (examContext) {
      for (const [code, score] of matches) {
        if (score >= 0.008 && score <= 0.03) {
          matches.set(code, score + 0.05);
        }
      }
    }

    return Array.from(matches.entries()).map(([code, score]) => ({ code, score }));
  }

  resolveAmbiguousNickname(options, fullPathNorm) {
    // options: [{ course: "ME F212", context: ["mech", "fluid"] }, ...]
    // Returns the course code with most context matches, or first option if no context found
    let bestMatch = null;
    let bestScore = -1;

    for (const opt of options) {
      let contextScore = 0;
      for (const hint of opt.context || []) {
        if (fullPathNorm.includes(hint.toUpperCase())) {
          contextScore++;
        }
      }
      if (contextScore > bestScore) {
        bestScore = contextScore;
        bestMatch = opt.course;
      }
    }

    // If no context clues found (bestScore = 0), return first option as default
    return bestMatch || (options[0] && options[0].course);
  }

  getBestMatches(scoredMatches) {
    // Returns only the best-scoring matches (all tied for lowest score)
    if (scoredMatches.length === 0) return [];

    const bestScore = Math.min(...scoredMatches.map(m => m.score));
    const bestMatches = scoredMatches.filter(m => m.score === bestScore).map(m => m.code);

    // Expand duplicates for best matches (they all get same score)
    return this.expandDuplicates(bestMatches);
  }

  extractDeptPrefixes(fullPathNorm) {
    // Extract department code prefixes from path context
    const prefixes = new Set();
    const pathWords = fullPathNorm.split(/\s+/);
    for (const word of pathWords) {
      const deptPrefixes = this.deptKeywords[word];
      if (deptPrefixes) {
        for (const p of deptPrefixes) prefixes.add(p);
      }
    }
    return prefixes;
  }

  isExamContext(words) {
    // Returns true if the text contains exam-related keywords suggesting
    // abbreviations like MSE/ESE are exam labels, not course names
    return words.some(w => this.examTerms.has(w));
  }

  simpleStem(word) {
    if (word.length > 4 && word.endsWith('IES')) return word.slice(0, -3) + 'Y';
    if (word.length > 3 && word.endsWith('ES')) return word.slice(0, -2);
    if (word.length > 3 && word.endsWith('S') && !word.endsWith('SS')) return word.slice(0, -1);
    return word;
  }

  jaccardSimilarity(a, b) {
    const stem = w => this.simpleStem(w);
    const setA = new Set(a.toUpperCase().split(/\s+/).filter(w => w.length > 0).map(stem));
    const setB = new Set(b.toUpperCase().split(/\s+/).filter(w => w.length > 0).map(stem));
    const intersection = new Set([...setA].filter(x => setB.has(x)));
    const union = new Set([...setA, ...setB]);
    return union.size === 0 ? 0 : intersection.size / union.size;
  }

  diceScore(a, b) {
    return stringSimilarity.compareTwoStrings(a.toLowerCase(), b.toLowerCase());
  }

  matchAbbreviation(text, abbrev) {
    // Skip common academic terms that are also abbreviations
    const blockedAbbrevs = new Set([
      'SEM', 'EVEN', 'ODD', 'MID', 'END', 'LAB', 'TUT', 'LEC', 'PYQ',
      'PDF', 'IMG', 'DOC', 'PPT', 'ZIP', 'RAR', 'RUN', 'LOG',
      'DES', 'CMD', 'APP', 'SRC', 'LIB', 'BIN', 'OBJ', 'OUT', 'EXE', 'BAT',
      'HLP', 'DAT', 'CFG', 'DLL', 'SYS', 'TMP', 'LOP', 'NET',
    ]);
    if (blockedAbbrevs.has(abbrev)) {
      return false;
    }

    // Also block exam terms from matching as abbreviations
    if (this.examTerms.has(abbrev)) {
      return false;
    }

    const words = text.split(/\s+/);
    for (const word of words) {
      // Exact match only for abbreviations
      if (word === abbrev) {
        return true;
      }
    }
    return false;
  }

  expandDuplicates(courseCodes) {
    const expanded = new Set(courseCodes);
    for (const code of courseCodes) {
      if (this.duplicateCourses[code]) {
        this.duplicateCourses[code].forEach(c => expanded.add(c));
      }
    }
    return Array.from(expanded);
  }

  async purgeFirebase(dryRun = false) {
    await this.initializeFirebase();
    console.log(`\n🗑️  ${dryRun ? '[DRY RUN] ' : ''}Purging Firebase acad_drives_files collection...`);

    const snapshot = await this.db.collection('acad_drives_files').get();
    const total = snapshot.size;

    if (total === 0) {
      console.log('📭 No documents to delete');
      return;
    }

    console.log(`📊 Found ${total} documents`);

    if (!dryRun) {
      const confirmed = await this.confirm(`Delete ${total} documents?`);
      if (!confirmed) {
        console.log('❌ Cancelled');
        return;
      }
    }

    const batchSize = 500;
    let deleted = 0;

    while (true) {
      const batch = await this.db.collection('acad_drives_files').limit(batchSize).get();
      if (batch.empty) break;

      if (dryRun) {
        deleted += batch.size;
        console.log(`  Would delete ${batch.size} documents`);
        break;
      }

      const writeBatch = this.db.batch();
      batch.docs.forEach(doc => writeBatch.delete(doc.ref));
      await writeBatch.commit();
      deleted += batch.size;
      console.log(`  Deleted ${deleted}/${total}`);
    }

    console.log(`✅ ${dryRun ? 'Would delete' : 'Deleted'} ${deleted} documents`);
  }

  async purgeR2(dryRun = false) {
    await this.initializeR2();
    console.log(`\n🗑️  ${dryRun ? '[DRY RUN] ' : ''}Purging R2 bucket...`);

    const objects = [];
    let token = null;

    do {
      const params = { Bucket: this.config.r2.bucketName, MaxKeys: 1000 };
      if (token) params.ContinuationToken = token;
      const response = await this.s3.send(new ListObjectsV2Command(params));
      if (response.Contents) objects.push(...response.Contents);
      token = response.NextContinuationToken;
    } while (token);

    console.log(`📊 Found ${objects.length} objects`);

    if (objects.length === 0) {
      console.log('📭 Bucket is empty');
      return;
    }

    if (!dryRun) {
      const confirmed = await this.confirm(`Delete ${objects.length} objects?`);
      if (!confirmed) {
        console.log('❌ Cancelled');
        return;
      }
    }

    for (let i = 0; i < objects.length; i += 1000) {
      const batch = objects.slice(i, i + 1000);
      if (dryRun) {
        console.log(`  Would delete batch of ${batch.length} objects`);
        continue;
      }

      await this.s3.send(new DeleteObjectsCommand({
        Bucket: this.config.r2.bucketName,
        Delete: { Objects: batch.map(o => ({ Key: o.Key })) }
      }));
      console.log(`  Deleted ${Math.min(i + 1000, objects.length)}/${objects.length}`);
    }

    console.log(`✅ ${dryRun ? 'Would delete' : 'Deleted'} ${objects.length} objects`);
  }

  async purgeJunk(dryRun = false) {
    await this.initializeFirebase();
    await this.initializeR2();
    console.log(`\n🗑️  ${dryRun ? '[DRY RUN] ' : ''}Purging junk files (build artifacts, bytecode, etc.)...`);

    const snapshot = await this.db.collection('acad_drives_files').get();
    console.log(`📊 Scanning ${snapshot.size} files...`);

    const junkDocs = [];
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const name = data.name || '';
      const ext = path.extname(name).toLowerCase();
      const folder = (data.path || '').toLowerCase().split('/').slice(0, -1)
        .find(f => this.junkFolders.has(f));
      if (folder) {
        junkDocs.push({ doc, data, ext: `${folder}/` });
      } else if (this.isMoodleStub(data.path || name)) {
        junkDocs.push({ doc, data, ext: 'moodle .html' });
      } else if (this.ignoredExtensions.has(ext)) {
        junkDocs.push({ doc, data, ext });
      }
    }

    if (junkDocs.length === 0) {
      console.log('✅ No junk files found');
      return;
    }

    const extCounts = {};
    for (const { ext } of junkDocs) {
      extCounts[ext] = (extCounts[ext] || 0) + 1;
    }
    console.log(`\n🔍 Found ${junkDocs.length} junk files:`);
    for (const [ext, count] of Object.entries(extCounts).sort((a, b) => b[1] - a[1])) {
      console.log(`  ${ext}: ${count}`);
    }

    if (dryRun) {
      for (const { data, ext } of junkDocs) {
        console.log(`  ${ext} ${data.driveName}/${data.path || data.name}`);
      }
      console.log(`\n🔍 Dry run — no files deleted`);
      return;
    }

    const confirmed = await this.confirm(`Delete ${junkDocs.length} junk files from R2 + Firebase?`);
    if (!confirmed) {
      console.log('❌ Cancelled');
      return;
    }

    let deleted = 0;
    let r2Deleted = 0;
    let errors = 0;

    for (const { doc, data } of junkDocs) {
      try {
        if (data.storagePath) {
          await this.s3.send(new DeleteObjectCommand({
            Bucket: this.config.r2.bucketName,
            Key: data.storagePath,
          }));
          r2Deleted++;
        }
        await doc.ref.delete();
        deleted++;
        if (deleted % 100 === 0) console.log(`  ${deleted}/${junkDocs.length} deleted`);
      } catch (e) {
        errors++;
        console.error(`  ❌ ${data.name}: ${e.message}`);
      }
    }

    console.log(`\n✅ Deleted ${deleted} Firestore docs, ${r2Deleted} R2 objects${errors > 0 ? `, ${errors} errors` : ''}`);
  }

  async uploadFromDrives(dryRun = false) {
    await this.initializeFirebase();
    await this.initializeR2();

    let hasGoogleDrive = false;

    const driveEntries = Object.entries(this.credits);
    const mode = dryRun ? this.yellow('[DRY RUN]') : '';
    console.log(`\n${this.bold('📤 Upload')} ${mode} ${driveEntries.length} drives · concurrency: ${this.config.driveConcurrency} drives × ${this.config.concurrency} files`);
    console.log(this.dim('─'.repeat(60)));

    const needsDrive = driveEntries.some(([, d]) => {
      const link = d.properties?.drive_link;
      return link && link !== 'NA';
    });
    if (needsDrive) {
      await this.initializeGoogleDrive();
    }

    let driveIndex = 0;
    const driveTasks = driveEntries.map(([driveName, driveData]) => async () => {
      const idx = ++driveIndex;
      const driveLink = driveData.properties?.drive_link;
      const contributor = driveData.properties?.contributor || 'Unknown';
      this.initDriveStats(driveName);

      const label = driveLink && driveLink !== 'NA'
        ? (driveLink.includes('/file/d/') ? '📄' : '📁')
        : '📂';
      console.log(`\n${label} ${this.bold(driveName)} ${this.dim(`(${idx}/${driveEntries.length})`)} ${this.dim(`by ${contributor}`)}`);

      const driveNameMatches = driveData.courseCode
        ? [{ code: driveData.courseCode, score: 0 }]
        : this.findCourseMatches(driveName, driveName);

      if (driveLink && driveLink !== 'NA') {
        try {
          const { id: driveId, isFile } = this.extractDriveId(driveLink);
          if (isFile) {
            await this.processSingleDriveFile(driveId, driveName, contributor, dryRun);
          } else {
            await this.processDriveFolder(driveId, driveName, contributor, '', dryRun, driveNameMatches);
          }
        } catch (error) {
          console.error(`  ${this.red('✗')} ${error.message}`);
          this.stats.errors.push({ drive: driveName, error: error.message });
          this.driveStats[driveName].errors++;
        }
      }

      const localDir = path.join(this.config.downloadsDir, driveName);
      try {
        await fs.access(localDir);
        console.log(`  ${this.dim('+ local:')} ${localDir}`);
        await this.processLocalFolder(localDir, driveName, contributor, '', dryRun, driveNameMatches);
      } catch {
        // Directory doesn't exist — skip silently
      }

      this.printDriveSummary(driveName);
    });

    await this.runBatch(driveTasks, this.config.driveConcurrency);

    this.printStats();
  }

  extractDriveId(url) {
    const patterns = [
      /folders\/([a-zA-Z0-9-_]+)/,
      /file\/d\/([a-zA-Z0-9-_]+)/,
      /id=([a-zA-Z0-9-_]+)/,
    ];
    for (const pattern of patterns) {
      const match = url.match(pattern);
      if (match) return { id: match[1], isFile: url.includes('/file/d/') };
    }
    throw new Error(`Invalid drive URL: ${url}`);
  }

  async processDriveFolder(folderId, driveName, contributor, relativePath, dryRun, inheritedMatches = []) {
    const files = [];
    let pageToken;
    do {
      const response = await this.drive.files.list({
        q: `'${folderId}' in parents and trashed = false`,
        fields: 'nextPageToken, files(id, name, mimeType, size)',
        pageSize: 1000,
        pageToken,
      });
      files.push(...(response.data.files || []));
      pageToken = response.data.nextPageToken;
    } while (pageToken);

    // First pass: classify files and recurse into subfolders
    const uploadQueue = [];

    for (const file of files) {
      const filePath = relativePath ? `${relativePath}/${file.name}` : file.name;
      const currentMatches = this.findCourseMatches(file.name, filePath);

      let effectiveMatches;
      let matchSource;

      const inheritedBestScore = inheritedMatches.length > 0
        ? Math.min(...inheritedMatches.map(m => m.score))
        : Infinity;
      const localBestScore = currentMatches.length > 0
        ? Math.min(...currentMatches.map(m => m.score))
        : Infinity;

      if (inheritedMatches.length === 0 && currentMatches.length === 0) {
        effectiveMatches = [];
        matchSource = 'none';
      } else if (localBestScore < inheritedBestScore) {
        effectiveMatches = currentMatches;
        matchSource = 'local';
      } else if (localBestScore === inheritedBestScore && currentMatches.length > 0) {
        const existingCodes = new Set(inheritedMatches.map(m => m.code));
        effectiveMatches = [...inheritedMatches];
        for (const m of currentMatches) {
          if (!existingCodes.has(m.code)) effectiveMatches.push(m);
        }
        matchSource = 'merged';
      } else {
        effectiveMatches = inheritedMatches;
        matchSource = 'inherited';
      }

      if (file.mimeType === 'application/vnd.google-apps.folder') {
        if (this.ignoredFolders.has(file.name.toLowerCase())) {
          if (this.verbose) console.log(`  ${this.dim('⏭ skip folder:')} ${file.name}`);
          continue;
        }
        const folderMatches = localBestScore < inheritedBestScore ? currentMatches
          : localBestScore === inheritedBestScore && currentMatches.length > 0
            ? effectiveMatches : effectiveMatches;
        await this.processDriveFolder(file.id, driveName, contributor, filePath, dryRun, folderMatches);
        continue;
      }

      const ext = path.extname(file.name).toLowerCase();
      const baseName = file.name.toLowerCase();
      if (this.ignoredExtensions.has(ext) || this.ignoredFiles.has(baseName) || baseName.startsWith('._')
          || this.isMoodleStub(filePath)) {
        this.stats.skipped++;
        continue;
      }

      if (matchSource === 'inherited' && effectiveMatches.length > 0) {
        const bestInherited = Math.min(...effectiveMatches.map(m => m.score));
        if (bestInherited >= 0.1 && this.nonAcademicExtensions.has(ext)) {
          effectiveMatches = [];
          matchSource = 'none (dropped weak inheritance for non-academic file)';
        }
      }

      this.stats.processed++;
      if (this.driveStats[driveName]) this.driveStats[driveName].processed++;

      const bestCodes = this.getBestMatches(effectiveMatches);
      if (bestCodes.length === 0) {
        bestCodes.push('unclassified');
        if (this.driveStats[driveName]) this.driveStats[driveName].unclassified++;
      }

      const bestScore = effectiveMatches.length > 0 ? Math.min(...effectiveMatches.map(m => m.score)) : null;

      if (dryRun) {
        const isUnclassified = bestCodes[0] === 'unclassified';
        const scoreStr = bestScore !== null ? this.dim(` (${bestScore.toFixed(3)}, ${matchSource})`) : '';
        // Always show unclassified; show classified only in verbose
        if (isUnclassified || this.verbose) {
          const codeStr = isUnclassified ? this.yellow('unclassified') : bestCodes.join(', ');
          console.log(`  ${isUnclassified ? '?' : '·'} ${file.name} → ${codeStr}${scoreStr}`);
          if (this.verbose) {
            if (currentMatches.length > 0) {
              console.log(`    ${this.dim(`↳ name: [${currentMatches.map(m => `${m.code}:${m.score.toFixed(3)}`).join(', ')}]`)}`);
            } else if (inheritedMatches.length > 0) {
              console.log(`    ${this.dim(`↳ inherited: [${inheritedMatches.map(m => `${m.code}:${m.score.toFixed(3)}`).join(', ')}]`)}`);
            }
          }
        }
        continue;
      }

      uploadQueue.push({ file, filePath, bestCodes, relativePath });
    }

    // Second pass: upload files concurrently
    if (uploadQueue.length > 0) {
      const tasks = uploadQueue.map(({ file, filePath, bestCodes, relativePath: relPath }) => () =>
        this._uploadDriveFile(file, filePath, bestCodes, driveName, contributor, relPath)
      );
      await this.runBatch(tasks, this.config.concurrency);
    }
  }

  async _uploadDriveFile(file, filePath, bestCodes, driveName, contributor, relativePath) {
    const ds = this.driveStats[driveName];
    try {
      const existsResult = await this.checkFileExists(file.id);

      if (existsResult.inFirebase && existsResult.inR2) {
        this.stats.skipped++;
        if (ds) ds.skipped++;
        if (this.verbose) console.log(`  ${this.dim('· skip')} ${file.name}`);
        return;
      } else if (existsResult.inFirebase || existsResult.inR2) {
        if (this.verbose) console.log(`  ${this.yellow('⟳')} ${file.name} ${this.dim('(partial, re-uploading)')}`);
        await this.cleanupPartialUpload(file.id, existsResult);
      }

      const localPath = await this.downloadFile(file.id, file.name, file.mimeType);
      let uploadPath = localPath;

      const fileStats = await fs.stat(localPath);
      if (fileStats.size >= this.config.compressionThreshold) {
        uploadPath = await this.compressFile(localPath) || localPath;
      }

      const primaryCode = bestCodes[0];
      const r2Key = this.buildR2Path(primaryCode, driveName, relativePath, path.basename(uploadPath));
      const publicUrl = await this.uploadToR2(uploadPath, r2Key);

      await this.createFirebaseEntry({
        name: file.name,
        path: filePath,
        storagePath: r2Key,
        firebaseUrl: publicUrl,
        courseCode: primaryCode,
        courseCodes: bestCodes,
        driveName,
        contributor,
        mimeType: file.mimeType,
        size: fileStats.size,
        driveFileId: file.id
      });

      await fs.unlink(localPath).catch(() => {});
      if (uploadPath !== localPath) await fs.unlink(uploadPath).catch(() => {});

      this.stats.uploaded++;
      if (ds) ds.uploaded++;
      if (this.verbose) console.log(`  ${this.green('✓')} ${file.name} → ${bestCodes[0]}`);
    } catch (error) {
      const errDetail = this._formatError(error);
      if (this._isRetryable(error) && !file._retried) {
        file._retried = true;
        const delay = 2000 + Math.random() * 3000;
        if (this.verbose) console.log(`  ${this.yellow('⟳')} ${file.name}: ${errDetail}, retrying in ${(delay/1000).toFixed(1)}s...`);
        await new Promise(r => setTimeout(r, delay));
        return this._uploadDriveFile(file, filePath, bestCodes, driveName, contributor, relativePath);
      }
      if (ds) ds.errors++;
      console.error(`  ${this.red('✗')} ${file.name}: ${errDetail}`);
      this.stats.errors.push({ file: file.name, error: errDetail });
    }
  }

  _isRetryable(error) {
    const code = error.code || error.status || error?.response?.status;
    if (code === 429 || code === 403 || code === 500 || code === 503) return true;
    const msg = (error.message || '').toLowerCase();
    return msg.includes('rate') || msg.includes('quota') || msg.includes('unknown')
        || msg.includes('timeout') || msg.includes('econnreset') || msg.includes('socket');
  }

  async processSingleDriveFile(fileId, driveName, contributor, dryRun) {
    const meta = await this.drive.files.get({
      fileId,
      fields: 'id, name, mimeType, size',
    });
    const file = meta.data;
    const filePath = file.name;
    const matches = this.findCourseMatches(file.name, filePath);
    const bestCodes = this.getBestMatches(matches);
    if (bestCodes.length === 0) bestCodes.push('unclassified');

    const bestScore = matches.length > 0 ? Math.min(...matches.map(m => m.score)) : null;
    const isUnclassified = bestCodes[0] === 'unclassified';
    const codeStr = isUnclassified ? this.yellow('unclassified') : bestCodes.join(', ');
    console.log(`  · ${file.name} → ${codeStr}${bestScore !== null ? this.dim(` (${bestScore.toFixed(3)})`) : ''}`);

    this.stats.processed++;
    if (this.driveStats[driveName]) {
      this.driveStats[driveName].processed++;
      if (isUnclassified) this.driveStats[driveName].unclassified++;
    }

    if (dryRun) return;

    try {
      const existsResult = await this.checkFileExists(file.id);
      if (existsResult.inFirebase && existsResult.inR2) {
        console.log(`    ⏭️  Already uploaded, skipping`);
        this.stats.skipped++;
        return;
      } else if (existsResult.inFirebase || existsResult.inR2) {
        console.log(`    ⚠️  Partial upload detected, cleaning up...`);
        await this.cleanupPartialUpload(file.id, existsResult);
      }

      const localPath = await this.downloadFile(file.id, file.name, file.mimeType);
      let uploadPath = localPath;

      const fileStats = await fs.stat(localPath);
      if (fileStats.size >= this.config.compressionThreshold) {
        uploadPath = await this.compressFile(localPath) || localPath;
      }

      const primaryCode = bestCodes[0];
      const r2Key = this.buildR2Path(primaryCode, driveName, '', path.basename(uploadPath));
      const publicUrl = await this.uploadToR2(uploadPath, r2Key);

      await this.createFirebaseEntry({
        name: file.name,
        path: filePath,
        storagePath: r2Key,
        firebaseUrl: publicUrl,
        courseCode: primaryCode,
        courseCodes: bestCodes,
        driveName,
        contributor,
        mimeType: file.mimeType,
        size: fileStats.size,
        driveFileId: file.id
      });

      await fs.unlink(localPath).catch(() => {});
      if (uploadPath !== localPath) await fs.unlink(uploadPath).catch(() => {});

      this.stats.uploaded++;
    } catch (error) {
      console.error(`    ❌ ${error.message}`);
      this.stats.errors.push({ file: file.name, error: error.message });
    }
  }

  async processLocalFolder(localDir, driveName, contributor, relativePath, dryRun, inheritedMatches = []) {
    let entries;
    try {
      entries = await fs.readdir(localDir, { withFileTypes: true });
    } catch (err) {
      console.error(`    ❌ Cannot read directory ${localDir}: ${err.message}`);
      return;
    }

    const uploadQueue = [];

    for (const entry of entries) {
      const filePath = relativePath ? `${relativePath}/${entry.name}` : entry.name;
      const fullPath = path.join(localDir, entry.name);
      const currentMatches = this.findCourseMatches(entry.name, filePath);

      const inheritedBestScore = inheritedMatches.length > 0
        ? Math.min(...inheritedMatches.map(m => m.score))
        : Infinity;
      const localBestScore = currentMatches.length > 0
        ? Math.min(...currentMatches.map(m => m.score))
        : Infinity;

      let effectiveMatches;
      let matchSource;

      if (inheritedMatches.length === 0 && currentMatches.length === 0) {
        effectiveMatches = [];
        matchSource = 'none';
      } else if (localBestScore < inheritedBestScore) {
        effectiveMatches = currentMatches;
        matchSource = 'local';
      } else if (localBestScore === inheritedBestScore && currentMatches.length > 0) {
        const existingCodes = new Set(inheritedMatches.map(m => m.code));
        effectiveMatches = [...inheritedMatches];
        for (const m of currentMatches) {
          if (!existingCodes.has(m.code)) effectiveMatches.push(m);
        }
        matchSource = 'merged';
      } else {
        effectiveMatches = inheritedMatches;
        matchSource = 'inherited';
      }

      if (entry.isDirectory()) {
        if (this.ignoredFolders.has(entry.name.toLowerCase())) {
          if (this.verbose) console.log(`  ${this.dim('⏭ skip folder:')} ${entry.name}`);
          continue;
        }
        const folderMatches = localBestScore < inheritedBestScore ? currentMatches
          : localBestScore === inheritedBestScore && currentMatches.length > 0
            ? effectiveMatches : effectiveMatches;
        await this.processLocalFolder(fullPath, driveName, contributor, filePath, dryRun, folderMatches);
        continue;
      }

      const ext = path.extname(entry.name).toLowerCase();
      const baseName = entry.name.toLowerCase();
      if (this.ignoredExtensions.has(ext) || this.ignoredFiles.has(baseName) || baseName.startsWith('._')
          || this.isMoodleStub(filePath)) {
        this.stats.skipped++;
        continue;
      }

      if (matchSource === 'inherited' && effectiveMatches.length > 0) {
        const bestInherited = Math.min(...effectiveMatches.map(m => m.score));
        if (bestInherited >= 0.1 && this.nonAcademicExtensions.has(ext)) {
          effectiveMatches = [];
          matchSource = 'none (dropped weak inheritance for non-academic file)';
        }
      }

      this.stats.processed++;
      if (this.driveStats[driveName]) this.driveStats[driveName].processed++;

      const bestCodes = this.getBestMatches(effectiveMatches);
      if (bestCodes.length === 0) {
        bestCodes.push('unclassified');
        if (this.driveStats[driveName]) this.driveStats[driveName].unclassified++;
      }

      const bestScore = effectiveMatches.length > 0 ? Math.min(...effectiveMatches.map(m => m.score)) : null;

      if (dryRun) {
        const isUnclassified = bestCodes[0] === 'unclassified';
        const scoreStr = bestScore !== null ? this.dim(` (${bestScore.toFixed(3)}, ${matchSource})`) : '';
        if (isUnclassified || this.verbose) {
          const codeStr = isUnclassified ? this.yellow('unclassified') : bestCodes.join(', ');
          console.log(`  ${isUnclassified ? '?' : '·'} ${entry.name} → ${codeStr}${scoreStr}`);
          if (this.verbose) {
            if (currentMatches.length > 0) {
              console.log(`    ${this.dim(`↳ name: [${currentMatches.map(m => `${m.code}:${m.score.toFixed(3)}`).join(', ')}]`)}`);
            } else if (inheritedMatches.length > 0) {
              console.log(`    ${this.dim(`↳ inherited: [${inheritedMatches.map(m => `${m.code}:${m.score.toFixed(3)}`).join(', ')}]`)}`);
            }
          }
        }
        continue;
      }

      uploadQueue.push({ entry, fullPath, filePath, bestCodes, ext, relativePath });
    }

    if (uploadQueue.length > 0) {
      const tasks = uploadQueue.map(({ entry, fullPath, filePath, bestCodes, ext, relativePath: relPath }) => () =>
        this._uploadLocalFile(entry, fullPath, filePath, bestCodes, ext, driveName, contributor, relPath)
      );
      await this.runBatch(tasks, this.config.concurrency);
    }
  }

  async _uploadLocalFile(entry, fullPath, filePath, bestCodes, ext, driveName, contributor, relativePath) {
    const ds = this.driveStats[driveName];
    try {
      const fileContent = await fs.readFile(fullPath);
      const localFileId = crypto.createHash('md5').update(fileContent).digest('hex');

      const existsResult = await this.checkLocalFileExists(localFileId);
      if (existsResult.inFirebase && existsResult.inR2) {
        this.stats.skipped++;
        if (ds) ds.skipped++;
        if (this.verbose) console.log(`  ${this.dim('· skip')} ${entry.name}`);
        return;
      } else if (existsResult.inFirebase || existsResult.inR2) {
        if (this.verbose) console.log(`  ${this.yellow('⟳')} ${entry.name} ${this.dim('(partial, re-uploading)')}`);
        await this.cleanupPartialUpload(null, existsResult);
      }

      let uploadPath = fullPath;
      const fileStats = await fs.stat(fullPath);
      if (fileStats.size >= this.config.compressionThreshold) {
        uploadPath = await this.compressFile(fullPath) || fullPath;
      }

      const mimeType = this.getMimeTypeFromExtension(ext);
      const primaryCode = bestCodes[0];
      const r2Key = this.buildR2Path(primaryCode, driveName, relativePath, path.basename(uploadPath));
      const publicUrl = await this.uploadToR2(uploadPath, r2Key);

      await this.createFirebaseEntry({
        name: entry.name,
        path: filePath,
        storagePath: r2Key,
        firebaseUrl: publicUrl,
        courseCode: primaryCode,
        courseCodes: bestCodes,
        driveName,
        contributor,
        mimeType,
        size: fileStats.size,
        localFileId
      });

      if (uploadPath !== fullPath) await fs.unlink(uploadPath).catch(() => {});

      this.stats.uploaded++;
      if (ds) ds.uploaded++;
      if (this.verbose) console.log(`  ${this.green('✓')} ${entry.name} → ${bestCodes[0]}`);
    } catch (error) {
      const errDetail = this._formatError(error);
      if (this._isRetryable(error) && !entry._retried) {
        entry._retried = true;
        const delay = 2000 + Math.random() * 3000;
        if (this.verbose) console.log(`  ${this.yellow('⟳')} ${entry.name}: ${errDetail}, retrying...`);
        await new Promise(r => setTimeout(r, delay));
        return this._uploadLocalFile(entry, fullPath, filePath, bestCodes, ext, driveName, contributor, relativePath);
      }
      if (ds) ds.errors++;
      console.error(`  ${this.red('✗')} ${entry.name}: ${errDetail}`);
      this.stats.errors.push({ file: entry.name, error: errDetail });
    }
  }

  _formatError(error) {
    // Dig through nested error structures to find the real message
    const parts = [];
    if (error.name && error.name !== 'Error') parts.push(error.name);
    if (error.code) parts.push(`code=${error.code}`);
    if (error.status) parts.push(`status=${error.status}`);
    if (error.$metadata?.httpStatusCode) parts.push(`http=${error.$metadata.httpStatusCode}`);
    if (error.message && error.message !== 'UnknownError') parts.push(error.message);
    if (error.cause) parts.push(`cause: ${error.cause.message || error.cause}`);
    if (parts.length === 0) {
      // Last resort — serialize the whole thing
      try { return JSON.stringify(error).substring(0, 200); } catch { return String(error); }
    }
    return parts.join(' · ');
  }

  async checkLocalFileExists(localFileId) {
    const result = { inFirebase: false, inR2: false, firebaseDocs: [], r2Key: null };

    const snapshot = await this.db.collection('acad_drives_files')
      .where('localFileId', '==', localFileId)
      .get();

    if (!snapshot.empty) {
      result.inFirebase = true;
      snapshot.forEach(doc => {
        result.firebaseDocs.push({ id: doc.id, data: doc.data() });
      });
      result.r2Key = result.firebaseDocs[0].data.storagePath;
    }

    if (result.r2Key) {
      try {
        await this.s3.send(new HeadObjectCommand({
          Bucket: this.config.r2.bucketName,
          Key: result.r2Key
        }));
        result.inR2 = true;
      } catch (err) {
        if (err.name !== 'NotFound' && err.$metadata?.httpStatusCode !== 404) {
          throw err;
        }
        result.inR2 = false;
      }
    }

    return result;
  }

  getMimeTypeFromExtension(ext) {
    const map = {
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.ppt': 'application/vnd.ms-powerpoint',
      '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.txt': 'text/plain',
      '.csv': 'text/csv',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.svg': 'image/svg+xml',
      '.mp4': 'video/mp4',
      '.mkv': 'video/x-matroska',
      '.mov': 'video/quicktime',
      '.avi': 'video/x-msvideo',
      '.mp3': 'audio/mpeg',
      '.zip': 'application/zip',
      '.rar': 'application/vnd.rar',
      '.7z': 'application/x-7z-compressed',
      '.html': 'text/html',
      '.md': 'text/markdown',
    };
    return map[ext.toLowerCase()] || 'application/octet-stream';
  }

  buildR2Path(courseCode, driveName, relativePath, fileName) {
    const sanitizedCode = this.sanitizePath(courseCode);
    const sanitizedDrive = this.sanitizePath(driveName);
    const sanitizedPath = relativePath ? this.sanitizePath(relativePath.replace(/\//g, '_')) : '';
    const sanitizedFile = this.sanitizePath(fileName);

    const parts = [this.config.basePath, sanitizedCode, sanitizedDrive];
    if (sanitizedPath) parts.push(sanitizedPath);
    parts.push(sanitizedFile);

    return parts.join('/');
  }

  async downloadFile(fileId, fileName, mimeType) {
    await fs.mkdir(this.config.downloadsDir, { recursive: true });
    const safeName = path.basename(fileName).replace(/[^a-zA-Z0-9._-]/g, '_');
    const localPath = path.join(this.config.downloadsDir, `${Date.now()}_${safeName}`);

    if (mimeType.includes('google-apps')) {
      const exportMime = this.getExportMimeType(mimeType);

      // Skip unsupported Google Apps types (shortcuts, forms, sites, etc.)
      if (!exportMime) {
        throw new Error(`Unsupported Google Apps type: ${mimeType} (skipping)`);
      }

      const ext = this.getExportExtension(exportMime);
      const exportPath = localPath.replace(/\.[^.]+$/, '') + ext;

      const response = await this.drive.files.export(
        { fileId, mimeType: exportMime },
        { responseType: 'stream' }
      );

      await this.streamToFile(response.data, exportPath);
      return exportPath;
    }

    const response = await this.drive.files.get(
      { fileId, alt: 'media' },
      { responseType: 'stream' }
    );

    await this.streamToFile(response.data, localPath);
    return localPath;
  }

  getExportMimeType(googleMime) {
    const map = {
      'application/vnd.google-apps.document': 'application/pdf',
      'application/vnd.google-apps.spreadsheet': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.google-apps.presentation': 'application/pdf',
      'application/vnd.google-apps.drawing': 'image/png'
    };
    return map[googleMime] || null; // Return null for unsupported types
  }

  getExportExtension(mimeType) {
    const map = {
      'application/pdf': '.pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
      'image/png': '.png'
    };
    return map[mimeType] || '.pdf';
  }

  streamToFile(stream, filePath) {
    return new Promise((resolve, reject) => {
      const writeStream = fsSync.createWriteStream(filePath);
      stream.pipe(writeStream);
      writeStream.on('finish', resolve);
      writeStream.on('error', reject);
      stream.on('error', reject);
    });
  }

  async compressFile(filePath) {
    const ext = path.extname(filePath).toLowerCase();

    if (ext === '.pdf') {
      return this.compressPdf(filePath);
    }

    if (['.mp4', '.mkv', '.mov', '.avi'].includes(ext)) {
      return this.compressVideo(filePath);
    }

    return null;
  }

  async compressPdf(filePath) {
    const outputPath = filePath.replace('.pdf', '_compressed.pdf');
    try {
      await execFileAsync('qpdf', ['--optimize-images', '--compress-streams=y', filePath, outputPath]);
      const original = (await fs.stat(filePath)).size;
      const compressed = (await fs.stat(outputPath)).size;
      console.log(`    🗜️  PDF: ${this.formatBytes(original)} → ${this.formatBytes(compressed)}`);
      return outputPath;
    } catch {
      return null;
    }
  }

  async compressVideo(filePath) {
    const outputPath = filePath.replace(/\.[^.]+$/, '_compressed.mp4');
    try {
      await execFileAsync('ffmpeg', ['-i', filePath, '-c:v', 'libx264', '-preset', 'medium', '-crf', '28', '-c:a', 'aac', '-b:a', '128k', '-y', outputPath], {
        maxBuffer: 100 * 1024 * 1024
      });
      const original = (await fs.stat(filePath)).size;
      const compressed = (await fs.stat(outputPath)).size;
      console.log(`    🗜️  Video: ${this.formatBytes(original)} → ${this.formatBytes(compressed)}`);
      return outputPath;
    } catch {
      return null;
    }
  }

  async uploadToR2(localPath, r2Key) {
    const fileContent = await fs.readFile(localPath);
    await this.s3.send(new PutObjectCommand({
      Bucket: this.config.r2.bucketName,
      Key: r2Key,
      Body: fileContent,
      ACL: 'public-read'
    }));

    const base = this.config.r2.customDomain || this.config.r2.publicUrl;
    return `${base}/${r2Key}`;
  }

  async createFirebaseEntry(data) {
    const fileId = crypto.createHash('md5').update(`${data.courseCode}_${data.driveName}_${data.path}`).digest('hex');
    const courseData = this.courseData.codes.get(data.courseCode.toUpperCase());
    const courseName = courseData ? courseData.name : data.courseCode;

    const entry = {
      name: data.name,
      path: data.path,
      storagePath: data.storagePath,
      url: data.firebaseUrl,
      course_codes: data.courseCodes || [data.courseCode],
      courseName: courseName,
      driveName: data.driveName,
      contributor: data.contributor,
      mimeType: data.mimeType,
      size: data.size,
      ...classifyResource(data.name, data.path),
      uploadedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    if (data.driveFileId) {
      entry.driveFileId = data.driveFileId;
      entry.folderMetadata = { drive_link: `https://drive.google.com/file/d/${data.driveFileId}/view` };
    } else if (data.localFileId) {
      entry.localFileId = data.localFileId;
      entry.folderMetadata = { source: 'local' };
    }

    await this.db.collection('acad_drives_files').doc(fileId).set(entry, { merge: true });
  }

  async checkFileExists(driveFileId) {
    // Check if file exists in Firebase and R2
    // Returns { inFirebase: bool, inR2: bool, firebaseDocs: [], r2Key: string }
    const result = { inFirebase: false, inR2: false, firebaseDocs: [], r2Key: null };

    // Check Firebase by driveFileId
    const snapshot = await this.db.collection('acad_drives_files')
      .where('driveFileId', '==', driveFileId)
      .get();

    if (!snapshot.empty) {
      result.inFirebase = true;
      snapshot.forEach(doc => {
        result.firebaseDocs.push({ id: doc.id, data: doc.data() });
      });
      // Get the R2 key from the first doc to check R2
      result.r2Key = result.firebaseDocs[0].data.storagePath;
    }

    // Check R2 if we have a key
    if (result.r2Key) {
      try {
        await this.s3.send(new HeadObjectCommand({
          Bucket: this.config.r2.bucketName,
          Key: result.r2Key
        }));
        result.inR2 = true;
      } catch (err) {
        if (err.name !== 'NotFound' && err.$metadata?.httpStatusCode !== 404) {
          throw err; // Re-throw unexpected errors
        }
        result.inR2 = false;
      }
    }

    return result;
  }

  async cleanupPartialUpload(driveFileId, existsResult) {
    // Remove partial entries from Firebase and/or R2
    const { inFirebase, inR2, firebaseDocs, r2Key } = existsResult;

    if (inFirebase) {
      for (const doc of firebaseDocs) {
        await this.db.collection('acad_drives_files').doc(doc.id).delete();
        console.log(`    🗑️  Deleted Firebase entry: ${doc.id}`);
      }
    }

    if (inR2 && r2Key) {
      await this.s3.send(new DeleteObjectCommand({
        Bucket: this.config.r2.bucketName,
        Key: r2Key
      }));
      console.log(`    🗑️  Deleted R2 object: ${r2Key}`);
    }
  }

  async confirm(message) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answer = await new Promise(resolve => rl.question(`⚠️  ${message} Type YES to confirm: `, resolve));
    rl.close();
    return answer === 'YES';
  }

  formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  printStats() {
    console.log(`\n${this.bold('📊 Summary')}`);
    console.log(this.dim('═'.repeat(50)));

    const pad = (label, val) => `  ${label.padEnd(14)} ${val}`;
    console.log(pad('Processed', this.stats.processed));
    console.log(pad('Uploaded', this.stats.uploaded > 0 ? this.green(this.stats.uploaded) : '0'));
    console.log(pad('Skipped', this.stats.skipped > 0 ? this.dim(this.stats.skipped) : '0'));
    console.log(pad('Errors', this.stats.errors.length > 0 ? this.red(this.stats.errors.length) : '0'));

    // Per-drive breakdown for drives with activity
    const activeDrives = Object.entries(this.driveStats).filter(([, s]) => s.processed > 0);
    if (activeDrives.length > 0) {
      console.log(`\n${this.bold('Per-drive breakdown')}`);
      console.log(this.dim('─'.repeat(50)));

      // Sort: errors first, then by file count descending
      activeDrives.sort((a, b) => (b[1].errors - a[1].errors) || (b[1].processed - a[1].processed));

      for (const [name, s] of activeDrives) {
        const parts = [`${s.processed} files`];
        if (s.uploaded > 0) parts.push(this.green(`${s.uploaded}↑`));
        if (s.skipped > 0) parts.push(this.dim(`${s.skipped}⏭`));
        if (s.errors > 0) parts.push(this.red(`${s.errors}✗`));
        if (s.unclassified > 0) parts.push(this.yellow(`${s.unclassified}?`));
        const elapsed = ((Date.now() - s.startTime) / 1000).toFixed(1);
        console.log(`  ${name.substring(0, 40).padEnd(42)} ${parts.join(' · ')} ${this.dim(`${elapsed}s`)}`);
      }
    }

    if (this.stats.errors.length > 0) {
      console.log(`\n${this.bold(this.red('Errors'))}`);
      console.log(this.dim('─'.repeat(50)));
      this.stats.errors.slice(0, 15).forEach(e =>
        console.log(`  ${this.red('✗')} ${(e.file || e.drive)}: ${this.dim(e.error)}`)
      );
      if (this.stats.errors.length > 15) {
        console.log(this.dim(`  ... and ${this.stats.errors.length - 15} more`));
      }
    }

    console.log('');
  }

  async rescore(dryRun = false, filterCodes = null) {
    await this.initializeFirebase();
    await this.initializeR2();

    const codeFilter = filterCodes
      ? new Set(filterCodes.split(',').map(c => c.trim()))
      : null;

    const label = codeFilter
      ? `files in ${[...codeFilter].join(', ')}`
      : 'all files';
    console.log(`\n🔄 ${dryRun ? '[DRY RUN] ' : ''}Rescoring ${label}...`);

    let snapshot;
    if (codeFilter) {
      const codeArray = [...codeFilter];
      const batches = [];
      for (let i = 0; i < codeArray.length; i += 30) {
        const chunk = codeArray.slice(i, i + 30);
        const snap = await this.db.collection('acad_drives_files')
          .where('course_codes', 'array-contains-any', chunk).get();
        batches.push(...snap.docs);
      }
      snapshot = { docs: batches, size: batches.length };
    } else {
      snapshot = await this.db.collection('acad_drives_files').get();
    }
    const total = snapshot.size;
    console.log(`📊 Found ${total} files to check\n`);

    let rescored = 0;
    let unchanged = 0;
    let errors = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const currentCodes = data.course_codes || data.courseCodes || [];
      const currentCode = currentCodes[0] || 'unclassified';
      const filePath = data.path || data.name;
      const driveName = data.driveName || '';

      const ext = path.extname(data.name || '').toLowerCase();
      if (this.ignoredExtensions.has(ext)) {
        unchanged++;
        continue;
      }

      // Seed with drive name context — cap scores at nickname tier (0.01)
      // because a drive can contain multiple courses' materials
      const segments = filePath.split('/');
      let inheritedMatches = driveName
        ? this.findCourseMatches(driveName, driveName).map(m => ({ ...m, score: Math.max(m.score, 0.01) }))
        : [];

      for (let i = 0; i < segments.length; i++) {
        const segment = segments[i];
        const partialPath = segments.slice(0, i + 1).join('/');
        const localMatches = this.findCourseMatches(segment, partialPath);

        const inheritedBestScore = inheritedMatches.length > 0
          ? Math.min(...inheritedMatches.map(m => m.score))
          : Infinity;
        const localBestScore = localMatches.length > 0
          ? Math.min(...localMatches.map(m => m.score))
          : Infinity;

        if (localBestScore < inheritedBestScore) {
          inheritedMatches = localMatches;
        } else if (localBestScore === inheritedBestScore && localMatches.length > 0) {
          // Merge same-score matches — both folder signals are equally valid
          const existingCodes = new Set(inheritedMatches.map(m => m.code));
          for (const m of localMatches) {
            if (!existingCodes.has(m.code)) inheritedMatches.push(m);
          }
        }
      }

      const bestCodes = this.getBestMatches(inheritedMatches);

      // Skip if no positive match — don't override existing assignment with unclassified
      if (bestCodes.length === 0) {
        unchanged++;
        continue;
      }

      // Don't reclassify an already-assigned file with a low-confidence fuzzy match
      const bestScore = inheritedMatches.length > 0 ? Math.min(...inheritedMatches.map(m => m.score)) : null;
      if (currentCode !== 'unclassified' && bestScore !== null && bestScore > 0.03) {
        unchanged++;
        continue;
      }

      const newCode = bestCodes[0];

      // Check if current code is already correct (including duplicates),
      // or if it matched at the same score tier as the proposed new code
      const currentCodeScore = inheritedMatches.find(m => m.code === currentCode)?.score;
      const currentInDuplicates = bestCodes.includes(currentCode);
      const currentTiedWithBest = currentCodeScore !== undefined && currentCodeScore === bestScore;
      const isAlreadyCorrect = currentInDuplicates || currentTiedWithBest;

      if (!isAlreadyCorrect) {
        rescored++;
        console.log(`  📄 ${data.name}`);
        console.log(`      ${currentCode} → ${bestCodes.join(', ')}${bestScore !== null ? ` (score: ${bestScore.toFixed(3)})` : ''}`);
        console.log(`      drive: ${driveName || '(none)'}`);
        if (data.storagePath) {
          console.log(`      r2: ${data.storagePath}`);
        } else if (filePath !== data.name) {
          console.log(`      path: ${filePath}`);
        }

        if (!dryRun) {
          try {
            // Update Firebase document
            const courseData = this.courseData.codes.get(newCode.toUpperCase());
            const courseName = courseData ? courseData.name : newCode;

            await doc.ref.update({
              course_codes: bestCodes,
              courseName: courseName,
              rescoredAt: admin.firestore.FieldValue.serverTimestamp(),
              previousCourseCode: currentCode
            });

            // Move file in R2 if storage path exists
            if (data.storagePath && data.storagePath.includes(currentCode)) {
              const oldKey = data.storagePath;
              const newKey = data.storagePath.replace(
                new RegExp(`/${this.sanitizePath(currentCode)}/`),
                `/${this.sanitizePath(newCode)}/`
              );

              if (oldKey !== newKey) {
                try {
                  // Copy to new location
                  const { CopyObjectCommand } = require('@aws-sdk/client-s3');
                  await this.s3.send(new CopyObjectCommand({
                    Bucket: this.config.r2.bucketName,
                    CopySource: `${this.config.r2.bucketName}/${oldKey}`,
                    Key: newKey
                  }));

                  // Delete old location
                  const { DeleteObjectCommand } = require('@aws-sdk/client-s3');
                  await this.s3.send(new DeleteObjectCommand({
                    Bucket: this.config.r2.bucketName,
                    Key: oldKey
                  }));

                  // Update storage path in Firebase
                  const base = this.config.r2.customDomain || this.config.r2.publicUrl;
                  await doc.ref.update({
                    storagePath: newKey,
                    url: `${base}/${newKey}`
                  });

                  console.log(`      ✅ Moved in R2`);
                } catch (r2Error) {
                  console.log(`      ⚠️  R2 move failed: ${r2Error.message}`);
                  errors++;
                }
              }
            }
          } catch (error) {
            console.log(`      ❌ Error: ${error.message}`);
            errors++;
          }
        }
      } else {
        unchanged++;
      }
    }

    console.log('\n📊 Rescore Summary');
    console.log('═'.repeat(40));
    console.log(`Total files: ${total}`);
    console.log(`Rescored: ${rescored}`);
    console.log(`Unchanged: ${unchanged}`);
    if (errors > 0) {
      console.log(`Errors: ${errors}`);
    }
    if (dryRun && rescored > 0) {
      console.log(`\nRe-run with --apply to apply changes.`);
    }
  }

  async reallocate(sourcePath, targetCode, dryRun = false) {
    // Reallocate all files matching sourcePath to targetCode
    // sourcePath can be: courseCode, driveName, or path substring
    // Example: reallocate "BITS F444" "GS F223" --apply
    // Example: reallocate "Mech Drive/Huels/Mass Comm" "GS F223"

    await this.initializeFirebase();
    console.log(`\n🔄 ${dryRun ? '[DRY RUN] ' : ''}Reallocating files...`);
    console.log(`Source: "${sourcePath}"`);
    console.log(`Target: "${targetCode}"`);
    console.log('═'.repeat(50));

    // Validate target code exists
    const targetData = this.courseData.codes.get(targetCode.toUpperCase());
    if (!targetData) {
      console.error(`❌ Target course code "${targetCode}" not found in courses_master`);
      return;
    }

    // Get target duplicates for courseCodes array
    const targetCodes = this.expandDuplicates([targetCode]);
    console.log(`Target codes (with duplicates): ${targetCodes.join(', ')}`);

    // Find all files matching sourcePath
    const snapshot = await this.db.collection('acad_drives_files').get();
    const matchingFiles = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const courseCodes = data.course_codes || data.courseCodes || [];
      const driveName = data.driveName || '';
      const filePath = data.path || '';
      const storagePath = data.storagePath || '';

      // Match against course_codes, driveName, path, or storagePath
      const searchFields = [...courseCodes, driveName, filePath, storagePath].join(' ').toLowerCase();
      if (searchFields.includes(sourcePath.toLowerCase())) {
        matchingFiles.push({ id: doc.id, data });
      }
    }

    console.log(`\nFound ${matchingFiles.length} matching files\n`);

    if (matchingFiles.length === 0) {
      console.log('No files to reallocate.');
      return;
    }

    let reallocated = 0;
    let errors = 0;

    for (const file of matchingFiles) {
      const { id, data } = file;
      const fileCodes = data.course_codes || data.courseCodes || [];
      const currentCode = fileCodes[0] || 'unclassified';
      const fileName = data.name;
      const oldStoragePath = data.storagePath;

      // Skip if already in target
      if (targetCodes.includes(currentCode)) {
        console.log(`  ⏭️  ${fileName} - already in ${currentCode}`);
        continue;
      }

      console.log(`  📄 ${fileName}`);
      console.log(`      ${currentCode} → ${targetCode}`);

      if (dryRun) {
        reallocated++;
        continue;
      }

      try {
        // Build new R2 path
        const newStoragePath = oldStoragePath.replace(
          /^tabulr_drives\/[^\/]+\//,
          `tabulr_drives/${this.sanitizePath(targetCode)}/`
        );

        // Move in R2 (copy + delete)
        if (oldStoragePath !== newStoragePath) {
          // Copy to new location
          await this.s3.send(new CopyObjectCommand({
            Bucket: this.config.r2.bucketName,
            CopySource: `${this.config.r2.bucketName}/${oldStoragePath}`,
            Key: newStoragePath
          }));

          // Delete old location
          await this.s3.send(new DeleteObjectCommand({
            Bucket: this.config.r2.bucketName,
            Key: oldStoragePath
          }));

          console.log(`      ✓ R2: ${oldStoragePath} → ${newStoragePath}`);
        }

        // Update Firebase
        const base = this.config.r2.customDomain || this.config.r2.publicUrl;
        const newUrl = `${base}/${newStoragePath}`;

        await this.db.collection('acad_drives_files').doc(id).update({
          course_codes: targetCodes,
          courseName: targetData.name,
          storagePath: newStoragePath,
          url: newUrl,
          reallocatedAt: admin.firestore.FieldValue.serverTimestamp(),
          reallocatedFrom: currentCode
        });

        console.log(`      ✓ Firebase updated`);
        reallocated++;
      } catch (error) {
        console.error(`      ❌ Error: ${error.message}`);
        errors++;
      }
    }

    console.log('\n📊 Reallocate Summary');
    console.log('═'.repeat(40));
    console.log(`Total matched: ${matchingFiles.length}`);
    console.log(`Reallocated: ${reallocated}`);
    if (errors > 0) {
      console.log(`Errors: ${errors}`);
    }
    if (dryRun && reallocated > 0) {
      console.log(`\nRe-run with --apply to apply changes.`);
    }
  }
  _loadDriveLinkMap() {
    const linkMap = {};
    for (const [name, entry] of Object.entries(this.credits)) {
      const link = entry.properties?.drive_link;
      if (link && link !== 'NA') linkMap[name] = link;
    }
    return linkMap;
  }

  async buildIndex(dryRun = false) {
    console.log('\n📇 Building acad_drives_index...');
    console.log('═'.repeat(50));

    await this.initializeFirebase();

    const driveLinkMap = this._loadDriveLinkMap();
    console.log(`Loaded ${Object.keys(driveLinkMap).length} drive links from credits files`);

    const snapshot = await this.db.collection('acad_drives_files').get();
    console.log(`Reading ${snapshot.size} files...`);

    const index = {};

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const courseCodes = data.course_codes || data.courseCodes || [];
      const driveName = data.driveName || 'Unknown';
      const uploadedAt = data.uploadedAt;

      const codes = Array.isArray(courseCodes) && courseCodes.length > 0
        ? courseCodes
        : ['Uncategorized'];

      for (const code of codes) {
        if (!index[code]) {
          index[code] = { fileCount: 0, drives: new Set(), driveLinks: {}, typeCounts: {}, lastUpdated: null };
        }
        index[code].fileCount++;
        const type = data.resource_type || 'other';
        index[code].typeCounts[type] = (index[code].typeCounts[type] || 0) + 1;
        index[code].drives.add(driveName);

        if (driveLinkMap[driveName] && !index[code].driveLinks[driveName]) {
          index[code].driveLinks[driveName] = driveLinkMap[driveName];
        }

        if (uploadedAt) {
          const ts = uploadedAt.toDate ? uploadedAt.toDate() : new Date(uploadedAt);
          if (!index[code].lastUpdated || ts > index[code].lastUpdated) {
            index[code].lastUpdated = ts;
          }
        }
      }
    }

    const codes = Object.keys(index);
    console.log(`Found ${codes.length} unique course codes`);

    if (dryRun) {
      console.log('\n[DRY RUN] Would write index documents:');
      for (const code of codes) {
        const entry = index[code];
        console.log(`  ${code}: ${entry.fileCount} files, ${entry.drives.size} drives, ${JSON.stringify(entry.typeCounts)}`);
      }
      return;
    }

    // Clear existing index
    const existing = await this.db.collection('acad_drives_index').get();
    if (!existing.empty) {
      let batch = this.db.batch();
      let count = 0;
      for (const doc of existing.docs) {
        batch.delete(doc.ref);
        count++;
        if (count % 450 === 0) {
          await batch.commit();
          batch = this.db.batch();
        }
      }
      if (count % 450 !== 0) await batch.commit();
      console.log(`Cleared ${count} existing index docs`);
    }

    // Write new index
    let batch = this.db.batch();
    let written = 0;
    for (const code of codes) {
      const entry = index[code];
      const docId = code.replace(/\s+/g, '_').replace(/\//g, '-');
      const ref = this.db.collection('acad_drives_index').doc(docId);

      const doc = {
        code: code,
        fileCount: entry.fileCount,
        driveCount: entry.drives.size,
        typeCounts: entry.typeCounts,
        lastUpdated: entry.lastUpdated
          ? admin.firestore.Timestamp.fromDate(entry.lastUpdated)
          : null,
      };
      if (Object.keys(entry.driveLinks).length > 0) {
        doc.driveLinks = entry.driveLinks;
      }
      batch.set(ref, doc);

      written++;
      if (written % 450 === 0) {
        await batch.commit();
        console.log(`  Written ${written}/${codes.length}...`);
        batch = this.db.batch();
      }
    }
    if (written % 450 !== 0) await batch.commit();

    console.log(`\n✓ Built index: ${written} course entries`);

    // Upload index as static JSON to R2 for client-side caching
    await this.uploadIndexToR2(index, codes, dryRun);
  }

  async uploadIndexToR2(index, codes, dryRun = false) {
    console.log('\n📦 Uploading index JSON to R2...');
    await this.initializeR2();

    const jsonData = codes.map(code => {
      const entry = index[code];
      const doc = {
        code,
        fileCount: entry.fileCount,
        driveCount: entry.drives.size,
        typeCounts: entry.typeCounts,
        lastUpdated: entry.lastUpdated ? entry.lastUpdated.toISOString() : null,
      };
      if (Object.keys(entry.driveLinks).length > 0) {
        doc.driveLinks = entry.driveLinks;
      }
      return doc;
    });

    const payload = JSON.stringify({ updatedAt: new Date().toISOString(), courses: jsonData });

    if (dryRun) {
      console.log(`[DRY RUN] Would upload acad-drives-index.json (${(payload.length / 1024).toFixed(1)} KB, ${jsonData.length} courses)`);
      return;
    }

    await this.s3.send(new PutObjectCommand({
      Bucket: this.config.r2.bucketName,
      Key: 'tabulr_meta/acad-drives-index.json',
      Body: payload,
      ContentType: 'application/json',
      ACL: 'public-read'
    }));

    const base = this.config.r2.customDomain || this.config.r2.publicUrl;
    console.log(`✓ Uploaded index JSON to ${base}/tabulr_meta/acad-drives-index.json`);
  }

  async copyIndexToR2(dryRun = false) {
    console.log('\n📋 Copying Firestore acad_drives_index → R2 JSON...');
    console.log('═'.repeat(50));

    await this.initializeFirebase();
    await this.initializeR2();

    const snapshot = await this.db.collection('acad_drives_index').get();
    console.log(`Read ${snapshot.size} index documents from Firestore`);

    if (snapshot.empty) {
      console.log('⚠️  Index is empty — nothing to copy');
      return;
    }

    const jsonData = snapshot.docs.map(doc => {
      const data = doc.data();
      const entry = {
        code: data.code || doc.id.replace(/_/g, ' '),
        fileCount: data.fileCount || 0,
        driveCount: data.driveCount || 0,
        typeCounts: data.typeCounts || {},
        lastUpdated: data.lastUpdated?.toDate?.()
          ? data.lastUpdated.toDate().toISOString()
          : null,
      };
      if (data.driveLinks && Object.keys(data.driveLinks).length > 0) {
        entry.driveLinks = data.driveLinks;
      }
      return entry;
    });

    const payload = JSON.stringify({ updatedAt: new Date().toISOString(), courses: jsonData });
    console.log(`Prepared JSON: ${(payload.length / 1024).toFixed(1)} KB, ${jsonData.length} courses`);

    if (dryRun) {
      console.log('[DRY RUN] Would upload to tabulr_meta/acad-drives-index.json');
      return;
    }

    await this.s3.send(new PutObjectCommand({
      Bucket: this.config.r2.bucketName,
      Key: 'tabulr_meta/acad-drives-index.json',
      Body: payload,
      ContentType: 'application/json',
      ACL: 'public-read'
    }));

    const base = this.config.r2.customDomain || this.config.r2.publicUrl;
    console.log(`✅ Uploaded to ${base}/tabulr_meta/acad-drives-index.json`);
  }

  // Backfills resource_type / exam / year on files synced before they existed,
  // or after classify.js changes. Metadata only: nothing moves in R2.
  async reclassify(dryRun) {
    await this.initializeFirebase();
    const snapshot = await this.db.collection('acad_drives_files').get();
    console.log(`\n🏷️  ${dryRun ? '[DRY RUN] ' : ''}Reclassifying ${snapshot.size} files`);
    const counts = {};
    const changes = [];
    for (const doc of snapshot.docs) {
      const d = doc.data();
      const next = classifyResource(d.name || '', d.path || d.name || '');
      counts[next.resource_type] = (counts[next.resource_type] || 0) + 1;
      const same = d.resource_type === next.resource_type && d.exam === next.exam && d.year === next.year;
      if (!same) changes.push({ doc, d, next });
    }
    for (const { d, next } of changes) {
      const tag = [next.resource_type, next.exam, next.year].filter(Boolean).join(' · ');
      console.log(`  ${(d.resource_type || '—').padEnd(11)} → ${tag.padEnd(26)} ${d.driveName}/${d.path}`);
    }
    console.log(`\n${changes.length} of ${snapshot.size} would change. Totals after: ${JSON.stringify(counts)}`);
    if (dryRun) { console.log('Re-run with --apply to write, then build-index.'); return; }

    const del = admin.firestore.FieldValue.delete();
    let batch = this.db.batch();
    let n = 0;
    for (const { doc, next } of changes) {
      batch.update(doc.ref, {
        resource_type: next.resource_type,
        exam: next.exam ?? del,
        year: next.year ?? del,
      });
      if (++n % 450 === 0) { await batch.commit(); batch = this.db.batch(); }
    }
    await batch.commit();
    console.log(`✓ Updated ${n} files`);
  }

  async dedup(dryRun = false) {
    console.log(`\n🔍 ${dryRun ? '[DRY RUN] ' : ''}Scanning for duplicate files in R2...`);
    console.log('═'.repeat(50));

    await this.initializeFirebase();
    await this.initializeR2();

    // 1. List all R2 objects with ETags (content hash for single-part uploads)
    const objects = [];
    let token = null;
    do {
      const params = { Bucket: this.config.r2.bucketName, MaxKeys: 1000 };
      if (token) params.ContinuationToken = token;
      const response = await this.s3.send(new ListObjectsV2Command(params));
      if (response.Contents) objects.push(...response.Contents);
      token = response.NextContinuationToken;
    } while (token);

    console.log(`📊 Found ${objects.length} R2 objects`);

    // Skip metadata files
    const fileObjects = objects.filter(o => !o.Key.startsWith('tabulr_meta/'));

    // 2. Group by ETag (content hash)
    const byEtag = {};
    for (const obj of fileObjects) {
      const etag = obj.ETag?.replace(/"/g, '');
      if (!etag) continue;
      if (!byEtag[etag]) byEtag[etag] = [];
      byEtag[etag].push(obj);
    }

    const duplicateGroups = Object.entries(byEtag).filter(([, objs]) => objs.length > 1);
    const totalDuplicateObjects = duplicateGroups.reduce((sum, [, objs]) => sum + objs.length - 1, 0);
    const duplicateBytes = duplicateGroups.reduce((sum, [, objs]) => {
      return sum + objs.slice(1).reduce((s, o) => s + (o.Size || 0), 0);
    }, 0);

    console.log(`\n📋 Found ${duplicateGroups.length} duplicate groups (${totalDuplicateObjects} redundant copies)`);
    console.log(`💾 Potential savings: ${(duplicateBytes / 1024 / 1024).toFixed(1)} MB`);

    if (duplicateGroups.length === 0) {
      console.log('✅ No duplicates found');
      return;
    }

    // Show top 10 biggest duplicate groups
    const sortedGroups = duplicateGroups
      .map(([etag, objs]) => ({ etag, objs, wastedBytes: objs.slice(1).reduce((s, o) => s + (o.Size || 0), 0) }))
      .sort((a, b) => b.wastedBytes - a.wastedBytes);

    console.log('\nTop duplicate groups:');
    for (const group of sortedGroups.slice(0, 10)) {
      console.log(`  ${group.objs[0].Key} (${group.objs.length} copies, ${(group.wastedBytes / 1024 / 1024).toFixed(1)} MB wasted)`);
      for (const obj of group.objs.slice(1)) {
        console.log(`    dup: ${obj.Key}`);
      }
    }

    if (dryRun) {
      console.log(`\n[DRY RUN] Would remove ${totalDuplicateObjects} duplicate R2 objects and update Firebase paths`);
      return;
    }

    const confirmed = await this.confirm(
      `Remove ${totalDuplicateObjects} duplicate objects (${(duplicateBytes / 1024 / 1024).toFixed(1)} MB) and update Firebase paths?`
    );
    if (!confirmed) {
      console.log('❌ Cancelled');
      return;
    }

    // 3. Load all Firebase file docs for path remapping
    const allDocs = await this.db.collection('acad_drives_files').get();
    const docsByStoragePath = {};
    allDocs.forEach(doc => {
      const sp = doc.data().storagePath;
      if (sp) {
        if (!docsByStoragePath[sp]) docsByStoragePath[sp] = [];
        docsByStoragePath[sp].push(doc);
      }
    });

    const base = this.config.r2.customDomain || this.config.r2.publicUrl;
    let r2Deleted = 0;
    let fbUpdated = 0;
    let errors = 0;

    // 4. For each duplicate group: keep first, remap + delete the rest
    for (const group of sortedGroups) {
      const canonical = group.objs[0];
      const canonicalUrl = `${base}/${canonical.Key}`;
      const duplicates = group.objs.slice(1);

      for (const dup of duplicates) {
        // Update any Firebase docs pointing to this duplicate
        const docsToUpdate = docsByStoragePath[dup.Key] || [];
        for (const doc of docsToUpdate) {
          try {
            await doc.ref.update({
              storagePath: canonical.Key,
              url: canonicalUrl,
            });
            fbUpdated++;
          } catch (err) {
            console.error(`  ❌ Failed to update Firebase doc ${doc.id}: ${err.message}`);
            errors++;
          }
        }

        // Delete the duplicate R2 object
        try {
          await this.s3.send(new DeleteObjectCommand({
            Bucket: this.config.r2.bucketName,
            Key: dup.Key,
          }));
          r2Deleted++;
        } catch (err) {
          console.error(`  ❌ Failed to delete R2 object ${dup.Key}: ${err.message}`);
          errors++;
        }
      }
    }

    console.log(`\n✅ Dedup complete:`);
    console.log(`   R2 objects deleted: ${r2Deleted}`);
    console.log(`   Firebase docs updated: ${fbUpdated}`);
    console.log(`   Saved: ~${(duplicateBytes / 1024 / 1024).toFixed(1)} MB`);
    if (errors > 0) console.log(`   Errors: ${errors}`);
  }
}

async function main() {
  const master = new AcadDriveMaster();
  await master.initialize();

  const args = process.argv.slice(2);
  const command = args[0];
  // Every command is a dry run unless --apply is passed: this is production data.
  const dryRun = !args.includes('--apply');
  if (dryRun && command) console.log('🔎 Dry run — nothing will be written. Pass --apply to write.');

  switch (command) {
    case 'purge-firebase':
      await master.purgeFirebase(dryRun);
      break;

    case 'purge-r2':
      await master.purgeR2(dryRun);
      break;

    case 'purge-all':
      await master.purgeFirebase(dryRun);
      await master.purgeR2(dryRun);
      break;

    case 'upload':
      await master.uploadFromDrives(dryRun);
      await master.buildIndex(dryRun);
      break;

    case 'full-sync':
      await master.purgeFirebase(dryRun);
      await master.purgeR2(dryRun);
      await master.uploadFromDrives(dryRun);
      await master.buildIndex(dryRun);
      break;

    case 'purge-junk':
      await master.purgeJunk(dryRun);
      break;

    case 'rescore': {
      const codesIdx = args.indexOf('--codes');
      const filterCodes = codesIdx !== -1 ? args[codesIdx + 1] : null;
      await master.rescore(dryRun, filterCodes);
      break;
    }

    case 'build-index':
      await master.buildIndex(dryRun);
      break;

    case 'copy-index-r2':
      await master.copyIndexToR2(dryRun);
      break;

    case 'reclassify':
      await master.reclassify(dryRun);
      break;

    case 'import-sources':
      if (!args[1] || args[1].startsWith('--')) {
        console.error('Usage: node acad-drive-master.js import-sources <credits.json> [--apply]');
        process.exit(1);
      }
      await master.importSources(args[1], dryRun);
      break;

    case 'dedup':
      await master.dedup(dryRun);
      break;

    case 'collapse-copies':
      await master.collapseCopies(dryRun);
      break;

    case 'reallocate':
      const source = args[1];
      const target = args[2];
      if (!source || !target) {
        console.error('Usage: node acad-drive-master.js reallocate <source> <target> [--apply]');
        console.error('Example: node acad-drive-master.js reallocate "BITS F444" "GS F223"');
        console.error('Example: node acad-drive-master.js reallocate "Mech Drive/Huels/Mass Comm" "GS F223"');
        process.exit(1);
      }
      await master.reallocate(source, target, dryRun);
      break;

    default:
      console.log(`
🎓 Acad Drive Master Script

Commands:
  purge-firebase    Purge all documents from Firebase acad_drives_files collection
  purge-r2          Purge all objects from Cloudflare R2 bucket
  purge-all         Purge both Firebase and R2
  upload            Download from Google Drive and upload to R2/Firebase
  full-sync         Purge everything, then upload fresh
  purge-junk        Delete build artifacts (.pyc, .o, .dll, etc.) from R2 + Firebase
  rescore           Re-classify all files with updated matching logic
                    --codes "CS F111,CS F222"  Only rescore files in these course codes
  build-index       Build acad_drives_index collection for fast course listing
  copy-index-r2     Copy existing Firestore index to R2 as static JSON
  dedup             Find and remove duplicate files in R2 (by content hash)
  reallocate        Manually move files to a different course code
  reclassify        Backfill resource_type / exam / year from classify.js
  import-sources    One-shot: seed acad_drives_sources from an old credits.json
  collapse-copies   One-shot: merge the per-code copies of each file into one doc

Flags:
  --apply           Actually write. Without it every command is a dry run.
  --verbose         Show per-file detail (skips, uploads, match reasoning)

Examples:
  node acad-drive-master.js upload                 # dry run
  node acad-drive-master.js upload --apply
  node acad-drive-master.js reclassify --apply && node acad-drive-master.js build-index --apply
  node acad-drive-master.js reallocate "Mech Drive/Huels/Mass Comm" "GS F223" --apply

Path Structure:
  R2: tabulr_drives/{course_code}/{drive_name}/{resource_division}/{file}
  Firebase: acad_drives_files collection with course_codes, driveName, contributor fields

Course Matching:
  - Course codes from campuses/hyderabad/courses_master (e.g., CS F211)
  - Course names with 70% fuzzy match (e.g., Data Structures & Algorithms)
  - Auto-generated abbreviations with fuzzy match (e.g., DSA, ToC)
  - Common nicknames from nicknames.json (e.g., disco, lics, oops)
  - Fuzzy matching allows 1-2 character typos in abbreviations
  - Duplicate courses from reference/duplicate_courses are expanded

Compression:
  - Files >= 500MB are compressed before upload
  - PDFs: qpdf optimization
  - Videos: ffmpeg H.264 encoding
  - DOCX: skipped (causes issues)
      `);
  }
}

// A fatal error must fail the process, or a scheduled sync looks green.
main().catch((e) => { console.error(e); process.exit(1); });
