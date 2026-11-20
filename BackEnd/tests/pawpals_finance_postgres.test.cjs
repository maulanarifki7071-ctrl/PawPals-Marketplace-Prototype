'use strict';
// PawPals finance integration smoke/regression test against REAL PostgreSQL.
// NO payments/refunds are sent to external providers. Every fixture is ROLLED BACK.
// Install under project_pawpals/tests/ and run after `npm run build`.
require('dotenv/config');
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {Pool} = require('pg');

const database = process.env.PAWPALS_TEST_DATABASE_URL;
const enabled = Boolean(database) && process.env.PAWPALS_ALLOW_INTEGRATION_TESTS === 'yes';

function amount(row, key) { return Number(row[key]); }

const config = {
  skip: !enabled && 'Needs dedicated pawpals_finance_test database and PAWPALS_ALLOW_INTEGRATION_TESTS=yes',
};

test('Finance PostgreSQL: payment economics, partial/full refund, settlement adjustment and idempotency', config, async () => {
  const url = new URL(database);
  assert.equal(decodeURIComponent(url.pathname.slice(1)), 'pawpals_finance_test',
    'Refusing to run: test DB MUST be pawpals_finance_test');
  assert.ok(['127.0.0.1', 'localhost', '::1', '[::1]'].includes(url.hostname),
    'Refusing to run against non-local PostgreSQL');

  // Uses genuine compiled PawPals business code, NOT a rewritten SQL imitation.
  const finance = require('../dist/shared/domain/finance.js');
  const pool = new Pool({connectionString: database, max: 1, statement_timeout: 12000});
  const client = await pool.connect();
  let began = false;
  const ids = {
    vendorAccount: randomUUID(), customerAccount: randomUUID(), vendor: randomUUID(),
    location: randomUUID(), service: randomUUID(), package: randomUUID(),
    pet: randomUUID(), booking: randomUUID(), bookingItem: randomUUID(),
    payment: randomUUID(), window: randomUUID(),
  };
  const uniqueDigits = String(BigInt('0x' + randomUUID().replace(/-/g, '').slice(0, 12)) % 1000000000n).padStart(9, '0');
  const start = new Date(Date.now() + 48 * 3600_000);
  start.setUTCMinutes(0, 0, 0);
  const end = new Date(start.getTime() + 3600_000);
  const availStart = new Date(start.getTime() - 3600_000);
  const availEnd = new Date(end.getTime() + 3600_000);

  const q = (sql, params=[]) => client.query(sql,params);
  const getMoney = async () => {
    const s = (await q(`SELECT COALESCE(sum(amount_signed),0)::bigint AS net FROM settlement_items
                         WHERE booking_id=$1 AND status<>'REVERSED'`,[ids.booking])).rows[0];
    const commission = (await q(`SELECT COALESCE(sum(amount_signed),0)::bigint AS net FROM ledger_entries
                        WHERE booking_id=$1 AND posting_type IN ('PLATFORM_COMMISSION','PLATFORM_COMMISSION_REVERSAL')`,[ids.booking])).rows[0];
    const refunds = (await q(`SELECT COALESCE(sum(amount),0)::bigint AS total FROM refunds
                        WHERE payment_id=$1 AND status='SUCCEEDED'`,[ids.payment])).rows[0];
    const ledgerRefunds = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries
                       WHERE booking_id=$1 AND posting_type='REFUND'`,[ids.booking])).rows[0];
    return {net:amount(s,'net'),commission:amount(commission,'net'),
            refunded:amount(refunds,'total'),refundLedgerCount:ledgerRefunds.n};
  };
  try {
    await q('BEGIN'); began = true;
    // This test never commits; the constraints are explicitly checked before rollback.
    const installed = await q(`SELECT to_regclass('public.settlement_items') IS NOT NULL AS settlement_ok,
        to_regclass('public.refunds') IS NOT NULL AS refunds_ok,
        to_regprocedure('public.pawpals_guard_settlement()') IS NOT NULL AS guard_ok`);
    assert.ok(installed.rows[0].settlement_ok && installed.rows[0].refunds_ok && installed.rows[0].guard_ok,
      'Finance schema/guard missing: apply migrations 001-026 and 027');

    // Fixture mirrors the required account/vendor/pet/booking/payment relationships.
    await q(`INSERT INTO accounts(id,phone_e164,display_name,status,phone_verified_at)
             VALUES($1,$2,'Finance Test Vendor','ACTIVE',now()),
                   ($3,$4,'Finance Test Customer','ACTIVE',now())`,
      [ids.vendorAccount,`+6289${uniqueDigits}0`,ids.customerAccount,`+6289${uniqueDigits}1`]);
    await q(`INSERT INTO vendors(id,account_id,vendor_type,public_display_name,status,approved_at)
             VALUES($1,$2,'INDIVIDUAL','Finance Test Vendor','ACTIVE',now())`,[ids.vendor,ids.vendorAccount]);
    await q(`INSERT INTO vendor_locations(id,vendor_id,location_type,address_line1,latitude,longitude)
             VALUES($1,$2,'OPERATIONAL_PRIVATE','Finance test location',-6.2,106.8)`,[ids.location,ids.vendor]);
    await q(`INSERT INTO vendor_services(id,vendor_id,origin_vendor_location_id,category_code,name,
                delivery_mode,minimum_notice_minutes,buffer_after_minutes,base_capacity,status)
             VALUES($1,$2,$3,'TEST','Finance Test Service','AT_VENDOR',0,0,1,'ACTIVE')`,
      [ids.service,ids.vendor,ids.location]);
    await q(`INSERT INTO service_packages(id,vendor_service_id,name,duration_minutes,price_amount,is_active)
             VALUES($1,$2,'Finance Test Package',60,100000,true)`,[ids.package,ids.service]);
    await q(`INSERT INTO service_availability_windows(id,vendor_service_id,starts_at,ends_at)
             VALUES($1,$2,$3,$4)`,[ids.window,ids.service,availStart,availEnd]);
    await q(`INSERT INTO pets(id,owner_account_id,name,species_code)
             VALUES($1,$2,'Finance Test Pet','DOG')`,[ids.pet,ids.customerAccount]);
    await q(`INSERT INTO bookings(id,customer_account_id,vendor_id,vendor_service_id,
              status,scheduled_start_at,scheduled_end_at,occupied_end_at,total_amount)
             VALUES($1,$2,$3,$4,'CREATED',$5,$6,$6,100000)`,
      [ids.booking,ids.customerAccount,ids.vendor,ids.service,start,end]);
    await q(`INSERT INTO booking_items(id,booking_id,pet_id,service_package_id,
              pet_snapshot_json,compatibility_snapshot_json,price_amount_snapshot,
              duration_minutes_snapshot,buffer_after_minutes_snapshot,minimum_notice_minutes_snapshot)
             VALUES($1,$2,$3,$4,'{}'::jsonb,'{}'::jsonb,100000,60,0,0)`,
      [ids.bookingItem,ids.booking,ids.pet,ids.package]);
    await q(`INSERT INTO booking_location_snapshots(booking_id,delivery_mode_snapshot,address_snapshot,latitude,longitude)
             VALUES($1,'AT_VENDOR','Finance test location',-6.2,106.8)`,[ids.booking]);
    await q(`INSERT INTO booking_policy_snapshots(booking_id,policy_version,commission_rate_bps,
              cancellation_tiers_snapshot_json,payment_hold_minutes,settlement_hold_minutes,
              cancellation_claim_window_minutes,customer_self_reschedule_min_notice_minutes,
              customer_self_reschedule_max_applied_count)
             VALUES($1,'finance-test-v1',500,'{}'::jsonb,15,1440,1440,1440,1)`,[ids.booking]);
    await q(`INSERT INTO capacity_reservations(booking_id,vendor_service_id,service_package_id,
              status,starts_at,service_ends_at,occupied_ends_at,committed_at)
             VALUES($1,$2,$3,'COMMITTED',$4,$5,$5,now())`,
      [ids.booking,ids.service,ids.package,start,end]);
    await q(`INSERT INTO payments(id,booking_id,provider,provider_order_reference,amount,status,paid_at)
             VALUES($1,$2,'MIDTRANS',$3,100000,'PAID',now())`,
      [ids.payment,ids.booking,'finance-test-'+randomUUID()]);
    await q(`UPDATE bookings SET status='COMPLETED',confirmed_at=now(),service_started_at=now(),completed_at=now()
             WHERE id=$1`,[ids.booking]);
    // Verify deferred FK/state/capacity checks on this fixture while still within rollback-only transaction.
    await q('SET CONSTRAINTS ALL IMMEDIATE');

    const payment = (await q('SELECT * FROM payments WHERE id=$1',[ids.payment])).rows[0];
    const booking = (await q('SELECT * FROM bookings WHERE id=$1',[ids.booking])).rows[0];
    await finance.postPaidEconomics(client,payment,booking);
    await finance.postPaidEconomics(client,payment,booking); // replay same payment event
    let money = await getMoney();
    assert.deepEqual(money,{net:95000,commission:5000,refunded:0,refundLedgerCount:0});
    const paidEntries = await q(`SELECT count(*)::int AS n FROM ledger_entries
                                 WHERE booking_id=$1 AND canonical_event_type='PAYMENT_PAID'`,[ids.booking]);
    assert.equal(paidEntries.rows[0].n,3,'Duplicate payment posting must not create extra ledger entries');
    console.log('PASS 1: paid Rp100.000 -> platform Rp5.000, vendor Rp95.000; payment replay idempotent');

    await q(`UPDATE settlement_items SET status='HOLD',hold_until=now()+interval '1 day'
             WHERE booking_id=$1 AND source_type='SERVICE_EARNING'`,[ids.booking]);
    const r1 = await finance.createRefundObligation(client,{paymentId:ids.payment,amount:40000,
      initiatorType:'SYSTEM',reasonCode:'FINANCE_TEST_PARTIAL'});
    assert.equal(r1.status,'REQUESTED');
    await q(`UPDATE refunds SET status='SUCCEEDED',succeeded_at=now() WHERE id=$1`,[r1.id]);
    const succeeded1 = (await q('SELECT * FROM refunds WHERE id=$1',[r1.id])).rows[0];
    await finance.postRefundSucceeded(client,succeeded1);
    money = await getMoney();
    assert.deepEqual(money,{net:57000,commission:3000,refunded:40000,refundLedgerCount:1});
    console.log('PASS 2: refund Rp40.000 -> net vendor Rp57.000, commission Rp3.000');

    await finance.postRefundSucceeded(client,succeeded1); // simulate duplicated success callback
    assert.deepEqual(await getMoney(),money,'Duplicate refund success must not change economics');
    const adjustments = await q(`SELECT amount_signed,status FROM settlement_items
                                  WHERE booking_id=$1 AND source_type='NEGATIVE_ADJUSTMENT'`,[ids.booking]);
    assert.equal(adjustments.rows.length,1);
    assert.equal(Number(adjustments.rows[0].amount_signed),-38000);
    assert.equal(adjustments.rows[0].status,'HOLD');
    console.log('PASS 3: duplicate refund success does not create another negative adjustment');

    await assert.rejects(
      finance.createRefundObligation(client,{paymentId:ids.payment,amount:70000,
        initiatorType:'SYSTEM',reasonCode:'FINANCE_TEST_EXCESS'}),
      /REFUND_EXCEEDS_PAYMENT/,
    );
    assert.deepEqual(await getMoney(),money);
    console.log('PASS 4: combined refunds cannot exceed original payment');

    const r2 = await finance.createRefundObligation(client,{paymentId:ids.payment,amount:60000,
      initiatorType:'SYSTEM',reasonCode:'FINANCE_TEST_FULL'});
    await q(`UPDATE refunds SET status='SUCCEEDED',succeeded_at=now() WHERE id=$1`,[r2.id]);
    const succeeded2 = (await q('SELECT * FROM refunds WHERE id=$1',[r2.id])).rows[0];
    await finance.postRefundSucceeded(client,succeeded2);
    money = await getMoney();
    assert.deepEqual(money,{net:0,commission:0,refunded:100000,refundLedgerCount:2});
    console.log('PASS 5: total refund Rp100.000 -> vendor entitlement Rp0, commission Rp0');

    await q('SET CONSTRAINTS ALL IMMEDIATE'); // validate deferred refund/capacity integrity too
    console.log('PASS 6: PostgreSQL constraints verified; ALL fixtures will be rolled back');
  } finally {
    if (began) {
      try { await q('ROLLBACK'); console.log('ROLLBACK: no test finance records retained'); }
      catch(err) { console.error('ROLLBACK FAILED — verify test database:',err.message); }
    }
    client.release();
    await pool.end();
  }
});
