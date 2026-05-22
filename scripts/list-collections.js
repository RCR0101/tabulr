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

const MAX_DEPTH = 4;
const SAMPLE_SIZE = 10;

async function explore(colRef, depth = 0) {
  const prefix = '  '.repeat(depth);
  const countSnap = await colRef.count().get();
  const count = countSnap.data().count;

  // Sample a few doc refs (includes phantoms)
  const allDocRefs = await colRef.listDocuments();
  const sampleRefs = allDocRefs.slice(0, SAMPLE_SIZE);

  console.log(`${prefix}${colRef.path}  (${count} docs, ${allDocRefs.length} refs)`);

  if (depth >= MAX_DEPTH) return;

  // Discover unique subcollection names from sampled docs
  const seenSubs = new Set();
  for (const docRef of sampleRefs) {
    const subCols = await docRef.listCollections();
    for (const sub of subCols) {
      if (seenSubs.has(sub.id)) continue;
      seenSubs.add(sub.id);
      await explore(sub, depth + 1);
    }
  }
}

async function main() {
  const topLevel = await db.listCollections();
  for (const col of topLevel) {
    await explore(col);
    console.log('');
  }
}

main().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
