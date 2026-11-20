import { createHash, randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';
import { env } from '../../config/env';
function key():any{return createHash('sha256').update(env.dataEncryptionKey).digest();}
export function encryptSensitive(value:string):string{const iv=randomBytes(12);const c=createCipheriv('aes-256-gcm',key(),iv);const enc=Buffer.concat([c.update(value,'utf8'),c.final()]);const tag=c.getAuthTag();return `v1.${iv.toString('base64url')}.${tag.toString('base64url')}.${enc.toString('base64url')}`;}
export function decryptSensitive(value:string):string{const [v,ivs,tags,es]=value.split('.');if(v!=='v1'||!ivs||!tags||!es)throw new Error('Invalid encrypted value');const d=createDecipheriv('aes-256-gcm',key(),Buffer.from(ivs,'base64url'));d.setAuthTag(Buffer.from(tags,'base64url'));return Buffer.concat([d.update(Buffer.from(es,'base64url')),d.final()]).toString('utf8');}
