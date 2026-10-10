export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allowed = (env.ALLOWED_ORIGIN || '').split(',').map(s => s.trim());
    const isLocalhost = /^http:\/\/localhost(:\d+)?$/.test(origin);
    const corsOrigin = (allowed.includes(origin) || isLocalhost) ? origin : allowed[0];

    const corsHeaders = {
      'Access-Control-Allow-Origin': corsOrigin,
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'GET' && path === '/health') {
      return Response.json({ status: 'ok', timestamp: new Date().toISOString() }, { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return Response.json({ error: 'Method not allowed' }, { status: 405, headers: corsHeaders });
    }

    // API key authentication for write endpoints
    if (env.API_KEY) {
      const authHeader = request.headers.get('Authorization') || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
      if (token !== env.API_KEY) {
        return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders });
      }
    }

    if (path === '/perf') {
      return handlePerf(request, env, corsHeaders);
    }

    if (path === '/test') {
      return handleTest(request, env, corsHeaders);
    }

    if (path === '/log') {
      return handleLog(request, env, corsHeaders);
    }

    return Response.json({ error: 'Not found' }, { status: 404, headers: corsHeaders });
  },
};

async function handlePerf(request, env, corsHeaders) {
  try {
    const body = await request.json();

    if (!body.metrics || !Array.isArray(body.metrics)) {
      return Response.json({ error: 'Missing or invalid metrics array' }, { status: 400, headers: corsHeaders });
    }

    const raw = JSON.stringify(body);
    if (raw.length > 1_000_000) {
      return Response.json({ error: 'Payload too large' }, { status: 413, headers: corsHeaders });
    }

    const payload = {
      type: 'performance',
      timestamp: body.timestamp || new Date().toISOString(),
      metrics: body.metrics,
      metadata: body.metadata || {},
      receivedAt: new Date().toISOString(),
    };

    const key = buildKey('perf');
    await env.LOGS_BUCKET.put(key, JSON.stringify(payload, null, 2), {
      httpMetadata: { contentType: 'application/json' },
    });

    return Response.json({ ok: true, key }, { headers: corsHeaders });
  } catch (e) {
    return Response.json({ error: 'Processing failed' }, { status: 500, headers: corsHeaders });
  }
}

async function handleTest(request, env, corsHeaders) {
  try {
    const body = await request.json();

    if (!body.suite || typeof body.suite !== 'string') {
      return Response.json({ error: 'Missing or invalid suite name' }, { status: 400, headers: corsHeaders });
    }

    if (!body.results || !Array.isArray(body.results)) {
      return Response.json({ error: 'Missing or invalid results array' }, { status: 400, headers: corsHeaders });
    }

    const raw = JSON.stringify(body);
    if (raw.length > 1_000_000) {
      return Response.json({ error: 'Payload too large' }, { status: 413, headers: corsHeaders });
    }

    const payload = {
      type: 'test',
      suite: body.suite,
      results: body.results,
      timestamp: body.timestamp || new Date().toISOString(),
      metadata: body.metadata || {},
      receivedAt: new Date().toISOString(),
    };

    const key = buildKey(`test-${body.suite}`);
    await env.LOGS_BUCKET.put(key, JSON.stringify(payload, null, 2), {
      httpMetadata: { contentType: 'application/json' },
    });

    return Response.json({ ok: true, key }, { headers: corsHeaders });
  } catch (e) {
    return Response.json({ error: 'Processing failed' }, { status: 500, headers: corsHeaders });
  }
}

async function handleLog(request, env, corsHeaders) {
  try {
    const body = await request.json();

    if (!body.entries || !Array.isArray(body.entries)) {
      return Response.json({ error: 'Missing or invalid entries array' }, { status: 400, headers: corsHeaders });
    }

    const raw = JSON.stringify(body);
    if (raw.length > 1_000_000) {
      return Response.json({ error: 'Payload too large' }, { status: 413, headers: corsHeaders });
    }

    const payload = {
      type: 'log',
      timestamp: body.timestamp || new Date().toISOString(),
      entries: body.entries,
      metadata: body.metadata || {},
      receivedAt: new Date().toISOString(),
    };

    const key = buildKey('log');
    await env.LOGS_BUCKET.put(key, JSON.stringify(payload, null, 2), {
      httpMetadata: { contentType: 'application/json' },
    });

    return Response.json({ ok: true, key, count: body.entries.length }, { headers: corsHeaders });
  } catch (e) {
    return Response.json({ error: 'Processing failed' }, { status: 500, headers: corsHeaders });
  }
}

function buildKey(prefix) {
  const now = new Date();
  const date = now.toISOString().split('T')[0];
  const ts = now.getTime();
  const rand = Math.random().toString(36).slice(2, 8);
  return `logs/${date}/${prefix}-${ts}-${rand}.json`;
}
