import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve } from 'node:path';

const root = resolve('build/web');
const port = Number.parseInt(process.argv[2] ?? '8080', 10);

if (!existsSync(join(root, 'main.dart.wasm'))) {
  console.error('Missing build/web/main.dart.wasm. Run flutter build web --wasm first.');
  process.exit(1);
}

const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.otf': 'font/otf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
  '.webp': 'image/webp',
};

const server = createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const relativePath = normalize(pathname).replace(/^[/\\]+/, '');
  let filePath = resolve(root, relativePath || 'index.html');

  if (!filePath.startsWith(`${root}/`)) {
    response.writeHead(403).end('Forbidden');
    return;
  }
  if (!existsSync(filePath) || statSync(filePath).isDirectory()) {
    filePath = join(root, 'index.html');
  }

  response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  response.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader(
    'Content-Type',
    mimeTypes[extname(filePath)] ?? 'application/octet-stream',
  );
  createReadStream(filePath).pipe(response);
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Multi-threaded SkWasm: http://127.0.0.1:${port}`);
  console.log('Use guest mode while profiling; popup auth is intentionally isolated.');
});
