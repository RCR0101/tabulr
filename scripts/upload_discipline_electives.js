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

async function uploadDisciplineElectives() {
  try {
    console.log('📚 Starting discipline electives upload...');

    // Read the discipline electives data
    const dataPath = path.join(__dirname, 'toInsert.json');
    if (!fs.existsSync(dataPath)) {
      throw new Error('toInsert.json not found');
    }

    const disciplineElectivesData = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
    console.log('📖 Discipline electives data loaded successfully');

    // Clear existing data
    console.log('🔄 Clearing existing discipline electives data...');
    const disciplineElectivesRef = db.collection('discipline_electives');
    const snapshot = await disciplineElectivesRef.get();
    
    const batch = db.batch();
    snapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    if (!snapshot.empty) {
      await batch.commit();
      console.log(`✅ Cleared ${snapshot.size} existing discipline electives documents`);
    }

    // Upload new data
    console.log('🔄 Uploading new discipline electives data...');
    const newBatch = db.batch();
    let documentCount = 0;

    // Upload each branch's data as separate documents
    for (const [branchName, courses] of Object.entries(disciplineElectivesData)) {
      console.log(`📝 Processing ${branchName}...`);

      // Create a document ID from branch name (convert to kebab-case)
      const branchId = branchName.toLowerCase()
        .replace(/[^a-z0-9\s]/g, '') // Remove special characters
        .replace(/\s+/g, '-'); // Replace spaces with hyphens

      const docRef = disciplineElectivesRef.doc(branchId);
      
      // Add metadata to the document
      const documentData = {
        branchId: branchId,
        branchName: branchName,
        branchCode: getBranchCode(branchName),
        lastUpdated: new Date().toISOString(),
        courseCount: courses.length,
        courses: courses.map(course => ({
          course_code: course.course_code,
          course_name: course.course_name,
          // Add searchable fields for better querying
          code_lower: course.course_code.toLowerCase(),
          name_lower: course.course_name.toLowerCase()
        }))
      };

      newBatch.set(docRef, documentData);
      documentCount++;

      console.log(`  📚 Courses: ${courses.length} courses`);
    }

    // Create a metadata document
    const metadataRef = disciplineElectivesRef.doc('_metadata');
    const metadataData = {
      totalBranches: Object.keys(disciplineElectivesData).length,
      availableBranches: Object.keys(disciplineElectivesData),
      branchCodes: Object.keys(disciplineElectivesData).map(branchName => ({
        name: branchName,
        code: getBranchCode(branchName)
      })),
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

    console.log('✅ Discipline electives upload completed successfully!');
    console.log(`📊 Statistics:`);
    console.log(`   - Branches uploaded: ${Object.keys(disciplineElectivesData).length}`);
    console.log(`   - Total documents: ${documentCount}`);
    console.log(`   - Collection: discipline_electives`);

    // Verify the upload
    console.log('\n🔍 Verifying upload...');
    const docs = await disciplineElectivesRef.get();
    console.log(`✅ Verification: Found ${docs.size} documents in discipline_electives collection`);

    docs.forEach(doc => {
      if (doc.id === '_metadata') {
        const data = doc.data();
        console.log(`   📋 Metadata: ${data.totalBranches} branches, updated ${data.lastUpdated}`);
      } else {
        const data = doc.data();
        console.log(`   📚 ${data.branchName}: ${data.courseCount} courses`);
      }
    });

  } catch (error) {
    console.error('❌ Error uploading discipline electives:', error);
    process.exit(1);
  }
}

// Helper function to get branch code from branch name
function getBranchCode(branchName) {
  const codeMap = {
    'Civil Engineering': 'CE',
    'Chemical Engineering': 'CHE',
    'Electronics and Electrical Engineering': 'EEE',
    'Mechanical Engineering': 'ME',
    'B Pharma': 'PHA',
    'Computer Science': 'CS',
    'Electronics and Instrumentation': 'EI',
    'MSc. Biological Sciences': 'BIO',
    'MSc. Chemistry': 'CHEM',
    'MSc. Economics': 'ECON',
    'MSc. Mathematics': 'MATH',
    'MSc. Physics': 'PHY'
  };
  return codeMap[branchName] || branchName.substring(0, 3).toUpperCase();
}

// Main execution
async function main() {
  try {
    await uploadDisciplineElectives();
    console.log('\n🎉 Discipline electives upload script completed successfully!');
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