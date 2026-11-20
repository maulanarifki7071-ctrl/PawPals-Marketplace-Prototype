import { AUTH_CONFIG } from '../config/auth.config';

export async function createOtpChallenge(tx: any, accountId: string, purpose: string) {
  await tx.query(
    `UPDATE otp_challenges SET status='CANCELLED'
     WHERE account_id=$1 AND purpose=$2 AND status='PENDING'`,
    [accountId, purpose],
  );

  const result = await tx.query(
    `INSERT INTO otp_challenges(account_id,purpose,max_attempts,expires_at)
     VALUES($1,$2,$3,now()+($4||' minutes')::interval)
     RETURNING id,expires_at,purpose`,
    [accountId, purpose, AUTH_CONFIG.otpMaxAttempts, String(AUTH_CONFIG.otpTtlMinutes)],
  );

  return result.rows[0];
}
