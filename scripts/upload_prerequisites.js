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

async function uploadPrerequisites() {
  try {
    console.log('📚 Starting prerequisites upload...');

    // Read the prereqs.json file
    const dataPath = path.join(__dirname, 'prereqs.json');
    if (!fs.existsSync(dataPath)) {
      throw new Error('prereqs.json not found');
    }

    const fileContent = fs.readFileSync(dataPath, 'utf8');
    const prereqsData = JSON.parse(fileContent);
    
    console.log('📖 Prerequisites data loaded successfully');
    console.log(`📊 Total courses to process: ${prereqsData.length}`);

    // Fetch existing prerequisites to check what needs to be uploaded
    console.log('🔍 Checking existing prerequisites in database...');
    const prereqsRef = db.collection('prerequisites');
    const snapshot = await prereqsRef.get();
    
    // Create a set of existing course document IDs
    const existingCourseIds = new Set(snapshot.docs.map(doc => doc.id));
    console.log(`📦 Found ${existingCourseIds.size} existing prerequisite records in database`);

    // Upload data in batches (Firestore limit is 500 operations per batch)
    console.log('🔄 Uploading prerequisites...');
    
    let batchCount = 0;
    let currentBatch = db.batch();
    let operationCount = 0;
    let documentCount = 0;
    let skippedCount = 0;
    
    for (const course of prereqsData) {
      if (!course.name) {
        console.warn(`⚠️  Skipping invalid entry: ${JSON.stringify(course)}`);
        continue;
      }
      
      // Use course name as document ID (remove special characters for safety)
      const docId = course.name.replace(/[^a-zA-Z0-9]/g, '_');
      
      // Check if course already exists - we'll update instead of skip
      const alreadyExists = existingCourseIds.has(docId);
      if (alreadyExists) {
        skippedCount++;
      }
      
      const docRef = prereqsRef.doc(docId);
      
      const documentData = {
        name: course.name,
        prereqs: course.prereqs || [],
        // Add searchable field for better querying
        name_lower: course.name.toLowerCase(),
        // Extract course code from name (e.g., "BIO F110" from "BIO F110 BIOLOGICAL LABORATORY")
        course_code: course.name.split(' ').slice(0, 2).join(' '),
        course_code_lower: course.name.split(' ').slice(0, 2).join(' ').toLowerCase(),
        has_prerequisites: course.prereqs && course.prereqs.length > 0,
        lastUpdated: new Date().toISOString()
      };
      
      // Add all_one field if it exists
      if (course.all_one) {
        documentData.all_one = course.all_one;
      }
      
      currentBatch.set(docRef, documentData);
      operationCount++;
      if (!alreadyExists) {
        documentCount++;
      }
      
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
    const metadataRef = db.collection('metadata').doc('prerequisites');
    await metadataRef.set({
      lastUpdated: new Date().toISOString(),
      totalCourses: existingCourseIds.size + documentCount,
      coursesWithPrereqs: prereqsData.filter(c => c.prereqs && c.prereqs.length > 0).length,
      newCoursesAdded: documentCount,
      uploadedBy: 'upload_prerequisites.js',
      uploadDate: new Date().toISOString()
    });

    console.log('\n✨ Upload completed successfully!');
    console.log(`📊 New prerequisites uploaded: ${documentCount}`);
    console.log(`🔄 Existing courses updated: ${skippedCount}`);
    console.log(`📦 Total courses in database: ${existingCourseIds.size + documentCount}`);
    console.log(`📦 Total batches committed: ${batchCount}`);
    console.log('📝 Metadata document updated');
    
  } catch (error) {
    console.error('❌ Error uploading prerequisites:', error);
    throw error;
  } finally {
    process.exit();
  }
}

// Run the upload
uploadPrerequisites();
