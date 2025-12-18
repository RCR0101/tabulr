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

async function uploadProfessors() {
  try {
    console.log('👨‍🏫 Starting professor data upload...');

    // Read the professor data
    const dataPath = path.join(__dirname, 'profs.json');
    if (!fs.existsSync(dataPath)) {
      throw new Error('profs.json not found');
    }

    const professorData = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
    console.log('📖 Professor data loaded successfully');

    // Validate data structure
    if (!professorData.profs || !Array.isArray(professorData.profs)) {
      throw new Error('Invalid data structure: expected profs array');
    }

    console.log(`📊 Found ${professorData.profs.length} professors`);

    // Clear existing data
    console.log('🔄 Clearing existing professor data...');
    const professorsRef = db.collection('professors');
    const snapshot = await professorsRef.get();
    
    const deletePromises = [];
    snapshot.forEach(doc => {
      deletePromises.push(doc.ref.delete());
    });
    
    if (deletePromises.length > 0) {
      await Promise.all(deletePromises);
      console.log(`🗑️ Deleted ${deletePromises.length} existing professor records`);
    }

    // Upload new data
    console.log('⬆️ Uploading new professor data...');
    const uploadPromises = [];
    
    professorData.profs.forEach((prof, index) => {
      // Validate professor object
      if (!prof.name || !prof.chamber) {
        console.warn(`⚠️ Skipping invalid professor at index ${index}:`, prof);
        return;
      }

      // Create document with auto-generated ID
      const docRef = professorsRef.doc();
      const professorDoc = {
        id: docRef.id,
        name: prof.name.trim(),
        chamber: prof.chamber.trim(),
        // Add searchable fields for better querying
        nameSearch: prof.name.trim().toLowerCase(),
        chamberSearch: prof.chamber.trim().toLowerCase(),
        createdAt: new Date(),
        updatedAt: new Date()
      };
      
      uploadPromises.push(docRef.set(professorDoc));
    });

    await Promise.all(uploadPromises);
    console.log(`✅ Successfully uploaded ${uploadPromises.length} professor records`);

    // Create metadata document with upload info
    const metadataRef = db.collection('metadata').doc('professors');
    await metadataRef.set({
      totalProfessors: uploadPromises.length,
      lastUpdated: new Date(),
      version: '1.0.0',
      uploadedBy: 'admin_script'
    });

    console.log('📝 Metadata updated successfully');
    console.log('🎉 Professor data upload completed!');

  } catch (error) {
    console.error('❌ Error uploading professor data:', error);
    process.exit(1);
  }
}

// Run the upload
uploadProfessors().then(() => {
  console.log('🏁 Upload script finished');
  process.exit(0);
}).catch(error => {
  console.error('💥 Script failed:', error);
  process.exit(1);
});