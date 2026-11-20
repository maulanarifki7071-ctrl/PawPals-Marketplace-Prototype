import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { env } from '../../config/env';
export function opaqueToken(bytes=32):string{return randomBytes(bytes).toString('base64url');}
export function tokenHash(v:string):string{return createHash('sha256').update(v).digest('hex');}
export function signGrant(payload:Record<string,any>, ttlSeconds:number):string { const now=Math.floor(Date.now()/1000); const body=Buffer.from(JSON.stringify({...payload,iat:now,exp:now+ttlSeconds})).toString('base64url'); const sig=createHmac('sha256',env.tokenSecret).update(body).digest('base64url'); return `${body}.${sig}`; }
export function verifyGrant(token:any,expectedType:string):any { if(typeof token!=='string') return null; const [body,sig]=token.split('.'); if(!body||!sig)return null; const expected=createHmac('sha256',env.tokenSecret).update(body).digest('base64url'); if(sig.length!==expected.length||!timingSafeEqual(Buffer.from(sig),Buffer.from(expected)))return null; try{const p=JSON.parse(Buffer.from(body,'base64url').toString('utf8')); if(p.typ!==expectedType||p.exp<Math.floor(Date.now()/1000))return null; return p;}catch{return null;} }
