#!/usr/bin/env python3
"""BitChord local server: serves ./site on http://localhost:5173 (SPA fallback).

The extension only talks to this exact origin, so the port is fixed.
Binds to 127.0.0.1 only. Standard library, no dependencies.
"""
import http.server
import os
import socketserver

PORT = 5173
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "site")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm",
        ".onnx": "application/octet-stream", ".svg": "image/svg+xml", ".json": "application/json",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def send_head(self):
        if not os.path.exists(self.translate_path(self.path.split("?")[0])):
            self.path = "/index.html"
        return super().send_head()

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    Server(("127.0.0.1", PORT), Handler).serve_forever()
