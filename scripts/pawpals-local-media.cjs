'use strict';
/**
 * PawPals local S3-compatible private object storage, DEMO ONLY.
 * Binds 127.0.0.1. Supports SigV4 presigned PUT and HEAD as issued by
 * src/shared/providers/media.ts. Not a production S3 server.
 */
require('dotenv/config');
const http = require('node:http');
const { createHash, createHmac, timingSafeEqual, randomUUID } = require('node:crypto');
const path = require('node:path');
const fs = require('node:fs/promises');

const HOST = '127.0.0.1';
const PORT = Number(process.env.PAWPALS_LOCAL_MEDIA_PORT || '9100');
const BUCKET = process.env.MEDIA_S3_BUCKET;
const REGION = process.env.MEDIA_S3_REGION || 'ap-southeast-1';
const ACCESS = process.env.MEDIA_S3_ACCESS_KEY_ID;
const SECRET = process.env.MEDIA_S3_SECRET_ACCESS_KEY;
const ENDPOINT = process.env.MEDIA_S3_ENDPOINT;
const MAX_BYTES = 10 * 1024 * 1024;
const ROOT = path.resolve(__dirname, '..', '.pawpals-local-media');
const encode = (s) => encodeURIComponent(s).replace(/[!'()*]/g, ch => `%${ch.charCodeAt(0).toString(16).toUpperCase()}`);
const hmac = (key, val) => createHmac('sha256', key).update(val).digest();
const sha256 = (val) => createHash('sha256').update(val).digest('hex');
function fail(res, code, msg) { res.writeHead(code, { 'content-type':'text/plain; charset=utf-8', 'cache-control':'no-store' }); res.end(msg); }
function validPort(port) { return Number.isInteger(port) && port >= 1024 && port <= 65535; }
function verifyRequest(req, url) {
  if (!['PUT','HEAD','GET'].includes(req.method)) return false;
  const qp = url.searchParams;
  const algorithm = qp.get('X-Amz-Algorithm');
  const cred = qp.get('X-Amz-Credential');
  const stamp = qp.get('X-Amz-Date');
  const ttl = Number(qp.get('X-Amz-Expires'));
  const signed = qp.get('X-Amz-SignedHeaders');
  const given = qp.get('X-Amz-Signature');
  if (algorithm !== 'AWS4-HMAC-SHA256' || !cred || !stamp || !given || !/^[a-f0-9]{64}$/.test(given)) return false;
  if (!Number.isInteger(ttl) || ttl < 1 || ttl > 600) return false;
  if (!/^\d{8}T\d{6}Z$/.test(stamp)) return false;
  const ts = Date.UTC(Number(stamp.slice(0,4)),Number(stamp.slice(4,6))-1,Number(stamp.slice(6,8)),Number(stamp.slice(9,11)),Number(stamp.slice(11,13)),Number(stamp.slice(13,15)));
  if (!Number.isFinite(ts) || Math.abs(ts - Date.now()) > 12 * 60 * 1000 || Date.now() > ts + ttl*1000) return false;
  const day = stamp.slice(0,8);
  const scope = `${day}/${REGION}/s3/aws4_request`;
  if (cred !== `${ACCESS}/${scope}`) return false;
  const expectedSigned = req.method === 'PUT' ? 'content-type;host' : 'host';
  if (signed !== expectedSigned) return false;
  if (req.headers.host !== `${HOST}:${PORT}`) return false;
  const mime = String(req.headers['content-type'] || '');
  if (req.method === 'PUT' && !['image/png','image/jpeg','application/pdf','image/webp'].includes(mime)) return false;
  const hdr = req.method === 'PUT' ? `content-type:${mime}\nhost:${req.headers.host}\n` : `host:${req.headers.host}\n`;
  const query = [...qp.entries()].filter(([k]) => k !== 'X-Amz-Signature');
  if (query.length !== 5) return false;
  const canonicalQuery = query.sort(([a],[b]) => a.localeCompare(b)).map(([k,v])=>`${encode(k)}=${encode(v)}`).join('&');
  const canonical = [req.method,url.pathname,canonicalQuery,hdr,signed,'UNSIGNED-PAYLOAD'].join('\n');
  const signingKey = hmac(hmac(hmac(hmac(`AWS4${SECRET}`,day),REGION),'s3'),'aws4_request');
  const expected = createHmac('sha256',signingKey).update(`AWS4-HMAC-SHA256\n${stamp}\n${scope}\n${sha256(canonical)}`).digest('hex');
  return timingSafeEqual(Buffer.from(expected,'hex'),Buffer.from(given,'hex'));
}
async function run() {
  if (process.env.NODE_ENV === 'production') throw Error('Local media server is disabled in NODE_ENV=production');
  if (!validPort(PORT) || !BUCKET || !/^[a-zA-Z0-9._-]+$/.test(BUCKET) || !ACCESS || !SECRET || SECRET.length < 24)
    throw Error('Set MEDIA_S3_BUCKET, MEDIA_S3_ACCESS_KEY_ID and a random MEDIA_S3_SECRET_ACCESS_KEY (24+ chars).');
  if (ENDPOINT !== `http://${HOST}:${PORT}`) throw Error(`MEDIA_S3_ENDPOINT must equal http://${HOST}:${PORT}`);
  await fs.mkdir(ROOT,{recursive:true,mode:0o700});
  const server=http.createServer(async (req,res)=>{
    try {
      const url = new URL(req.url,`http://${HOST}:${PORT}`);
      if (req.method === 'GET' && url.pathname === '/health') return fail(res,200,'PAWPALS_LOCAL_MEDIA_OK');
      if (!['PUT','HEAD','GET'].includes(req.method)) return fail(res,405,'Method not allowed');
      // Accept only provider-generated paths; store by their SHA-256 to prevent traversal.
      const prefix=`/${BUCKET}/private/`;
      if (!url.pathname.startsWith(prefix) || url.pathname.length > 350 || !/^\/[a-zA-Z0-9/_\-%.]+$/.test(url.pathname)) return fail(res,404,'Not found');
      if (!verifyRequest(req,url)) return fail(res,403,'Invalid or expired signature');
      const hash=sha256(url.pathname);
      const dst=path.join(ROOT,`${hash}.blob`);
      const meta=path.join(ROOT,`${hash}.json`);
      if (req.method === 'HEAD' || req.method === 'GET') {
        let data;
        try { data=JSON.parse(await fs.readFile(meta,'utf8')); await fs.access(dst); } catch { return fail(res,404,'Not found'); }
        res.writeHead(200, {'content-type':data.mime,'content-length':String(data.bytes),'cache-control':'no-store'});
        return res.end(req.method === 'GET' ? await fs.readFile(dst) : undefined);
      }
      let bytes=0; const chunks=[];
      for await (const chunk of req) {
        bytes+=chunk.length;
        if (bytes>MAX_BYTES) return fail(res,413,'File too large');
        chunks.push(chunk);
      }
      if(bytes===0) return fail(res,400,'Empty upload');
      const mime=String(req.headers['content-type']);
      const tmp=path.join(ROOT,`${hash}.${randomUUID()}.tmp`);
      try { await fs.writeFile(tmp,Buffer.concat(chunks),{mode:0o600}); await fs.rename(tmp,dst); }
      finally { await fs.rm(tmp,{force:true}).catch(()=>{}); }
      await fs.writeFile(meta,JSON.stringify({mime,bytes}),{mode:0o600});
      res.writeHead(200,{'cache-control':'no-store'});res.end('Stored');
    } catch (err) {
      console.error('Local storage request failed:', err?.message || 'unknown error');
      if (!res.headersSent) fail(res,500,'Local storage error'); else res.end();
    }
  });
  server.listen(PORT,HOST,()=>{
    console.log(`PawPals local private media listening at http://${HOST}:${PORT}`);
    console.log(`Storage folder: ${ROOT}`);
    console.log('DEVELOPMENT ONLY. Do not use actual KTP/selfies.');
  });
}
run().catch(err=>{console.error(err.message);process.exitCode=1;});
