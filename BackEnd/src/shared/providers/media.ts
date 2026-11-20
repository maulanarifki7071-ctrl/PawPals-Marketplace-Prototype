import {createHmac,createHash} from 'node:crypto';
import {opaqueToken} from '../security/tokens';
import {AppError} from '../errors/app-error';
import {query} from '../db/database';

const mimeByClass:Record<string,string[]>={
 VERIFICATION_SENSITIVE:['image/jpeg','image/png','application/pdf'],
 PET_SENSITIVE:['image/jpeg','image/png','image/webp'],
 BOOKING_PRIVATE:['image/jpeg','image/png','image/webp'],
 INCIDENT_RESTRICTED:['image/jpeg','image/png','application/pdf'],
};
function sha(s:string){return createHash('sha256').update(s).digest('hex');}
function hmac(key:any,input:string){return createHmac('sha256',key).update(input).digest();}
function storage(){
 const endpoint=process.env.MEDIA_S3_ENDPOINT,bucket=process.env.MEDIA_S3_BUCKET,region=process.env.MEDIA_S3_REGION||'ap-southeast-1',access=process.env.MEDIA_S3_ACCESS_KEY_ID,secret=process.env.MEDIA_S3_SECRET_ACCESS_KEY;
 if(!endpoint||!bucket||!access||!secret)throw new AppError(503,'MEDIA_STORAGE_UNAVAILABLE','Private object storage is not configured.');
 const uri=new URL(endpoint);if(uri.protocol!=='https:'&&!(process.env.NODE_ENV!=='production'&&['localhost','127.0.0.1'].includes(uri.hostname)))throw new AppError(503,'MEDIA_STORAGE_UNAVAILABLE','Storage endpoint must use HTTPS.');
 if(!/^[a-zA-Z0-9._-]+$/.test(bucket))throw new AppError(503,'MEDIA_STORAGE_UNAVAILABLE','Invalid bucket configuration.');
 return {uri,bucket,region,access,secret};
}
/** S3-compatible AWS Signature V4 pre-signed URL, with private object keys. */
export function signS3Url(method:'PUT'|'HEAD'|'GET',key:string,expires=600,contentType?:string):string{
 const c=storage(),dt=new Date(),stamp=dt.toISOString().replace(/[-:]|\.\d{3}/g,''),day=stamp.slice(0,8),scope=`${day}/${c.region}/s3/aws4_request`;
 const encoded=(x:string)=>encodeURIComponent(x).replace(/[!'()*]/g,char=>`%${char.charCodeAt(0).toString(16).toUpperCase()}`);
 const basePath=c.uri.pathname.replace(/\/$/,'');
 const path=`${basePath}/${encoded(c.bucket)}/${key.split('/').map(encoded).join('/')}`;
 const host=c.uri.host;
 const headers=contentType?`content-type:${contentType}\nhost:${host}\n`:`host:${host}\n`;
 const signed=contentType?'content-type;host':'host';
 const params=new URLSearchParams({'X-Amz-Algorithm':'AWS4-HMAC-SHA256','X-Amz-Credential':`${c.access}/${scope}`,'X-Amz-Date':stamp,'X-Amz-Expires':String(expires),'X-Amz-SignedHeaders':signed});
 const sorted=Array.from(params.entries()).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>`${encoded(k)}=${encoded(v)}`).join('&');
 const canonical=[method,path,sorted,headers,signed,'UNSIGNED-PAYLOAD'].join('\n');
 const keyBytes=hmac(hmac(hmac(hmac(`AWS4${c.secret}`,day),c.region),'s3'),'aws4_request');
 const sig=createHmac('sha256',keyBytes).update(`AWS4-HMAC-SHA256\n${stamp}\n${scope}\n${sha(canonical)}`).digest('hex');
 return `${c.uri.origin}${path}?${sorted}&X-Amz-Signature=${sig}`;
}
export async function uploadIntent(input:{accountId:string;dataClass:string;contentType:string;fileName?:string}){
 if(!mimeByClass[input.dataClass]?.includes(input.contentType))throw new AppError(400,'MEDIA_TYPE_UNSUPPORTED','Unsupported media type for this data class.');
 storage(); // Never issue a fake upload URL and falsely imply the object exists.
 const objectKey=`private/${input.dataClass.toLowerCase()}/${input.accountId}/${opaqueToken(18)}`;
 const r=await query<any>(`INSERT INTO media_objects(uploaded_by_account_id,data_class,storage_provider,object_key,mime_type)
 VALUES($1,$2,'S3',$3,$4) RETURNING id`,[input.accountId,input.dataClass,objectKey,input.contentType]);
 return {media_object_id:r.rows[0].id,upload_url:signS3Url('PUT',objectKey,600,input.contentType),expires_in_seconds:600,method:'PUT',headers:{'content-type':input.contentType}};
}
export async function assertMedia(mediaId:string,accountId:string,expectedClass:string):Promise<any>{
 const r=await query<any>(`SELECT id,data_class,mime_type,object_key FROM media_objects
 WHERE id=$1 AND uploaded_by_account_id=$2 AND deleted_at IS NULL`,[mediaId,accountId]);
 const row=r.rows[0];if(!row||row.data_class!==expectedClass)throw new AppError(404,'MEDIA_NOT_FOUND','Media object not found.');
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),10000);
 try{
  const response=await fetch(signS3Url('HEAD',row.object_key,60),{method:'HEAD',signal:controller.signal});
  if(response.status===404)throw new AppError(409,'MEDIA_UPLOAD_INCOMPLETE','Media upload has not completed.');
  if(!response.ok)throw new AppError(503,'MEDIA_STORAGE_UNAVAILABLE','Media storage could not verify the object.');
  const size=Number(response.headers.get('content-length'));
  const mime=response.headers.get('content-type')?.split(';')[0].trim();
  if(!mimeByClass[expectedClass]?.includes(mime??'')||mime!==row.mime_type||!Number.isSafeInteger(size)||size<=0||size>10*1024*1024)throw new AppError(422,'MEDIA_UPLOAD_INVALID','Object content type or size violates upload policy.');
  await query(`UPDATE media_objects SET size_bytes=$2 WHERE id=$1`,[row.id,size]);
  return {id:row.id,data_class:row.data_class,mime_type:row.mime_type,size_bytes:size};
 }catch(err){if(err instanceof AppError)throw err;throw new AppError(503,'MEDIA_STORAGE_UNAVAILABLE','Could not verify the media object.');}
 finally{clearTimeout(timeout);}
}
