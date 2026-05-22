import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '..', '.env') });

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

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

async function uploadBranchStructure() {
  console.log('Starting branch structure upload...');

  const repoRoot = path.join(__dirname, '..', '..');

  const cdcPath = path.join(repoRoot, 'cdc_structure.json');
  const coursePath = path.join(repoRoot, 'course_structure.json');

  if (!fs.existsSync(cdcPath)) throw new Error('cdc_structure.json not found at ' + cdcPath);
  if (!fs.existsSync(coursePath)) throw new Error('course_structure.json not found at ' + coursePath);

  const cdcData = JSON.parse(fs.readFileSync(cdcPath, 'utf8'));
  const courseData = JSON.parse(fs.readFileSync(coursePath, 'utf8'));

  console.log(`CDC branches: ${Object.keys(cdcData).length}`);
  console.log(`Course structure branches: ${Object.keys(courseData).length}`);

  const allBranches = new Set([...Object.keys(cdcData), ...Object.keys(courseData)]);
  console.log(`Total unique branches: ${allBranches.size}`);

  // Clear existing branch documents
  console.log('Clearing existing reference/branches/data collection...');
  const branchesRef = db.collection('reference').doc('branches').collection('data');
  const existing = await branchesRef.get();

  if (!existing.empty) {
    const batchSize = 450;
    let deleted = 0;
    for (let i = 0; i < existing.docs.length; i += batchSize) {
      const deleteBatch = db.batch();
      const chunk = existing.docs.slice(i, i + batchSize);
      chunk.forEach(doc => deleteBatch.delete(doc.ref));
      await deleteBatch.commit();
      deleted += chunk.length;
    }
    console.log(`Cleared ${deleted} existing documents`);
  }

  // Upload each branch
  let batchCount = 0;
  let currentBatch = db.batch();
  let opCount = 0;

  for (const branchCode of allBranches) {
    const cdcs = cdcData[branchCode] || {};
    const structure = courseData[branchCode] || {};

    const docData = {
      branch_code: branchCode,
      cdcs: cdcs,
      dels: structure.dels || [],
      huels: structure.huels || [],
      updated_at: new Date().toISOString(),
    };

    const docRef = branchesRef.doc(branchCode);
    currentBatch.set(docRef, docData);
    opCount++;

    console.log(`  ${branchCode}: ${Object.keys(cdcs).length} semesters, ${docData.dels.length} DELs, ${docData.huels.length} HUELs`);

    if (opCount >= 450) {
      await currentBatch.commit();
      batchCount++;
      console.log(`Batch ${batchCount} committed (${opCount} ops)`);
      currentBatch = db.batch();
      opCount = 0;
    }
  }

  // Metadata document
  const metaRef = branchesRef.doc('_metadata');
  currentBatch.set(metaRef, {
    branches: [...allBranches].sort(),
    lastUpdated: new Date().toISOString(),
    version: '2.0.0',
    uploadedBy: 'upload-branch-structure.js',
  });
  opCount++;

  if (opCount > 0) {
    await currentBatch.commit();
    batchCount++;
    console.log(`Final batch committed (${opCount} ops)`);
  }

  // Verify
  const verifySnapshot = await branchesRef.get();
  const branchDocs = verifySnapshot.docs.filter(d => d.id !== '_metadata').length;
  console.log(`\nUpload complete: ${branchDocs} branches + metadata`);
}

async function main() {
  try {
    await uploadBranchStructure();
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

process.on('SIGINT', () => { console.log('\nInterrupted'); process.exit(1); });
main().catch(console.error);
