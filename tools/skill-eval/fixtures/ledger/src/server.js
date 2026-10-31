'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { readLedger, total } = require('./ledger');
const { formatCents } = require('./amount');

const port = Number(process.env.PORT || 4310);
const root = path.resolve(__dirname, '..');

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok\n');
    return;
  }
  if (url.pathname === '/total') {
    const name = url.searchParams.get('ledger') || 'march';
    const file = path.join(root, 'examples', `${path.basename(name)}.txt`);
    if (!fs.existsSync(file)) {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: `no ledger ${name}` }) + '\n');
      return;
    }
    const entries = readLedger(fs.readFileSync(file, 'utf8'));
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ledger: name, entries: entries.length, total: formatCents(total(entries)) }) + '\n');
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('not found\n');
});

server.listen(port, '127.0.0.1', () => {
  console.log(`ledger listening on http://127.0.0.1:${port}`);
});
