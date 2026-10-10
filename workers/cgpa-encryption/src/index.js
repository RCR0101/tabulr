export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allowed = parseAllowedOrigins(env.ALLOWED_ORIGINS || env.ALLOWED_ORIGIN || '');
    const isLocalhost = /^http:\/\/localhost(:\d+)?$/.test(origin);
    const corsOrigin = (allowed.includes(origin) || isLocalhost) ? origin : allowed[0];

    const corsHeaders = {
      'Access-Control-Allow-Origin': corsOrigin,
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return Response.json({ error: 'Method not allowed' }, { status: 405, headers: corsHeaders });
    }

    try {
      const authHeader = request.headers.get('Authorization') || '';
      if (!authHeader.startsWith('Bearer ')) {
        return Response.json({ error: 'Missing authorization' }, { status: 401, headers: corsHeaders });
      }
      const idToken = authHeader.slice(7);

      const payload = await verifyFirebaseToken(idToken, env.FIREBASE_PROJECT_ID);
      if (!payload) {
        return Response.json({ error: 'Invalid token' }, { status: 401, headers: corsHeaders });
      }

      const userId = deriveUserDocId(payload.email);
      if (!userId) {
        return Response.json({ error: 'Unrecognized email domain' }, { status: 403, headers: corsHeaders });
      }

      const { action, data, items } = await request.json();

      if (!action) {
        return Response.json({ error: 'Missing required fields' }, { status: 400, headers: corsHeaders });
      }

      // The key is derived from the caller's own userId, so a batch can only
      // ever contain that caller's own blobs — batching widens no access.
      const key = await deriveKey(env.ENCRYPTION_SECRET, userId);

      // Batch forms. The client holds one document per semester, so a CGPA
      // screen load was firing one round trip per semester (up to 8) to do
      // work that is identical and independent. One request now covers them.
      if (action === 'encryptBatch' || action === 'decryptBatch') {
        const bad = validateBatch(items);
        if (bad) return Response.json({ error: bad }, { status: 400, headers: corsHeaders });

        const op = action === 'encryptBatch' ? encrypt : decrypt;
        // A single bad blob must not fail the whole batch — the client can
        // still render the semesters that did decrypt, which is what the
        // per-semester error handling in CGPAService already expects.
        const results = await Promise.all(
          items.map(async (item) => {
            try {
              return { ok: true, result: await op(item, key) };
            } catch {
              return { ok: false, error: 'Processing failed' };
            }
          }),
        );
        return Response.json({ results }, { headers: corsHeaders });
      }

      if (typeof data !== 'string') {
        return Response.json({ error: 'Invalid field types' }, { status: 400, headers: corsHeaders });
      }

      if (data.length > MAX_ITEM_BYTES) {
        return Response.json({ error: 'Payload too large' }, { status: 413, headers: corsHeaders });
      }

      let result;
      if (action === 'encrypt') {
        result = await encrypt(data, key);
      } else if (action === 'decrypt') {
        result = await decrypt(data, key);
      } else {
        return Response.json({ error: 'Invalid action' }, { status: 400, headers: corsHeaders });
      }

      return Response.json({ result }, { headers: corsHeaders });
    } catch (e) {
      // `detail` used to echo the raw exception message. For AES-GCM that is a
      // decrypt-failure string, which tells an attacker probing with forged
      // ciphertext exactly why each attempt failed. The real message still goes
      // to the Workers log, where only an operator can see it.
      console.error('cgpa-encryption:', e instanceof Error ? e.stack : String(e));
      return Response.json({ error: 'Processing failed' }, { status: 500, headers: corsHeaders });
    }
  },
};

function parseAllowedOrigins(rawValue) {
  if (!rawValue) return [];

  if (Array.isArray(rawValue)) {
    return rawValue.map((value) => String(value).trim()).filter(Boolean);
  }

  if (typeof rawValue !== 'string') {
    return [];
  }

  const trimmed = rawValue.trim();
  if (!trimmed) return [];

  if (trimmed.startsWith('[')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((value) => String(value).trim()).filter(Boolean);
      }
    } catch {
      // Fall through to comma-separated parsing below.
    }
  }

  return trimmed.split(',').map((value) => value.trim()).filter(Boolean);
}

// --- Request validation ---

const MAX_ITEM_BYTES = 1_000_000;
// One CGPA document per semester; 16 leaves headroom over a normal degree.
const MAX_BATCH_ITEMS = 16;

/** Returns an error string for an invalid batch, or null when it is fine. */
function validateBatch(items) {
  if (!Array.isArray(items)) return 'items must be an array';
  if (items.length === 0) return 'items must not be empty';
  if (items.length > MAX_BATCH_ITEMS) return `items must be at most ${MAX_BATCH_ITEMS}`;
  let total = 0;
  for (const item of items) {
    if (typeof item !== 'string') return 'items must all be strings';
    total += item.length;
  }
  // Bound the aggregate, not just each element — 16 x 1MB is still 16MB of
  // work for one request.
  if (total > MAX_ITEM_BYTES) return 'Payload too large';
  return null;
}

// --- Firebase ID token verification ---

let cachedKeys = null;
let cachedKeysExpiry = 0;

async function getGoogleJwks() {
  if (cachedKeys && Date.now() < cachedKeysExpiry) return cachedKeys;

  const resp = await fetch(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  );
  const cacheControl = resp.headers.get('Cache-Control') || '';
  const maxAgeMatch = cacheControl.match(/max-age=(\d+)/);
  const maxAge = maxAgeMatch ? parseInt(maxAgeMatch[1], 10) : 3600;

  const jwks = await resp.json();
  const keyMap = {};
  for (const key of jwks.keys) {
    const cryptoKey = await crypto.subtle.importKey(
      'jwk', key, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
    );
    keyMap[key.kid] = cryptoKey;
  }

  cachedKeys = keyMap;
  cachedKeysExpiry = Date.now() + maxAge * 1000;
  return cachedKeys;
}

function base64UrlDecode(str) {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

async function verifyFirebaseToken(token, projectId) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const header = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
  const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));

  if (header.alg !== 'RS256') return null;
  if (payload.aud !== projectId) return null;
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;

  const now = Math.floor(Date.now() / 1000);
  if (payload.exp < now || payload.iat > now + 5) return null;
  if (!payload.sub || !payload.email) return null;

  const keys = await getGoogleJwks();
  const publicKey = keys[header.kid];
  if (!publicKey) return null;

  const signatureBytes = base64UrlDecode(parts[2]);
  const signedData = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);

  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, signatureBytes, signedData);
  if (!valid) return null;

  return payload;
}

// --- userId derivation (mirrors auth_service.dart) ---

function deriveUserDocId(email) {
  if (!email || !email.includes('@')) return null;
  const [username, domain] = email.split('@');
  const d = domain.toLowerCase();
  if (d === 'hyderabad.bits-pilani.ac.in') return `${username}H`;
  if (d === 'pilani.bits-pilani.ac.in') return `${username}P`;
  if (d === 'goa.bits-pilani.ac.in') return `${username}G`;
  if (d === 'dubai.bits-pilani.ac.in') return `${username}D`;
  return null;
}

// --- Encryption ---

async function deriveKey(secret, userId) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const derived = await crypto.subtle.sign('HMAC', keyMaterial, enc.encode(userId));
  return crypto.subtle.importKey(
    'raw', derived, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'],
  );
}

async function encrypt(plaintext, key) {
  const enc = new TextEncoder();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv }, key, enc.encode(plaintext),
  );
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return btoa(String.fromCharCode(...combined));
}

async function decrypt(encoded, key) {
  const raw = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
  const iv = raw.slice(0, 12);
  const ciphertext = raw.slice(12);
  const decrypted = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv }, key, ciphertext,
  );
  return new TextDecoder().decode(decrypted);
}
