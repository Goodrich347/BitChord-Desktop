#!/usr/bin/env node
// BitChord local server (Node, no dependencies): serves ./site on
// http://localhost:5173 with SPA fallback. The extension only trusts this
// exact origin, so the port is fixed. Binds to 127.0.0.1 only.
import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const PORT = 5173;
const ROOT = join(dirname(fileURLToPath(import.meta.url)), 'site');
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.webp': 'image/webp', '.ico': 'image/x-icon', '.wasm': 'application/wasm',
  '.onnx': 'application/octet-stream', '.woff2': 'font/woff2', '.txt': 'text/plain', '.zip': 'application/zip',
};

function resolveFile(urlPath) {
  let rel;
  try { rel = decodeURIComponent(urlPath.split('?')[0]); } catch { rel = '/'; }
  const file = normalize(join(ROOT, rel));
  if (file !== ROOT && !file.startsWith(ROOT + sep)) return join(ROOT, 'index.html');
  try { if (statSync(file).isFile()) return file; } catch {}
  return join(ROOT, 'index.html');
}

createServer((req, res) => {
  const file = resolveFile(req.url || '/');
  let size;
  try { size = statSync(file).size; } catch { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'Content-Type': TYPES[extname(file).toLowerCase()] || 'application/octet-stream', 'Content-Length': size });
  if (req.method === 'HEAD') { res.end(); return; }
  createReadStream(file).pipe(res);
}).listen(PORT, '127.0.0.1');
