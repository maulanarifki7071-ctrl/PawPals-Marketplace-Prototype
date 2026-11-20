import { env } from '../../../config/env';

export const AUTH_CONFIG = Object.freeze({
  sessionCookie: 'pawpals_session',
  reauthCookie: 'pawpals_reauth',
  sensitiveCookie: 'pawpals_sensitive',
  sessionPath: '/api/v1',
  sessionSameSite: 'lax' as const,
  sessionSecure: env.nodeEnv === 'production',
  sessionTtlHours: env.sessionTtlHours,
  otpTtlMinutes: env.otpTtlMinutes,
  otpMaxAttempts: env.otpMaxAttempts,
  otpResendCooldownSeconds: env.otpResendCooldownSeconds,
  resetGrantTtlMinutes: env.resetGrantTtlMinutes,
  reauthGrantTtlMinutes: env.reauthGrantTtlMinutes,
  sensitiveGrantTtlMinutes: env.sensitiveGrantTtlMinutes,
});
