import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const serviceAccount = {
  type: 'service_account',
  project_id: process.env.FIREBASE_PROJECT_ID,
  private_key_id: process.env.FIREBASE_PRIVATE_KEY_ID,
  private_key: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  client_email: process.env.FIREBASE_CLIENT_EMAIL,
  client_id: process.env.FIREBASE_CLIENT_ID,
  auth_uri: process.env.FIREBASE_AUTH_URI,
  token_uri: process.env.FIREBASE_TOKEN_URI,
  auth_provider_x509_cert_url: process.env.FIREBASE_AUTH_PROVIDER_X509_CERT_URL,
  client_x509_cert_url: process.env.FIREBASE_CLIENT_X509_CERT_URL,
};

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

async function deleteCollection(colRef) {
  const docs = await colRef.listDocuments();
  if (docs.length === 0) {
    console.log(`  No documents found in ${colRef.path}`);
    return 0;
  }

  let deleted = 0;
  const batchSize = 500;

  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + batchSize);
    for (const doc of chunk) {
      batch.delete(doc);
    }
    await batch.commit();
    deleted += chunk.length;
    console.log(`  Deleted ${deleted}/${docs.length} docs`);
  }

  return deleted;
}

async function main() {
  const colRef = db.collection('user_timetables');
  console.log('Deleting user_timetables collection...');
  const count = await deleteCollection(colRef);
  console.log(`Done. Deleted ${count} documents.`);
}

main().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
