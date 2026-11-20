import {env} from '../../config/env';
import {AppError} from '../errors/app-error';
import {query} from '../db/database';

function serviceForPurpose(purpose:string):string|undefined{
 if(!['PHONE_VERIFICATION','PASSWORD_RESET','PAYOUT_ACCOUNT_CHANGE','SENSITIVE_PROFILE_CHANGE'].includes(purpose))return undefined;
 return process.env[`TWILIO_VERIFY_SERVICE_SID_${purpose}`];
}
function twilioSettings(purpose:string){
 const sid=process.env.TWILIO_ACCOUNT_SID,token=process.env.TWILIO_AUTH_TOKEN,service=serviceForPurpose(purpose);
 if(!sid||!token||!service)throw new AppError(503,'OTP_DELIVERY_UNAVAILABLE','OTP provider is not configured.');
 return {sid,token,service};
}
async function twilioForm(purpose:string,path:string,body:Record<string,string>):Promise<any>{
 const {sid,token,service}=twilioSettings(purpose);
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),10000);
 try{
  const r=await fetch(`https://verify.twilio.com/v2/Services/${encodeURIComponent(service)}/${path}`,{
   method:'POST',headers:{authorization:`Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`,'content-type':'application/x-www-form-urlencoded'},
   body:new URLSearchParams(body),signal:controller.signal,
  });
  if(!r.ok){if(path==='VerificationCheck'&&r.status===404)return {status:'pending',valid:false};throw new AppError(503,'OTP_PROVIDER_UNAVAILABLE',`OTP provider error (${r.status}).`);}
  return await r.json();
 }catch(err){if(err instanceof AppError)throw err;throw new AppError(503,'OTP_PROVIDER_UNAVAILABLE','OTP provider is temporarily unavailable.');}
 finally{clearTimeout(timeout);}
}
export async function sendOtp(challengeId:string,accountId:string,channel:'WHATSAPP'|'SMS'='WHATSAPP'):Promise<void>{
 const cr=(await query<any>(`SELECT c.purpose,a.phone_e164 FROM otp_challenges c JOIN accounts a ON a.id=c.account_id
  WHERE c.id=$1 AND c.account_id=$2`,[challengeId,accountId])).rows[0];
 if(!cr)throw new AppError(422,'OTP_INVALID','OTP challenge is invalid.');
 if(!serviceForPurpose(cr.purpose)){
  if(env.nodeEnv==='production')throw new AppError(503,'OTP_DELIVERY_UNAVAILABLE','Purpose-bound OTP provider is not configured.');
  await query(`INSERT INTO otp_delivery_attempts(otp_challenge_id,channel,provider,status,sent_at) VALUES($1,$2,'DEV_PROVIDER','SENT',now())`,[challengeId,channel]);return;
 }
 const send=async(ch:'WHATSAPP'|'SMS')=>{
  const r=await twilioForm(cr.purpose,'Verifications',{To:cr.phone_e164,Channel:ch==='WHATSAPP'?'whatsapp':'sms'});
  await query(`INSERT INTO otp_delivery_attempts(otp_challenge_id,channel,provider,provider_reference,status,sent_at)
    VALUES($1,$2,'TWILIO_VERIFY',$3,'SENT',now())`,[challengeId,ch,r.sid??null]);
 };
 try{await send(channel);}catch(err){
  await query(`INSERT INTO otp_delivery_attempts(otp_challenge_id,channel,provider,status,failed_at)
    VALUES($1,$2,'TWILIO_VERIFY','FAILED',now())`,[challengeId,channel]);
  if(channel!=='WHATSAPP')throw err;
  await send('SMS');
 }
}
export function verifyOtpCode(code:string):boolean{return env.devOtpCode!==undefined&&code===env.devOtpCode;}
export async function verifyOtpForChallenge(tx:any,challenge:any,code:string):Promise<boolean>{
 if(!serviceForPurpose(challenge.purpose)){
  if(env.nodeEnv==='production')throw new AppError(503,'OTP_PROVIDER_UNAVAILABLE','OTP verification is not configured.');
  return verifyOtpCode(code);
 }
 const acct=(await tx.query(`SELECT phone_e164 FROM accounts WHERE id=$1`,[challenge.account_id])).rows[0];
 if(!acct)throw new AppError(422,'OTP_INVALID','OTP challenge is invalid.');
 const r=await twilioForm(challenge.purpose,'VerificationCheck',{To:acct.phone_e164,Code:code});
 return r.status==='approved'&&r.valid===true;
}
