
require('dotenv/config');

const http = require('node:http');
const crypto = require('node:crypto');

const secret = process.env.NOTIFICATION_WEBHOOK_SECRET;
if (!secret) throw new Error('Webhook secret belum tersedia');

const attempts = new Map();
const processed = new Set();

http.createServer((req, res) => {
  const chunks = [];

  req.on('data', chunk => chunks.push(chunk));

  req.on('end', () => {
    const body = Buffer.concat(chunks);

    const signature = crypto
      .createHmac('sha256', secret)
      .update(body)
      .digest('hex');

    if (req.headers['x-pawpals-signature'] !== signature) {
      res.writeHead(401);
      return res.end('Invalid signature');
    }

    let event;
    try {
      event = JSON.parse(body.toString());
    } catch {
      res.writeHead(400);
      return res.end('Invalid JSON');
    }

    // Hanya menerima event pengujian ini.
    if (event.event_type !== 'LOCAL_SMOKE_TEST_RETRY') {
      res.writeHead(503);
      return res.end('Non-test event rejected');
    }

    const key = event.event_key;
    const attempt = (attempts.get(key) || 0) + 1;
    attempts.set(key, attempt);

    if (attempt === 1) {
      console.log('Percobaan 1: HTTP 500', key);
      res.writeHead(500);
      return res.end('Simulated failure');
    }

    if (!processed.has(key)) {
      processed.add(key);
      console.log('Percobaan 2: HTTP 200', key);
      console.log('Event berhasil diproses');
    } else {
      console.log('Duplikat diabaikan:', key);
    }

    res.writeHead(200);
    res.end('OK');
  });
}).listen(4010, '127.0.0.1', () => {
  console.log('Webhook retry test aktif pada port 4010');
});
