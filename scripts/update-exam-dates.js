import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from parent directory (.env in timetable_maker root)
dotenv.config({ path: path.join(__dirname, '.', '.env') });

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

function updateDateFrom2025To2026(dateString) {
  if (!dateString || !dateString.includes('2025')) {
    return dateString;
  }
  return dateString.replace('2025', '2026');
}

async function updateExamDatesForCollection(collectionName) {
  console.log(`🔄 Processing collection: ${collectionName}`);
  
  const coursesRef = db.collection(collectionName);
  const snapshot = await coursesRef.get();
  
  if (snapshot.empty) {
    console.log(`⚠️  Collection ${collectionName} is empty or doesn't exist`);
    return 0;
  }
  
  let updatedCount = 0;
  const batchSize = 500;
  
  for (let i = 0; i < snapshot.docs.length; i += batchSize) {
    const batch = db.batch();
    const docsToProcess = snapshot.docs.slice(i, i + batchSize);
    
    for (const doc of docsToProcess) {
      const data = doc.data();
      let needsUpdate = false;
      const updates = {};
      
      // Check and update midSemExam date
      if (data.midSemExam && data.midSemExam.date && data.midSemExam.date.includes('2025')) {
        updates['midSemExam.date'] = updateDateFrom2025To2026(data.midSemExam.date);
        needsUpdate = true;
      }
      
      // Check and update endSemExam date  
      if (data.endSemExam && data.endSemExam.date && data.endSemExam.date.includes('2025')) {
        updates['endSemExam.date'] = updateDateFrom2025To2026(data.endSemExam.date);
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        batch.update(doc.ref, updates);
        updatedCount++;
      }
    }
    
    if (docsToProcess.some(doc => {
      const data = doc.data();
      return (data.midSemExam && data.midSemExam.date && data.midSemExam.date.includes('2025')) ||
             (data.endSemExam && data.endSemExam.date && data.endSemExam.date.includes('2025'));
    })) {
      await batch.commit();
      console.log(`✅ Updated batch ${Math.floor(i/batchSize) + 1} for ${collectionName}`);
    }
  }
  
  console.log(`✅ Updated ${updatedCount} courses in ${collectionName}`);
  return updatedCount;
}

async function main() {
  console.log('🚀 Starting exam date updates (2025 → 2026)...\n');
  
  const collections = ['hyd-courses', 'goa-courses', 'pilani-courses'];
  let totalUpdated = 0;
  
  for (const collection of collections) {
    try {
      const updated = await updateExamDatesForCollection(collection);
      totalUpdated += updated;
    } catch (error) {
      console.error(`❌ Error updating ${collection}:`, error.message);
    }
  }
  
  console.log(`\n🎉 Completed! Total courses updated: ${totalUpdated}`);
}

main().catch(console.error);