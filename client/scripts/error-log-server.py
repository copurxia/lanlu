#!/usr/bin/env python3
import json
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = '/tmp/lanlu_client_errors.log'

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok'); return
        self.send_response(404); self.end_headers()
    def do_POST(self):
        if self.path != '/log':
            self.send_response(404); self.end_headers(); return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            data = json.loads(body.decode('utf-8') or '{}')
            line = json.dumps(data, ensure_ascii=False)
            with open(LOG, 'a', encoding='utf-8') as f:
                f.write(f"[{datetime.now().isoformat(timespec='seconds')}] {line}\n")
            self.send_response(204); self.end_headers()
        except Exception as e:
            self.send_response(400); self.end_headers(); self.wfile.write(str(e).encode())

ThreadingHTTPServer(('0.0.0.0', 8084), Handler).serve_forever()
