import {AppError} from '../errors/app-error';

/**
 * Provider-neutral disbursement gateway. Adapter contract: POST /recipients/verify
 * {bank_code,account_name,account_number} -> {verified,recipient_id}; POST
 * /payouts {reference,recipient_id,amount,currency} -> {reference,status};
 * GET /payouts/:reference -> {reference,status}. Provider MUST honor Idempotency-Key.
 * Do not enable until a concrete provider has been validated against this contract.
 */
function settings(){
 const base=process.env.DISBURSEMENT_API_URL,token=process.env.DISBURSEMENT_API_TOKEN,provider=process.env.DISBURSEMENT_PROVIDER;
 if(!base||!token||!provider)throw new AppError(503,'DISBURSEMENT_PROVIDER_UNAVAILABLE','Disbursement provider is not configured.');
 if(provider.length>50)throw new AppError(503,'DISBURSEMENT_PROVIDER_UNAVAILABLE','Invalid provider name.');
 const url=new URL(base);
 if(url.protocol!=='https:'&&!(process.env.NODE_ENV!=='production'&&['localhost','127.0.0.1'].includes(url.hostname)))throw new AppError(503,'DISBURSEMENT_PROVIDER_UNAVAILABLE','Disbursement endpoint requires HTTPS.');
 return {url:url.toString().replace(/\/$/,''),token,provider};
}
export function isDisbursementConfigured():boolean{return !!(process.env.DISBURSEMENT_API_URL&&process.env.DISBURSEMENT_API_TOKEN&&process.env.DISBURSEMENT_PROVIDER);}
async function call(method:'GET'|'POST',path:string,body?:any,key?:string):Promise<any>{
 const s=settings(),abort=new AbortController(),timer=setTimeout(()=>abort.abort(),10000);
 try{
  const r=await fetch(`${s.url}${path}`,{method,headers:{authorization:`Bearer ${s.token}`,'content-type':'application/json',...(key?{'Idempotency-Key':key}:{})},body:body?JSON.stringify(body):undefined,signal:abort.signal});
  if(!r.ok)throw new AppError(503,'DISBURSEMENT_PROVIDER_UNAVAILABLE',`Disbursement provider returned HTTP ${r.status}.`);
  return r.json();
 }catch(e){if(e instanceof AppError)throw e;throw new AppError(503,'DISBURSEMENT_PROVIDER_UNAVAILABLE','Disbursement provider is temporarily unavailable.');}
 finally{clearTimeout(timer);}
}
export async function verifyDisbursementRecipient(input:{id:string;bank_code:string;account_holder_name:string;account_number:string}){
 const r=await call('POST','/recipients/verify',{bank_code:input.bank_code,account_name:input.account_holder_name,account_number:input.account_number},`recipient:${input.id}`);
 if(r.verified===true&&typeof r.recipient_id==='string'&&r.recipient_id.length>0)return {verified:true,ref:r.recipient_id};
 return {verified:false,ref:null};
}
export type PayoutResult='PROCESSING'|'PAID'|'FAILED';
function parse(r:any,expected:string):{status:PayoutResult;reference:string}{
 if(typeof r?.reference!=='string'||r.reference!==expected)throw new AppError(502,'DISBURSEMENT_PROVIDER_MISMATCH','Disbursement reference did not match.');
 const status=String(r.status??'').toUpperCase();
 if(!['PROCESSING','PAID','FAILED'].includes(status))throw new AppError(502,'DISBURSEMENT_PROVIDER_AMBIGUOUS','Unknown disbursement status.');
 return {reference:expected,status:status as PayoutResult};
}
export async function submitDisbursement(input:{id:string;recipientRef:string;amount:number}){
 const r=await call('POST','/payouts',{reference:input.id,recipient_id:input.recipientRef,amount:input.amount,currency:'IDR'},`payout:${input.id}`);
 return parse(r,input.id);
}
export async function fetchDisbursementStatus(id:string){return parse(await call('GET',`/payouts/${encodeURIComponent(id)}`),id);}
export function disbursementProviderName(){return settings().provider;}
