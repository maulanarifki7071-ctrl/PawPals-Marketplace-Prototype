/**
 * AC-01 async boundary.
 * OTP delivery is intentionally delegated to the shared VerificationProvider.
 * No business state is changed by a delivery worker; the account/OTP lifecycle
 * remains authoritative in PostgreSQL transactions.
 */
export const AUTH_JOB_NAMES = Object.freeze({
  OTP_DELIVERY: 'auth.otp.delivery',
});
