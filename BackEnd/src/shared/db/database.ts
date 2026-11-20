// PostgreSQL remains authoritative. `pg` is intentionally loaded lazily so static tooling can run
// before dependencies are installed, while production still fails fast on first database use.
let pool: any;

function getPool(): any {
  if (pool) return pool;
  let Pg: any;
  try { Pg = require('pg'); } catch {
    throw new Error('PostgreSQL driver `pg` is required. Run `npm install` before starting PawPals.');
  }
  pool = new Pg.Pool({
    connectionString: process.env.DATABASE_URL,
    max: Number(process.env.DB_POOL_MAX ?? 10),
    idleTimeoutMillis: 30_000,
    statement_timeout: Number(process.env.DB_STATEMENT_TIMEOUT_MS ?? 15_000),
  });
  return pool;
}

export async function query<T = any>(text: string, params: any[] = []): Promise<{ rows:T[]; rowCount:number }> {
  const result = await getPool().query(text, params);
  return { rows: result.rows as T[], rowCount: result.rowCount ?? result.rows.length };
}

export async function transaction<T>(fn: (tx: any) => Promise<T>, isolation: 'READ COMMITTED'|'SERIALIZABLE'='READ COMMITTED'): Promise<T> {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    if (isolation === 'SERIALIZABLE') await client.query('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch { /* retain original error */ }
    throw error;
  } finally { client.release(); }
}

export async function closeDatabase(): Promise<void> { if (pool) { await pool.end(); pool = undefined; } }
