'use strict';
// PawPals Stage 1B — real PostgreSQL + actual backend settlement/payout job functions.
// External disbursement functions are STUBBED IN THIS TEST PROCESS; no real money is sent.
// DB operations happen on one PostgreSQL transaction and are ROLLED BACK.
require('dotenv/config');
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {Pool} = require('pg');

const database = process.env.PAWPALS_TEST_DATABASE_URL;
const enabled = Boolean(database) && process.env.PAWPALS_ALLOW_INTEGRATION_TESTS === 'yes';
const config = { skip: !enabled && 'Needs local pawpals_finance_test and PAWPALS_ALLOW_INTEGRATION_TESTS=yes' };
const sum = async (q, sql, args=[]) => Number((await q(sql,args)).rows[0].n);

test('Stage 1B: HOLD/AVAILABLE, payout failure, idempotency, paid payout and post-payout refund',config,async()=>{
  const url=new URL(database);
  assert.equal(decodeURIComponent(url.pathname.slice(1)),'pawpals_finance_test','Refusing non-test DB');
  assert.ok(['localhost','127.0.0.1','::1','[::1]'].includes(url.hostname),'Refusing remote DB');
  assert.notEqual(process.env.NODE_ENV,'production','Refusing NODE_ENV=production');
  process.env.MINIMUM_PAYOUT_AMOUNT='50000'; // test-only policy, never edits .env
  const finance=require('../dist/shared/domain/finance.js');
  const db=require('../dist/shared/db/database.js');
  const payoutProvider=require('../dist/shared/providers/disbursement.js');
  const jobs=require('../dist/jobs/domain-jobs.js');
  const payoutJobs=require('../dist/jobs/payout-jobs.js');
  const pool=new Pool({connectionString:database,max:1,statement_timeout:12000});
  const client=await pool.connect();
  const q=(sql,params=[])=>client.query(sql,params);
  const ids={vendorAccount:randomUUID(), customerAccount:randomUUID(),vendor:randomUUID(),
     location:randomUUID(), service:randomUUID(), package:randomUUID(),pet:randomUUID(),
     booking:randomUUID(),bookingItem:randomUUID(),payment:randomUUID(),window:randomUUID(),
     payoutAccount:randomUUID(),caseId:randomUUID()};
  const uniqueDigits=String(BigInt('0x'+randomUUID().replace(/-/g,'').slice(0,12))%1000000000n).padStart(9,'0');
  const start=new Date(Date.now()+48*3600_000); start.setUTCMinutes(0,0,0);
  const end=new Date(start.getTime()+3600_000);
  const availStart=new Date(start.getTime()-3600_000);
  const availEnd=new Date(end.getTime()+3600_000);
  const original={dbQuery:db.query,dbTransaction:db.transaction,configured:payoutProvider.isDisbursementConfigured,
    submit:payoutProvider.submitDisbursement,fetch:payoutProvider.fetchDisbursementStatus,
    name:payoutProvider.disbursementProviderName};
  const outcomes=new Map();
  let submitCalls=0, pollCalls=0;
  let began=false;
  try{
    await q('BEGIN'); began=true;
    // Route imported production job SQL through the same test-only, rollback-only client.
    // This verifies job queries/state transitions, NOT cross-transaction isolation or scheduler timing.
    db.query=async(sql,params=[])=>q(sql,params);
    db.transaction=async(fn)=>fn(client);
    payoutProvider.isDisbursementConfigured=()=>true;
    payoutProvider.disbursementProviderName=()=> 'LOCAL_TEST_STUB';
    payoutProvider.submitDisbursement=async({id})=>{submitCalls++;outcomes.set(id,'PROCESSING');return {reference:id,status:'PROCESSING'};};
    payoutProvider.fetchDisbursementStatus=async(id)=>{pollCalls++;return {reference:id,status:outcomes.get(id)??'PROCESSING'};};

    const schema=await q(`SELECT to_regclass('public.payouts') IS NOT NULL AS payouts_ok,
            to_regclass('public.settlement_items') IS NOT NULL AS settlement_ok,
            to_regclass('public.vendor_payout_accounts') IS NOT NULL AS account_ok`);
    assert.ok(Object.values(schema.rows[0]).every(Boolean),'Finance schema not installed');
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
    // Validate fixture, then restore deferred checks for multi-statement payout allocation.
    await q('SET CONSTRAINTS ALL IMMEDIATE');
    await q('SET CONSTRAINTS ALL DEFERRED');


    const payment=(await q('SELECT * FROM payments WHERE id=$1',[ids.payment])).rows[0];
    const booking=(await q('SELECT * FROM bookings WHERE id=$1',[ids.booking])).rows[0];
    await finance.postPaidEconomics(client,payment,booking);
    await q(`INSERT INTO vendor_payout_accounts(id,vendor_id,bank_code,account_holder_name,
       account_number_encrypted,account_number_last4,provider_recipient_ref,verified_at,is_active)
       VALUES($1,$2,'TEST_BANK','TEST ONLY','fake-encrypted-test-value','1234','test-recipient',now(),true)`,
      [ids.payoutAccount,ids.vendor]);
    await q(`UPDATE settlement_items SET status='HOLD',hold_until=now()+interval '1 day'
      WHERE booking_id=$1 AND source_type='SERVICE_EARNING'`,[ids.booking]);
    assert.equal(await jobs.releaseEligibleSettlements(),0,'Unexpired hold cannot release');
    assert.equal(await sum(q,`SELECT count(*) AS n FROM settlement_items WHERE booking_id=$1 AND status='HOLD'`,[ids.booking]),1);
    console.log('PASS 1: HOLD before deadline cannot become AVAILABLE');

    // Advance ONLY a test-row deadline; do not adjust system clock or production settings.
    await q(`UPDATE settlement_items SET hold_until=now()-interval '1 minute' WHERE booking_id=$1`,[ids.booking]);
    await q(`INSERT INTO support_cases(id,case_type,status,booking_id,opened_by_type,category,description)
       VALUES($1,'DISPUTE','OPEN',$2,'SYSTEM','TEST_BLOCK','Local test-only dispute')`,[ids.caseId,ids.booking]);
    assert.equal(await jobs.releaseEligibleSettlements(),0,'Open dispute must block release');
    await q(`UPDATE support_cases SET status='RESOLVED',triaged_at=now(),
       investigation_started_at=now(),resolved_at=now() WHERE id=$1`,[ids.caseId]);
    assert.equal(await jobs.releaseEligibleSettlements(),1,'Release after expired hold and resolved dispute');
    assert.equal(await jobs.releaseEligibleSettlements(),0,'Release must be idempotent');
    assert.equal(await sum(q,`SELECT sum(amount_signed) AS n FROM settlement_items WHERE booking_id=$1 AND status='AVAILABLE'`,[ids.booking]),95000);
    console.log('PASS 2: open dispute blocks release; resolved dispute and elapsed hold release once');

    assert.equal(await jobs.allocateScheduledPayouts(),1,'One payout should be created');
    assert.equal(await jobs.allocateScheduledPayouts(),0,'Do not allocate same funds twice');
    const first=(await q(`SELECT * FROM payouts WHERE vendor_id=$1 AND status='QUEUED'`,[ids.vendor])).rows[0];
    assert.ok(first&&Number(first.total_amount)===95000,'Payout total must be 95000');
    assert.equal(await sum(q,`SELECT count(*) AS n FROM payout_items WHERE payout_id=$1 AND released_at IS NULL`,[first.id]),1);
    assert.equal(await sum(q,`SELECT count(*) AS n FROM settlement_items WHERE booking_id=$1 AND status='ALLOCATED'`,[ids.booking]),1);
    await q('SET CONSTRAINTS ALL IMMEDIATE');
    await q('SET CONSTRAINTS ALL DEFERRED');
    console.log('PASS 3: one QUEUED payout Rp95.000; allocation replay cannot duplicate it');

    assert.equal(await payoutJobs.dispatchQueuedPayouts(),1,'Dispatch one queued payout');
    assert.equal(await submitCalls,1,'Provider submit called exactly once');
    assert.equal((await q('SELECT status FROM payouts WHERE id=$1',[first.id])).rows[0].status,'PROCESSING');
    assert.equal(await payoutJobs.reconcileProcessingPayouts(),0,'Ambiguous/processing payout must stay PROCESSING');
    assert.equal(await payoutJobs.dispatchQueuedPayouts(),0,'PROCESSING payout cannot be submitted a second time');
    assert.equal(submitCalls,1);
    console.log('PASS 4: ambiguous PROCESSING payout is not submitted again');

    outcomes.set(first.id,'FAILED');
    assert.equal(await payoutJobs.reconcileProcessingPayouts(),1,'Definitive FAILED status should release allocation');
    assert.equal((await q('SELECT status FROM payouts WHERE id=$1',[first.id])).rows[0].status,'FAILED');
    assert.equal(await sum(q,`SELECT count(*) AS n FROM payout_items WHERE payout_id=$1 AND released_at IS NOT NULL`,[first.id]),1);
    assert.equal(await sum(q,`SELECT sum(amount_signed) AS n FROM settlement_items WHERE booking_id=$1 AND status='AVAILABLE'`,[ids.booking]),95000);
    await q('SET CONSTRAINTS ALL IMMEDIATE');
    await q('SET CONSTRAINTS ALL DEFERRED');
    console.log('PASS 5: definitive FAILED payout releases locked funds for later allocation');

    assert.equal(await jobs.allocateScheduledPayouts(),1,'Retry next cycle may allocate again after definitive failure');
    const second=(await q(`SELECT * FROM payouts WHERE vendor_id=$1 AND status='QUEUED'`,[ids.vendor])).rows[0];
    assert.ok(second&&second.id!==first.id);
    assert.equal(await payoutJobs.dispatchQueuedPayouts(),1);
    assert.equal(submitCalls,2,'New payout should submit just once');
    outcomes.set(second.id,'PAID');
    assert.equal(await payoutJobs.reconcileProcessingPayouts(),1,'Verified success should settle exactly once');
    assert.equal(await payoutJobs.reconcileProcessingPayouts(),0,'Repeated poll must be no-op for PAID');
    assert.equal((await q('SELECT status FROM payouts WHERE id=$1',[second.id])).rows[0].status,'PAID');
    assert.equal(await sum(q,`SELECT sum(amount_signed) AS n FROM settlement_items WHERE booking_id=$1 AND status='SETTLED'`,[ids.booking]),95000);
    assert.equal(await sum(q,`SELECT count(*) AS n FROM ledger_entries WHERE posting_type='PAYOUT_DISBURSED' AND canonical_event_id=$1`,[second.id]),1);
    await q('SET CONSTRAINTS ALL IMMEDIATE');
    await q('SET CONSTRAINTS ALL DEFERRED');
    console.log('PASS 6: verified PAID payout settles once; repeated reconciliation does not double-pay');

    // Post-payout refund: keep immutable SETTLED history and carry a negative vendor adjustment forward.
    const refund=await finance.createRefundObligation(client,{paymentId:ids.payment,amount:40000,
      initiatorType:'SYSTEM',reasonCode:'STAGE_1B_POST_PAYOUT_REFUND'});
    await q(`UPDATE refunds SET status='SUCCEEDED',succeeded_at=now() WHERE id=$1`,[refund.id]);
    const succeeded=(await q('SELECT * FROM refunds WHERE id=$1',[refund.id])).rows[0];
    await finance.postRefundSucceeded(client,succeeded);
    await finance.postRefundSucceeded(client,succeeded);
    assert.equal(await sum(q,`SELECT sum(amount_signed) AS n FROM settlement_items WHERE booking_id=$1 AND status='SETTLED'`,[ids.booking]),95000);
    assert.equal(await sum(q,`SELECT sum(amount_signed) AS n FROM settlement_items WHERE booking_id=$1 AND status='AVAILABLE'`,[ids.booking]),-38000);
    assert.equal(await sum(q,`SELECT sum(amount_signed) AS n FROM settlement_items WHERE booking_id=$1 AND status<>'REVERSED'`,[ids.booking]),57000);
    assert.equal(await sum(q,`SELECT count(*) AS n FROM ledger_entries WHERE booking_id=$1 AND posting_type='NEGATIVE_ADJUSTMENT'`,[ids.booking]),1);
    assert.equal(await jobs.allocateScheduledPayouts(),0,'Negative debit cannot trigger a payout');
    assert.equal((await q('SELECT status FROM payouts WHERE id=$1',[second.id])).rows[0].status,'PAID');
    await q('SET CONSTRAINTS ALL IMMEDIATE');
    console.log('PASS 7: refund after PAID creates one -Rp38.000 debit; settled history remains immutable');

    const finalRefund=await finance.createRefundObligation(client,{paymentId:ids.payment,amount:60000,
      initiatorType:'SYSTEM',reasonCode:'STAGE_1B_FULL_REFUND_AFTER_PAYOUT'});
    await q(`UPDATE refunds SET status='SUCCEEDED',succeeded_at=now() WHERE id=$1`,[finalRefund.id]);
    const finalSucceeded=(await q('SELECT * FROM refunds WHERE id=$1',[finalRefund.id])).rows[0];
    await finance.postRefundSucceeded(client,finalSucceeded);
    await finance.postRefundSucceeded(client,finalSucceeded); // duplicate callback is a no-op
    assert.equal(await sum(q,`SELECT COALESCE(sum(amount_signed),0) AS n FROM settlement_items
       WHERE booking_id=$1 AND status='SETTLED'`,[ids.booking]),95000);
    assert.equal(await sum(q,`SELECT COALESCE(sum(amount_signed),0) AS n FROM settlement_items
       WHERE booking_id=$1 AND status='AVAILABLE'`,[ids.booking]),-95000);
    assert.equal(await sum(q,`SELECT COALESCE(sum(amount_signed),0) AS n FROM settlement_items
       WHERE booking_id=$1 AND status<>'REVERSED'`,[ids.booking]),0);
    assert.equal(await sum(q,`SELECT COALESCE(sum(amount_signed),0) AS n FROM ledger_entries
       WHERE booking_id=$1 AND posting_type IN ('PLATFORM_COMMISSION','PLATFORM_COMMISSION_REVERSAL')`,[ids.booking]),0);
    assert.equal(await jobs.allocateScheduledPayouts(),0,'Outstanding vendor debt cannot generate payout');
    await q('SET CONSTRAINTS ALL IMMEDIATE');
    console.log('PASS 8: full refund after PAID carries -Rp95.000 debt; net entitlement and commission are zero');

    console.log(`SUMMARY: fake provider submits=${submitCalls}, status polls=${pollCalls}; NO external payout sent`);
    console.log('ROLLBACK: every fixture, payout, ledger entry, refund and outbox event will be removed');
  } finally {
    Object.assign(db,{query:original.dbQuery,transaction:original.dbTransaction});
    payoutProvider.isDisbursementConfigured=original.configured;
    payoutProvider.submitDisbursement=original.submit;
    payoutProvider.fetchDisbursementStatus=original.fetch;
    payoutProvider.disbursementProviderName=original.name;
    if(began){try{await q('ROLLBACK');console.log('ROLLBACK complete: no finance fixtures retained');}
      catch(err){console.error('ROLLBACK failed:',err.message);}}
    client.release(); await pool.end();
  }
});
