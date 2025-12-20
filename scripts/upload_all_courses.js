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

function parseCsvLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      result.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  
  result.push(current.trim());
  return result;
}

async function uploadAllCourses() {
  try {
    console.log('📚 Starting all courses upload...');

    // Read the courses.txt file
    const dataPath = path.join(__dirname, '..', 'courses.txt');
    if (!fs.existsSync(dataPath)) {
      throw new Error('courses.txt not found');
    }

    const fileContent = fs.readFileSync(dataPath, 'utf8');
    const lines = fileContent.trim().split('\n');
    
    // Skip header line
    const dataLines = lines.slice(1);
    
    console.log('📖 Courses data loaded successfully');
    console.log(`📊 Total courses to process: ${dataLines.length}`);

    // Fetch existing courses to check what needs to be uploaded
    console.log('🔍 Checking existing courses in database...');
    const allCoursesRef = db.collection('all_courses');
    const snapshot = await allCoursesRef.get();
    
    // Create a set of existing course document IDs
    const existingCourseIds = new Set(snapshot.docs.map(doc => doc.id));
    console.log(`📦 Found ${existingCourseIds.size} existing courses in database`);

    // Upload new data in batches (Firestore limit is 500 operations per batch)
    console.log('🔄 Uploading new courses...');
    
    let batchCount = 0;
    let currentBatch = db.batch();
    let operationCount = 0;
    let documentCount = 0;
    let skippedCount = 0;
    
    for (const line of dataLines) {
      if (!line.trim()) continue;
      
      const [course_code, course_title, u, has_asterisk] = parseCsvLine(line);
      
      if (!course_code) {
        console.warn(`⚠️  Skipping invalid line: ${line}`);
        continue;
      }
      
      // Determine type based on has_asterisk
      const type = has_asterisk === 'Yes' ? 'ATC' : 'Normal';
      
      // Use course_code as document ID (remove special characters for safety)
      const docId = course_code.replace(/[^a-zA-Z0-9]/g, '_');
      
      // Skip if course already exists
      if (existingCourseIds.has(docId)) {
        skippedCount++;
        continue;
      }
      
      const docRef = allCoursesRef.doc(docId);
      
      const documentData = {
        course_code: course_code,
        course_title: course_title,
        u: u,
        type: type,
        // Add searchable fields for better querying
        code_lower: course_code.toLowerCase(),
        title_lower: course_title.toLowerCase(),
        lastUpdated: new Date().toISOString()
      };
      
      currentBatch.set(docRef, documentData);
      operationCount++;
      documentCount++;
      
      // Commit batch if we hit the limit
      if (operationCount >= 500) {
        await currentBatch.commit();
        batchCount++;
        console.log(`  ✅ Batch ${batchCount} committed (${operationCount} operations)`);
        currentBatch = db.batch();
        operationCount = 0;
      }
    }
    
    // Commit remaining operations
    if (operationCount > 0) {
      await currentBatch.commit();
      batchCount++;
      console.log(`  ✅ Batch ${batchCount} committed (${operationCount} operations)`);
    }

    // Create metadata document
    const metadataRef = db.collection('metadata').doc('all_courses');
    await metadataRef.set({
      lastUpdated: new Date().toISOString(),
      totalCourses: existingCourseIds.size + documentCount,
      newCoursesAdded: documentCount,
      uploadedBy: 'upload_all_courses.js',
      uploadDate: new Date().toISOString()
    });

    console.log('\n✨ Upload completed successfully!');
    console.log(`📊 New courses uploaded: ${documentCount}`);
    console.log(`⏭️  Existing courses skipped: ${skippedCount}`);
    console.log(`📦 Total courses in database: ${existingCourseIds.size + documentCount}`);
    console.log(`📦 Total batches committed: ${batchCount}`);
    console.log('📝 Metadata document updated');
    
  } catch (error) {
    console.error('❌ Error uploading all courses:', error);
    throw error;
  } finally {
    process.exit();
  }
}

// Run the upload
uploadAllCourses();
