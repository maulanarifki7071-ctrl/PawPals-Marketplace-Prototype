import { query } from '../../../shared/db/database';

export async function findOwnedAccount(accountId: string) {
  const result = await query<any>(`SELECT * FROM accounts WHERE id=$1`, [accountId]);
  return result.rows[0] ?? null;
}
