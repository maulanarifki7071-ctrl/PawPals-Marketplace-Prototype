import { query } from '../../../shared/db/database';

export async function getCurrentAccount(accountId: string) {
  const result = await query<any>(
    `SELECT
       a.id,
       a.phone_e164,
       a.email,
       a.display_name,
       a.status,
       a.phone_verified_at,
       a.created_at,
       v.id AS vendor_id,
       v.status AS vendor_status
     FROM accounts a
     LEFT JOIN vendors v ON v.account_id = a.id
     WHERE a.id = $1`,
    [accountId],
  );
  return result.rows[0] ?? null;
}
