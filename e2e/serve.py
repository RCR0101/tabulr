#!/usr/bin/env python3
"""Serve build/web the way Firebase Hosting does.

`python3 -m http.server` 404s on `/prerequisites`, so it cannot exercise a
cold-loaded deep link at all — the case where the browser asks for a path and
the app has to work out what it means from the URL alone. This adds the one
piece firebase.json contributes: static files win, everything else falls back
to index.html.

    python3 e2e/serve.py [port]        # defaults to 8080, serving ../build/web
"""
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'web')


class SpaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.exists(path) and not self.path.startswith('/api'):
            # Same order as Firebase Hosting: only rewrite what no file matches.
            self.path = '/index.html'
        return super().send_head()

    def log_message(self, format, *args):  # noqa: A002 - signature is the base class's
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    if not os.path.isdir(ROOT):
        sys.exit(f'{ROOT} does not exist — run `flutter build web` first.')
    print(f'serving {ROOT} with SPA fallback on http://localhost:{port}')
    http.server.ThreadingHTTPServer(('', port), SpaHandler).serve_forever()
