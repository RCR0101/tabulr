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

async function uploadCourseGuide() {
  try {
    console.log('📚 Starting course guide upload...');

    // Read the course guide data
    const dataPath = path.join(__dirname, 'course_guide_data.json');
    if (!fs.existsSync(dataPath)) {
      throw new Error('course_guide_data.json not found');
    }

    const courseGuideData = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
    console.log('📖 Course guide data loaded successfully');

    // Clear existing data
    console.log('🔄 Clearing existing course guide data...');
    const courseGuideRef = db.collection('course_guide');
    const snapshot = await courseGuideRef.get();
    
    const batch = db.batch();
    snapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    if (!snapshot.empty) {
      await batch.commit();
      console.log(`✅ Cleared ${snapshot.size} existing course guide documents`);
    }

    // Upload new data
    console.log('🔄 Uploading new course guide data...');
    const newBatch = db.batch();
    let documentCount = 0;

    // Upload each semester's data as separate documents
    for (const [semesterId, semesterData] of Object.entries(courseGuideData)) {
      console.log(`📝 Processing ${semesterId}...`);

      const docRef = courseGuideRef.doc(semesterId);
      
      // Add metadata to the document
      const documentData = {
        semesterId: semesterId,
        name: semesterId.replace('_', '-').toUpperCase().replace('-', ' '),
        lastUpdated: new Date().toISOString(),
        groups: semesterData.groups
      };

      newBatch.set(docRef, documentData);
      documentCount++;

      // Log the groups being uploaded
      for (const [groupId, groupData] of Object.entries(semesterData.groups)) {
        console.log(`  📋 Group: ${groupId} (${groupData.branches.join(', ')})`);
        console.log(`     📚 Courses: ${groupData.courses.length} courses`);
      }
    }

    // Create a metadata document
    const metadataRef = courseGuideRef.doc('_metadata');
    const metadataData = {
      totalSemesters: Object.keys(courseGuideData).length,
      availableSemesters: Object.keys(courseGuideData),
      lastUpdated: new Date().toISOString(),
      uploadedBy: 'admin_script',
      version: '1.0.0',
      uploadedAt: new Date().toISOString()
    };

    newBatch.set(metadataRef, metadataData);
    documentCount++;

    // Commit the batch
    console.log(`💾 Uploading ${documentCount} documents to Firestore...`);
    await newBatch.commit();

    console.log('✅ Course guide upload completed successfully!');
    console.log(`📊 Statistics:`);
    console.log(`   - Semesters uploaded: ${Object.keys(courseGuideData).length}`);
    console.log(`   - Total documents: ${documentCount}`);
    console.log(`   - Collection: course_guide`);

    // Verify the upload
    console.log('\n🔍 Verifying upload...');
    const docs = await courseGuideRef.get();
    console.log(`✅ Verification: Found ${docs.size} documents in course_guide collection`);

    docs.forEach(doc => {
      if (doc.id === '_metadata') {
        const data = doc.data();
        console.log(`   📋 Metadata: ${data.totalSemesters} semesters, updated ${data.lastUpdated}`);
      } else {
        const data = doc.data();
        console.log(`   📚 ${doc.id}: ${Object.keys(data.groups || {}).length} groups`);
      }
    });

  } catch (error) {
    console.error('❌ Error uploading course guide:', error);
    process.exit(1);
  }
}

// Main execution
async function main() {
  try {
    await uploadCourseGuide();
    console.log('\n🎉 Course guide upload script completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('💥 Fatal error:', error);
    process.exit(1);
  }
}

// Handle script interruption
process.on('SIGINT', () => {
  console.log('\n⚠️ Upload interrupted by user');
  process.exit(1);
});

process.on('SIGTERM', () => {
  console.log('\n⚠️ Upload terminated');
  process.exit(1);
});

// Run the script
main().catch(console.error);