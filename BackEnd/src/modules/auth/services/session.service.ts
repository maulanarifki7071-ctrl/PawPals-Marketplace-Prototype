import { opaqueToken, tokenHash } from '../../../shared/security/tokens';
import { AUTH_CONFIG } from '../config/auth.config';

export function sessionCookieOptions() {
  return {
    httpOnly: true,
    sameSite: AUTH_CONFIG.sessionSameSite,
    secure: AUTH_CONFIG.sessionSecure,
    path: AUTH_CONFIG.sessionPath,
  } as const;
}

export async function createAuthSession(tx: any, accountId: string, req: any) {
  const token = opaqueToken();
  const result = await tx.query(
    `INSERT INTO auth_sessions
      (account_id,session_token_hash,ip_address,user_agent,expires_at,last_seen_at)
     VALUES($1,$2,$3,$4,now()+($5||' hours')::interval,now())
     RETURNING id,expires_at`,
    [accountId, tokenHash(token), req.ip ?? null, req.get('user-agent') ?? null, String(AUTH_CONFIG.sessionTtlHours)],
  );
  return { token, ...result.rows[0] };
}
