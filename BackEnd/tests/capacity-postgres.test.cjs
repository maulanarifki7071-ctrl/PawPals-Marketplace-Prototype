'use strict';
// PawPals PostgreSQL capacity regression test.
// Run ONLY on a disposable database with migrations 001-026 installed.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

const enabled = Boolean(process.env.PAWPALS_TEST_DATABASE_URL) &&
  process.env.PAWPALS_ALLOW_INTEGRATION_TESTS === 'yes';

test('PostgreSQL: valid slot succeeds; two competing last-slot bookings cannot overbook', {
  skip: !enabled && 'Needs dedicated PostgreSQL/PostGIS test DB and PAWPALS_ALLOW_INTEGRATION_TESTS=yes',
}, async () => {
  // Do not permit an accidental run against the primary PawPals database.
  const url = new URL(process.env.PAWPALS_TEST_DATABASE_URL);
  assert.equal(decodeURIComponent(url.pathname.slice(1)), 'pawpals_capacity_test',
    'Integration test must target the disposable pawpals_capacity_test database');

  const { Pool } = require('pg');
  const pool = new Pool({ connectionString: url.toString(), max: 4, statement_timeout: 10000 });
  const ids = {
    accounts: [randomUUID(), randomUUID(), randomUUID()], // vendor, customer A, customer B
    pets: [randomUUID(), randomUUID()],
    vendor: randomUUID(),
    loc: randomUUID(),
    svc: randomUUID(),
    pkg: randomUUID(),
    window: randomUUID(),
    bookings: [randomUUID(), randomUUID(), randomUUID()],
    items: [randomUUID(), randomUUID(), randomUUID()],
  };
  const tag = Math.floor(Math.random() * 1e9).toString().padStart(9, '0');
  const at = hour => `2031-01-15T${hour}:00:00+07:00`;
  let first, second;

  try {
    // Seed a valid vendor, two independent verified customers, and their pets.
    for (let i = 0; i < ids.accounts.length; i++) {
      await pool.query(
        `INSERT INTO accounts(id,phone_e164,display_name,status,phone_verified_at)
         VALUES($1,$2,$3,'ACTIVE',now())`,
        [ids.accounts[i], `+6289${tag}${i}`, `Capacity Test Account ${i}`],
      );
    }
    await pool.query(
      `INSERT INTO vendors(id,account_id,vendor_type,public_display_name,status,approved_at)
       VALUES($1,$2,'INDIVIDUAL','Capacity Test','ACTIVE',now())`,
      [ids.vendor, ids.accounts[0]],
    );
    await pool.query(
      `INSERT INTO vendor_locations(id,vendor_id,location_type,address_line1,latitude,longitude)
       VALUES($1,$2,'OPERATIONAL_PRIVATE','Test address',-6.2,106.8)`,
      [ids.loc, ids.vendor],
    );
    await pool.query(
      `INSERT INTO vendor_services(id,vendor_id,origin_vendor_location_id,category_code,name,
                                   delivery_mode,minimum_notice_minutes,buffer_after_minutes,
                                   base_capacity,status)
       VALUES($1,$2,$3,'TEST','Capacity Test','AT_VENDOR',0,0,1,'ACTIVE')`,
      [ids.svc, ids.vendor, ids.loc],
    );
    await pool.query(
      `INSERT INTO service_packages(id,vendor_service_id,name,duration_minutes,price_amount,is_active)
       VALUES($1,$2,'One hour',60,100000,true)`,
      [ids.pkg, ids.svc],
    );
    await pool.query(
      `INSERT INTO service_availability_windows(id,vendor_service_id,starts_at,ends_at)
       VALUES($1,$2,$3,$4)`,
      [ids.window, ids.svc, at('09'), at('17')],
    );
    for (let i = 0; i < ids.pets.length; i++) {
      await pool.query(
        `INSERT INTO pets(id,owner_account_id,name,species_code)
         VALUES($1,$2,$3,'DOG')`,
        [ids.pets[i], ids.accounts[i + 1], `Test Pet ${i}`],
      );
    }

    // The booking item MUST exist before its capacity reservation:
    // fk_capacity_booking_package -> booking_items(booking_id,service_package_id).
    for (let i = 0; i < ids.bookings.length; i++) {
      const hour = i === 0 ? '12' : '10';
      const next = i === 0 ? '13' : '11';
      const customer = i === 2 ? ids.accounts[2] : ids.accounts[1];
      const pet = i === 2 ? ids.pets[1] : ids.pets[0];
      await pool.query(
        `INSERT INTO bookings(id,customer_account_id,vendor_id,vendor_service_id,status,
                              scheduled_start_at,scheduled_end_at,occupied_end_at,total_amount)
         VALUES($1,$2,$3,$4,'CREATED',$5,$6,$6,100000)`,
        [ids.bookings[i], customer, ids.vendor, ids.svc, at(hour), at(next)],
      );
      await pool.query(
        `INSERT INTO booking_items(id,booking_id,pet_id,service_package_id,
                                   pet_snapshot_json,compatibility_snapshot_json,
                                   price_amount_snapshot,duration_minutes_snapshot,
                                   buffer_after_minutes_snapshot,minimum_notice_minutes_snapshot)
         VALUES($1,$2,$3,$4,'{}'::jsonb,'{}'::jsonb,100000,60,0,0)`,
        [ids.items[i], ids.bookings[i], pet, ids.pkg],
      );
    }

    const insertCapacity = (client, booking, hour, next) => client.query(
      `INSERT INTO capacity_reservations(booking_id,vendor_service_id,service_package_id,
                                         status,starts_at,service_ends_at,occupied_ends_at,expires_at)
       VALUES($1,$2,$3,'HELD',$4,$5,$5,now()+interval '15 minutes')`,
      [booking, ids.svc, ids.pkg, at(hour), at(next)],
    );

    // A non-overlapping slot must succeed, guarding against false positives.
    await insertCapacity(pool, ids.bookings[0], '12', '13');
    const validCount = await pool.query(
      `SELECT count(*)::int AS n FROM capacity_reservations WHERE booking_id=$1 AND status='HELD'`,
      [ids.bookings[0]],
    );
    assert.equal(validCount.rows[0].n, 1, 'valid non-overlapping slot must be accepted');

    // Two real database sessions simultaneously contend for capacity=1 at 10:00.
    first = await pool.connect();
    second = await pool.connect();
    await Promise.all([
      first.query('BEGIN ISOLATION LEVEL SERIALIZABLE'),
      second.query('BEGIN ISOLATION LEVEL SERIALIZABLE'),
    ]);
    await Promise.all([
      insertCapacity(first, ids.bookings[1], '10', '11'),
      insertCapacity(second, ids.bookings[2], '10', '11'),
    ]);
    const results = await Promise.allSettled([
      first.query('COMMIT'),
      second.query('COMMIT'),
    ]);
    // Always verify the database invariant before classifying the loser error.
    // Accepting a deadlock without proving the remaining capacity would
    // give a false positive on a marketplace-critical concurrency test.
    const count = await pool.query(
      `SELECT count(*)::int AS n FROM capacity_reservations
       WHERE vendor_service_id=$1 AND starts_at=$2 AND status='HELD'`,
      [ids.svc, at('10')],
    );
    const report = results.map((r, i) => r.status === 'fulfilled'
      ? { tx: i + 1, status: 'committed' }
      : { tx: i + 1, status: 'rejected', sqlstate: r.reason?.code, message: r.reason?.message });
    console.log('Capacity race outcome:', JSON.stringify({ transactions: report, activeHolds: count.rows[0].n }));
    assert.equal(count.rows[0].n, 1, 'there must be exactly one accepted hold; no overbooking');

    const accepted = results.filter(r => r.status === 'fulfilled');
    assert.equal(accepted.length, 1, 'two simultaneous last-slot bookings must have exactly one winner');
    const rejected = results.find(r => r.status === 'rejected');
    assert.ok(rejected, 'one concurrent booking must be rejected');
    assert.notEqual(rejected.reason?.code, '40P01',
      'Deadlock 40P01: apply migration 027_capacity_lock_deadlock_fix.sql and rerun.');
    assert.ok(
      rejected.reason?.code === '40001' ||
      String(rejected.reason?.message || '').includes('SLOT_UNAVAILABLE'),
      `losing booking must fail due to concurrency/capacity, SQLSTATE=${rejected.reason?.code}, message: ${rejected.reason?.message}`,
    );
  } finally {
    for (const client of [first, second]) {
      if (!client) continue;
      try { await client.query('ROLLBACK'); } catch { /* transaction may already be closed */ }
      client.release();
    }
    // Cleanup respects foreign-key dependency order. Run only on test database.
    const deletes = [
      [`DELETE FROM capacity_reservations WHERE booking_id=ANY($1::uuid[])`, [ids.bookings]],
      [`DELETE FROM booking_items WHERE booking_id=ANY($1::uuid[])`, [ids.bookings]],
      [`DELETE FROM bookings WHERE id=ANY($1::uuid[])`, [ids.bookings]],
      [`DELETE FROM pets WHERE id=ANY($1::uuid[])`, [ids.pets]],
      [`DELETE FROM service_availability_windows WHERE id=$1`, [ids.window]],
      [`DELETE FROM service_packages WHERE id=$1`, [ids.pkg]],
      [`DELETE FROM vendor_services WHERE id=$1`, [ids.svc]],
      [`DELETE FROM vendor_locations WHERE id=$1`, [ids.loc]],
      [`DELETE FROM vendors WHERE id=$1`, [ids.vendor]],
      [`DELETE FROM accounts WHERE id=ANY($1::uuid[])`, [ids.accounts]],
    ];
    for (const [sql, params] of deletes) {
      try { await pool.query(sql, params); }
      catch (err) { console.warn('Test fixture cleanup warning:', err.message); }
    }
    await pool.end();
  }
});
