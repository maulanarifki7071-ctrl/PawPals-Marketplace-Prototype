'use strict';
// PawPals local-only test: requeue an already acknowledged event.
// Never alters outbox_events or outbox_consumptions directly.
require('dotenv/config');
const { randomUUID } = require('node:crypto');
const { Pool } = require('pg');
const { Queue, QueueEvents } = require('bullmq');
const Redis = require('ioredis');

async function main() {
  if (!process.env.DATABASE_URL || !process.env.REDIS_URL) {
    throw new Error('DATABASE_URL dan REDIS_URL harus diisi dalam .env');
  }

  const db = new Pool({ connectionString: process.env.DATABASE_URL });
  const redis = new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null });
  const eventRedis = new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null });
  const queue = new Queue('pawpals-domain-events', { connection: redis });
  const queueEvents = new QueueEvents('pawpals-domain-events', { connection: eventRedis });

  try {
    const getSnapshot = async () => {
      const result = await db.query(`
        SELECT e.event_key, e.attempt_count, c.processed_at,
               (SELECT count(*)::int FROM outbox_consumptions c2
                WHERE c2.event_key=e.event_key) AS acknowledgement_count
        FROM outbox_events e
        JOIN outbox_consumptions c ON c.event_key=e.event_key
        WHERE e.event_type='LOCAL_SMOKE_TEST_RETRY'
        ORDER BY c.processed_at DESC
        LIMIT 1
      `);
      return result.rows[0];
    };

    const before = await getSnapshot();
    if (!before) throw new Error('Tidak ada LOCAL_SMOKE_TEST_RETRY yang sudah di-acknowledge.');
    if (before.acknowledgement_count !== 1) throw new Error('Jumlah acknowledgement awal bukan 1.');

    console.log('Event yang diuji:', before.event_key);
    console.log('Sebelum:', { attempts: before.attempt_count,
      acknowledgedAt: before.processed_at.toISOString(),
      acknowledgementCount: before.acknowledgement_count });

    await queueEvents.waitUntilReady();
    const job = await queue.add('LOCAL_SMOKE_TEST_RETRY',
      { event_key: before.event_key },
      { jobId: `duplicate-check-${randomUUID()}`, attempts: 1, removeOnComplete: false });

    console.log('Job duplikat dikirim:', job.id);
    await job.waitUntilFinished(queueEvents, 30000);
    const state = await job.getState();
    const after = await getSnapshot();
    if (!after || after.event_key !== before.event_key) throw new Error('Snapshot event berubah.');

    const unchanged = after.attempt_count === before.attempt_count &&
      after.processed_at.getTime() === before.processed_at.getTime() &&
      after.acknowledgement_count === before.acknowledgement_count;

    console.log('Sesudah:', { jobState: state, attempts: after.attempt_count,
      acknowledgedAt: after.processed_at.toISOString(),
      acknowledgementCount: after.acknowledgement_count });
    console.log(unchanged && state === 'completed'
      ? 'PASS: duplikat selesai tanpa mengubah acknowledgement/outbox.'
      : 'FAIL: terdapat perubahan atau job tidak completed.');
    if (!unchanged || state !== 'completed') process.exitCode = 1;
  } finally {
    await Promise.allSettled([
      queueEvents.close(), queue.close(),
      redis.quit(), eventRedis.quit(), db.end()
    ]);
  }
}

main().catch(err => { console.error('TEST FAILED:', err.message); process.exitCode = 1; });