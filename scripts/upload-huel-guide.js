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

async function uploadHuelGuide() {
  try {
    console.log('🚀 Starting HUEL Guide upload to Firebase...');
    
    // Read the huelGuide.json file
    const huelGuidePath = path.join(__dirname, 'huelGuide.json');
    if (!fs.existsSync(huelGuidePath)) {
      throw new Error('huelGuide.json file not found in scripts directory');
    }
    
    const huelGuideData = JSON.parse(fs.readFileSync(huelGuidePath, 'utf8'));
    console.log(`📋 Found ${huelGuideData.length} HUEL courses to upload`);
    
    // Clear existing huel_guide collection
    console.log('🧹 Clearing existing huel_guide collection...');
    const existingDocs = await db.collection('huel_guide').get();
    const batch = db.batch();
    existingDocs.docs.forEach(doc => batch.delete(doc.ref));
    if (existingDocs.docs.length > 0) {
      await batch.commit();
      console.log(`🗑️ Deleted ${existingDocs.docs.length} existing documents`);
    }
    
    // Upload new data in batches (Firestore batch limit is 500)
    const batchSize = 500;
    let uploadedCount = 0;
    
    for (let i = 0; i < huelGuideData.length; i += batchSize) {
      const batch = db.batch();
      const chunk = huelGuideData.slice(i, i + batchSize);
      
      chunk.forEach((course, index) => {
        const docId = `course_${i + index + 1}`; // course_1, course_2, etc.
        const docRef = db.collection('huel_guide').doc(docId);
        
        batch.set(docRef, {
          course_code: course.course_code,
          course_name: course.course_name,
          created_at: new Date(),
          updated_at: new Date()
        });
      });
      
      await batch.commit();
      uploadedCount += chunk.length;
      console.log(`✅ Uploaded batch ${Math.ceil((i + 1) / batchSize)}: ${uploadedCount}/${huelGuideData.length} courses`);
    }
    
    // Create metadata document
    console.log('📊 Creating metadata document...');
    await db.collection('huel_guide').doc('_metadata').set({
      total_courses: huelGuideData.length,
      last_updated: new Date(),
      version: new Date().toISOString(),
      description: 'HUEL (Humanities and Social Sciences) course guide for BITS Pilani'
    });
    
    console.log('🎉 HUEL Guide upload completed successfully!');
    console.log(`📈 Total courses uploaded: ${uploadedCount}`);
    console.log('🔗 Collection: huel_guide');
    
    // Verify upload
    const verifyCount = await db.collection('huel_guide').get();
    const actualCourseCount = verifyCount.docs.length - 1; // Subtract metadata doc
    console.log(`✅ Verification: ${actualCourseCount} courses in Firestore`);
    
    if (actualCourseCount !== huelGuideData.length) {
      console.warn('⚠️ Warning: Upload count mismatch!');
    } else {
      console.log('✨ Upload verified successfully!');
    }
    
  } catch (error) {
    console.error('❌ Error uploading HUEL Guide:', error);
    process.exit(1);
  }
}

// Run the upload
uploadHuelGuide();