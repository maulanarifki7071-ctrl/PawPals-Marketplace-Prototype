import { AppError } from '../../../shared/errors/app-error';
import { verifyOtpCode, verifyOtpForChallenge } from '../../../shared/providers/verification';

export const PUBLIC_OTP_PURPOSES = Object.freeze([
  'PHONE_VERIFICATION',
  'PASSWORD_RESET',
]);

export const SENSITIVE_OTP_PURPOSES = Object.freeze([
  'PAYOUT_ACCOUNT_CHANGE',
  'SENSITIVE_PROFILE_CHANGE',
]);

export function assertSensitiveOtpPurpose(purpose: string): void {
  if (!SENSITIVE_OTP_PURPOSES.includes(purpose as never)) {
    throw new AppError(422, 'OTP_PURPOSE_MISMATCH', 'OTP purpose is not valid for sensitive authentication.');
  }
}

export function assertPublicOtpPurpose(purpose: string): void {
  if (!PUBLIC_OTP_PURPOSES.includes(purpose as never)) {
    throw new AppError(422, 'OTP_PURPOSE_MISMATCH', 'OTP purpose is not valid for public OTP verification.');
  }
}

export function verifyCode(code: string): boolean {
  return verifyOtpCode(code);
}

/** Caller must lock the challenge and commit this result before raising its error.
 * Database failures still throw and roll back normally.
 */
export async function checkOtpAttempt(tx: any, challenge: any, code: string): Promise<AppError | null> {
  if (challenge.status === 'VERIFIED') {
    return new AppError(422, 'OTP_ALREADY_USED', 'OTP challenge has already been verified.');
  }
  if (challenge.status === 'LOCKED') {
    return new AppError(422, 'OTP_LOCKED', 'OTP challenge is locked.');
  }
  if (challenge.status !== 'PENDING' || new Date(challenge.expires_at).getTime() <= Date.now()) {
    if (challenge.status === 'PENDING') {
      await tx.query(`UPDATE otp_challenges SET status='EXPIRED' WHERE id=$1`, [challenge.id]);
    }
    return new AppError(422, 'OTP_EXPIRED', 'OTP challenge has expired.');
  }
  if (Number(challenge.attempt_count) >= Number(challenge.max_attempts)) {
    await tx.query(`UPDATE otp_challenges SET status='LOCKED' WHERE id=$1`, [challenge.id]);
    return new AppError(422, 'OTP_LOCKED', 'OTP challenge is locked.');
  }
  if (!(await verifyOtpForChallenge(tx, challenge, code))) {
    const next = Number(challenge.attempt_count) + 1;
    await tx.query(
      `UPDATE otp_challenges SET attempt_count=$2,
       status=CASE WHEN $2>=max_attempts THEN 'LOCKED'::otp_status ELSE status END WHERE id=$1`,
      [challenge.id, next],
    );
    const locked = next >= Number(challenge.max_attempts);
    return new AppError(422, locked ? 'OTP_LOCKED' : 'OTP_INVALID',
      locked ? 'OTP challenge is locked.' : 'OTP code is invalid.');
  }
  return null;
}

/** Consume within the same transaction as the protected business change. */
export async function consumeSensitiveOtp(tx: any, challengeId: string, accountId: string, purpose: string) {
  const result = await tx.query(
    `UPDATE otp_challenges SET consumed_at=now()
     WHERE id=$1 AND account_id=$2 AND purpose=$3 AND status='VERIFIED'
       AND consumed_at IS NULL RETURNING id`,
    [challengeId, accountId, purpose],
  );
  if (!result.rows[0]) {
    throw new AppError(403, 'STEP_UP_REQUIRED', 'Sensitive authorization is invalid or already consumed.');
  }
}
