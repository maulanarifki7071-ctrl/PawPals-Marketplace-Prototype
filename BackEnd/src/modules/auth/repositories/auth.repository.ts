export async function findAccountByPhone(tx: any, phone: string) {
  return (await tx.query(`SELECT id,status,phone_e164,display_name,phone_verified_at FROM accounts WHERE phone_e164=$1`, [phone])).rows[0] ?? null;
}

export async function findCredential(tx: any, accountId: string) {
  return (await tx.query(`SELECT password_hash,password_algorithm FROM account_credentials WHERE account_id=$1`, [accountId])).rows[0] ?? null;
}
