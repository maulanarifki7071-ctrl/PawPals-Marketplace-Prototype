import express from 'express';
import { asyncHandler } from '../../shared/http/async-handler';
import { ok,noContent } from '../../shared/http/respond';
import { bodyObject,e164,requireString,requireEnum,requireUuid } from '../../shared/http/validate';
import { AppError } from '../../shared/errors/app-error';
import { query,transaction } from '../../shared/db/database';
import { hashPassword,verifyPassword } from '../../shared/security/password';
import { signGrant,verifyGrant } from '../../shared/security/tokens';
import { env } from '../../config/env';
import { sendOtp } from '../../shared/providers/verification';
import { requireAuth,requireActive } from '../../middleware/auth';
import { audit,outbox } from '../../shared/domain/audit';
import { enforceRateLimit } from '../../shared/security/rate-limit';
import { createAuthSession, sessionCookieOptions } from './services/session.service';
import { createOtpChallenge } from './services/otp.service';
import { assertPublicOtpPurpose, assertSensitiveOtpPurpose, checkOtpAttempt } from './verification/otp.verification';

export const authRouter=express.Router();

// AC-01 — Auth & Account
// CONTRACT: POST /auth/register
// CONTRACT: Account + credential are persisted before OTP delivery; provider failure keeps account pending.
authRouter.post('/auth/register',asyncHandler(async(req,res)=>{const b=bodyObject(req.body);const phone=e164(b.phone_e164);await enforceRateLimit(`register:${req.ip??'unknown'}:${phone}`,5,3600);const display=requireString(b,'display_name',1,150);const password=requireString(b,'password',10,128);let hash:string;try{hash=await hashPassword(password);}catch{throw new AppError(400,'VALIDATION_ERROR','Password does not satisfy password policy.');}
 const result=await transaction(async tx=>{const exists=await tx.query(`SELECT id,status FROM accounts WHERE phone_e164=$1`,[phone]);if(exists.rows[0])throw new AppError(409,'PHONE_ALREADY_REGISTERED','Phone number is already registered.');const a=await tx.query(`INSERT INTO accounts(phone_e164,display_name) VALUES($1,$2) RETURNING id,phone_e164,display_name,status,created_at`,[phone,display]);await tx.query(`INSERT INTO account_credentials(account_id,password_hash,password_algorithm,password_updated_at) VALUES($1,$2,'scrypt',now())`,[a.rows[0].id,hash]);const c=await createOtpChallenge(tx,a.rows[0].id,'PHONE_VERIFICATION');return {account:a.rows[0],challenge:c};});
 await sendOtp(result.challenge.id,result.account.id,'WHATSAPP');ok(res,{account:result.account,challenge_id:result.challenge.id,expires_at:result.challenge.expires_at},201);}));

authRouter.post('/auth/otp/verify', asyncHandler(async (req, res) => {
  const body = bodyObject(req.body);
  await enforceRateLimit(`otp-verify:${req.ip ?? 'unknown'}`, 30, 900);
  const challengeId = requireUuid(body.challenge_id, 'challenge_id');
  const code = requireString(body, 'code', 4, 12);
  const result = await transaction(async tx => {
    const row = await tx.query(
      `SELECT c.*,a.status account_status FROM otp_challenges c
       JOIN accounts a ON a.id=c.account_id WHERE c.id=$1 FOR UPDATE`, [challengeId],
    );
    const challenge = row.rows[0];
    if (!challenge) throw new AppError(422, 'OTP_INVALID', 'OTP challenge is invalid.');
    assertPublicOtpPurpose(challenge.purpose);
    const error = await checkOtpAttempt(tx, challenge, code);
    if (error) return { error };
    await tx.query(`UPDATE otp_challenges SET status='VERIFIED',verified_at=now() WHERE id=$1`, [challenge.id]);
    if (challenge.purpose === 'PHONE_VERIFICATION') {
      const account = await tx.query(
        `UPDATE accounts SET status='ACTIVE',phone_verified_at=COALESCE(phone_verified_at,now()),updated_at=now()
         WHERE id=$1 AND status='PENDING_PHONE_VERIFICATION'
         RETURNING id,phone_e164,display_name,status,phone_verified_at`, [challenge.account_id],
      );
      if (!account.rows[0]) throw new AppError(409, 'STATE_CONFLICT', 'Account cannot be activated from its current state.');
      const session = await createAuthSession(tx, challenge.account_id, req);
      await audit(tx, { actorId: challenge.account_id, action: 'ACCOUNT_PHONE_VERIFIED', targetType: 'ACCOUNT', targetId: challenge.account_id });
      return { data: { purpose: challenge.purpose, account: account.rows[0], authenticated: true }, session };
    }
    return { data: { purpose: challenge.purpose, reset_authorization: signGrant(
      { typ: 'password_reset', sub: challenge.account_id, cid: challenge.id }, env.resetGrantTtlMinutes * 60,
    ) } };
  });
  // Expected verification failures must be reported AFTER the attempt/expiry commits.
  if (result.error) throw result.error;
  if (result.session) res.cookie('pawpals_session', result.session.token,
    { ...sessionCookieOptions(), maxAge: env.sessionTtlHours * 3600 * 1000 });
  ok(res, result.data);
}));

authRouter.post('/auth/otp/resend',asyncHandler(async(req,res)=>{const b=bodyObject(req.body);await enforceRateLimit(`otp-resend:${req.ip??'unknown'}`,20,3600);const id=requireUuid(b.challenge_id,'challenge_id');const old=await query<any>(`SELECT * FROM otp_challenges WHERE id=$1`,[id]);if(!old.rows[0])throw new AppError(422,'OTP_INVALID','OTP challenge is invalid.');const c=old.rows[0];assertPublicOtpPurpose(c.purpose);await enforceRateLimit(`otp-resend-account:${c.account_id}`,5,3600);if(c.status!=='PENDING')throw new AppError(422,c.status==='VERIFIED'?'OTP_ALREADY_USED':c.status==='LOCKED'?'OTP_LOCKED':'OTP_EXPIRED','OTP challenge cannot be resent from its current state.');const age=(Date.now()-new Date(c.created_at).getTime())/1000;if(age<env.otpResendCooldownSeconds)throw new AppError(429,'OTP_RESEND_TOO_SOON','OTP resend requested too soon.');const next=await transaction(tx=>createOtpChallenge(tx,c.account_id,c.purpose));await sendOtp(next.id,c.account_id,'WHATSAPP');ok(res,{challenge_id:next.id,expires_at:next.expires_at},202);}));

authRouter.post('/auth/login',asyncHandler(async(req,res)=>{const b=bodyObject(req.body);const phone=e164(b.phone_e164);await enforceRateLimit(`login:${req.ip??'unknown'}:${phone}`,10,900);const password=requireString(b,'password');const q=await query<any>(`SELECT a.*,c.password_hash FROM accounts a JOIN account_credentials c ON c.account_id=a.id WHERE a.phone_e164=$1`,[phone]);const a=q.rows[0];if(!a||!(await verifyPassword(password,a.password_hash)))throw new AppError(401,'INVALID_CREDENTIALS','Invalid phone number or password.');if(a.status==='PENDING_PHONE_VERIFICATION')throw new AppError(403,'PHONE_VERIFICATION_REQUIRED','Phone verification required.');if(a.status==='DISABLED')throw new AppError(403,'ACCOUNT_DISABLED','Account is disabled.');const s=await transaction(tx=>createAuthSession(tx,a.id,req));res.cookie('pawpals_session',s.token,{...sessionCookieOptions(),maxAge:env.sessionTtlHours*3600*1000});ok(res,{account:{id:a.id,phone_e164:a.phone_e164,display_name:a.display_name,status:a.status,phone_verified_at:a.phone_verified_at}});}));

authRouter.post('/auth/logout',requireAuth,asyncHandler(async(req,res)=>{await query(`UPDATE auth_sessions SET status='REVOKED',revoked_at=now() WHERE id=$1 AND status='ACTIVE'`,[req.session.id]);res.clearCookie('pawpals_session',sessionCookieOptions());noContent(res);}));


authRouter.post('/auth/password/forgot',asyncHandler(async(req,res)=>{const b=bodyObject(req.body);let phone:string;try{phone=e164(b.phone_e164);await enforceRateLimit(`forgot:${req.ip??'unknown'}:${phone}`,5,3600);}catch{ok(res,{accepted:true},202);return;}const q=await query<any>(`SELECT id,status FROM accounts WHERE phone_e164=$1`,[phone]);if(q.rows[0]&&q.rows[0].status!=='DISABLED'){const c=await transaction(tx=>createOtpChallenge(tx,q.rows[0].id,'PASSWORD_RESET'));try{await sendOtp(c.id,q.rows[0].id,'WHATSAPP');}catch{/* generic response intentionally preserved */}}ok(res,{accepted:true},202);}));

authRouter.post('/auth/password/reset',asyncHandler(async(req,res)=>{const b=bodyObject(req.body);const token=requireString(b,'reset_authorization');const password=requireString(b,'new_password',10,128);const grant=verifyGrant(token,'password_reset');if(!grant)throw new AppError(422,'RESET_AUTHORIZATION_INVALID','Password reset authorization is invalid or expired.');let hash:string;try{hash=await hashPassword(password);}catch{throw new AppError(400,'VALIDATION_ERROR','Password does not satisfy password policy.');}await transaction(async tx=>{const c=await tx.query(`SELECT * FROM otp_challenges WHERE id=$1 AND account_id=$2 FOR UPDATE`,[grant.cid,grant.sub]);if(!c.rows[0]||c.rows[0].status!=='VERIFIED'||c.rows[0].purpose!=='PASSWORD_RESET'||c.rows[0].consumed_at)throw new AppError(422,'RESET_AUTHORIZATION_INVALID','Password reset authorization has already been consumed or is invalid.');await tx.query(`UPDATE account_credentials SET password_hash=$2,password_algorithm='scrypt',password_updated_at=now(),updated_at=now() WHERE account_id=$1`,[grant.sub,hash]);await tx.query(`UPDATE otp_challenges SET consumed_at=now() WHERE id=$1`,[grant.cid]);await tx.query(`UPDATE auth_sessions SET status='REVOKED',revoked_at=now() WHERE account_id=$1 AND status='ACTIVE'`,[grant.sub]);await audit(tx,{actorId:grant.sub,action:'PASSWORD_RESET',targetType:'ACCOUNT',targetId:grant.sub});});ok(res,{password_reset:true});}));

authRouter.post('/auth/reauth',requireActive,asyncHandler(async(req,res)=>{const b=bodyObject(req.body);const password=requireString(b,'password');const q=await query<any>(`SELECT password_hash FROM account_credentials WHERE account_id=$1`,[req.account.id]);if(!q.rows[0]||!(await verifyPassword(password,q.rows[0].password_hash)))throw new AppError(401,'INVALID_CREDENTIALS','Invalid credentials.');const grant=signGrant({typ:'reauth',sub:req.account.id},env.reauthGrantTtlMinutes*60);res.cookie('pawpals_reauth',grant,{...sessionCookieOptions(),maxAge:env.reauthGrantTtlMinutes*60*1000});ok(res,{reauth_authorization:grant,expires_in_seconds:env.reauthGrantTtlMinutes*60});}));

authRouter.post('/auth/sensitive-otp/request',requireActive,asyncHandler(async(req,res)=>{const b=bodyObject(req.body);await enforceRateLimit(`sensitive-otp:${req.account.id}`,5,3600);const purpose=requireEnum(b,'purpose',['PAYOUT_ACCOUNT_CHANGE','SENSITIVE_PROFILE_CHANGE']);const c=await transaction(tx=>createOtpChallenge(tx,req.account.id,purpose));await sendOtp(c.id,req.account.id,'WHATSAPP');ok(res,{challenge_id:c.id,purpose,expires_at:c.expires_at},202);}));

authRouter.post('/auth/sensitive-otp/verify', requireActive, asyncHandler(async (req, res) => {
  const body = bodyObject(req.body);
  await enforceRateLimit(`sensitive-otp-verify:${req.account.id}`, 30, 900);
  const id = requireUuid(body.challenge_id, 'challenge_id');
  const code = requireString(body, 'code', 4, 12);
  const purpose = requireEnum(body, 'purpose', ['PAYOUT_ACCOUNT_CHANGE', 'SENSITIVE_PROFILE_CHANGE']);
  assertSensitiveOtpPurpose(purpose);
  const result = await transaction(async tx => {
    const row = await tx.query(`SELECT * FROM otp_challenges WHERE id=$1 AND account_id=$2 FOR UPDATE`, [id, req.account.id]);
    const challenge = row.rows[0];
    if (!challenge || challenge.purpose !== purpose) throw new AppError(422, 'OTP_PURPOSE_MISMATCH', 'OTP purpose does not match.');
    const error = await checkOtpAttempt(tx, challenge, code);
    if (error) return { error };
    await tx.query(`UPDATE otp_challenges SET status='VERIFIED',verified_at=now() WHERE id=$1`, [challenge.id]);
    return { token: signGrant({ typ: 'sensitive', sub: req.account.id, cid: challenge.id, purpose }, env.sensitiveGrantTtlMinutes * 60) };
  });
  if (result.error) throw result.error;
  res.cookie('pawpals_sensitive', result.token, { ...sessionCookieOptions(), maxAge: env.sensitiveGrantTtlMinutes * 60 * 1000 });
  ok(res, { sensitive_authorization: result.token, purpose, expires_in_seconds: env.sensitiveGrantTtlMinutes * 60 });
}));
