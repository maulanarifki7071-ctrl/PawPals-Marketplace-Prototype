export interface AppEnv {
  nodeEnv: 'development'|'test'|'production'; port:number; databaseUrl:string; tokenSecret:string; dataEncryptionKey:string;
  sessionTtlHours:number; otpTtlMinutes:number; otpMaxAttempts:number; otpResendCooldownSeconds:number;
  resetGrantTtlMinutes:number; reauthGrantTtlMinutes:number; sensitiveGrantTtlMinutes:number;
  paymentHoldMinutes:number; settlementHoldMinutes:number; cancellationClaimWindowMinutes:number; customerSelfRescheduleMinNoticeMinutes:number;
  commissionRateBps:number; minimumPayoutAmount:number; devOtpCode:string|undefined;
  midtransServerKey:string|undefined; midtransBaseUrl:string; mockPaymentsEnabled:boolean;
}
const n=(v:any,d:number)=>{const x=Number(v??d);if(!Number.isFinite(x)||x<0)throw new Error(`Invalid numeric environment value: ${v}`);return x};
const nodeEnv:AppEnv['nodeEnv']=process.env.NODE_ENV==='production'?'production':process.env.NODE_ENV==='test'?'test':'development';
// The mock provider is explicitly opt-in and MUST NEVER start in production.
const requestedMockPayments=process.env.PAWPALS_ENABLE_MOCK_PAYMENTS==='true';
if(nodeEnv==='production'&&requestedMockPayments)throw new Error('PAWPALS_ENABLE_MOCK_PAYMENTS is forbidden in production.');
if(nodeEnv==='production'&&!process.env.DATABASE_URL)throw new Error('DATABASE_URL must be explicitly configured in production.');
const port=n(process.env.PORT,3000); if(port<1||port>65535) throw new Error('PORT must be 1..65535');
const tokenSecret=process.env.APP_TOKEN_SECRET ?? (nodeEnv==='production'?'': 'pawpals-development-token-secret-change-me');
const dataEncryptionKey=process.env.DATA_ENCRYPTION_KEY ?? (nodeEnv==='production'?'':'pawpals-development-encryption-key-change-me');
if(!tokenSecret||tokenSecret.length<24) throw new Error('APP_TOKEN_SECRET must be configured (>=24 chars).');
if(!dataEncryptionKey||dataEncryptionKey.length<24) throw new Error('DATA_ENCRYPTION_KEY must be configured (>=24 chars).');
export const env:AppEnv=Object.freeze({nodeEnv,port,databaseUrl:process.env.DATABASE_URL??'postgresql://postgres:postgres@localhost:5432/pawpals_test',tokenSecret,dataEncryptionKey,
 sessionTtlHours:n(process.env.SESSION_TTL_HOURS,168),otpTtlMinutes:n(process.env.OTP_TTL_MINUTES,10),otpMaxAttempts:n(process.env.OTP_MAX_ATTEMPTS,5),otpResendCooldownSeconds:n(process.env.OTP_RESEND_COOLDOWN_SECONDS,60),
 resetGrantTtlMinutes:n(process.env.RESET_GRANT_TTL_MINUTES,10),reauthGrantTtlMinutes:n(process.env.REAUTH_GRANT_TTL_MINUTES,10),sensitiveGrantTtlMinutes:n(process.env.SENSITIVE_GRANT_TTL_MINUTES,10),
 paymentHoldMinutes:n(process.env.PAYMENT_HOLD_MINUTES,15),settlementHoldMinutes:n(process.env.SETTLEMENT_HOLD_MINUTES,1440),cancellationClaimWindowMinutes:n(process.env.CANCELLATION_CLAIM_WINDOW_MINUTES,1440),customerSelfRescheduleMinNoticeMinutes:n(process.env.CUSTOMER_SELF_RESCHEDULE_MIN_NOTICE_MINUTES,1440),commissionRateBps:n(process.env.COMMISSION_RATE_BPS,500),minimumPayoutAmount:n(process.env.MINIMUM_PAYOUT_AMOUNT,50000),
 devOtpCode:nodeEnv==='production'?undefined:(process.env.DEV_OTP_CODE??'123456'),midtransServerKey:process.env.MIDTRANS_SERVER_KEY,midtransBaseUrl:process.env.MIDTRANS_BASE_URL??'https://api.sandbox.midtrans.com',mockPaymentsEnabled:requestedMockPayments&&nodeEnv!=='production'});
