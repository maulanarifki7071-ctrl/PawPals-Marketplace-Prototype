'use strict';
const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
process.env.NODE_ENV='test';
process.env.PAWPALS_ENABLE_MOCK_PAYMENTS='true';
const pg=require('pg');
let state,snapshot;
pg.Pool=class {
 async query(sql,params){return handle(sql,params);}
 async connect(){return {query:async(sql,params)=>handle(sql,params),release(){}};}
};
const {createMockCheckout,createMockPaymentEvent,requireLocalMockPayments}=require('../dist/shared/providers/mock-payment');
const {applyVerifiedPaymentEvent}=require('../dist/shared/domain/payment-events');
const {submitRefund}=require('../dist/shared/providers/payment');
const future=()=>new Date(Date.now()+600_000).toISOString();
function reset(){
 state={payment:{id:'pay-1',booking_id:'booking-1',provider:'MOCK',provider_order_reference:'mock-order-1',amount:100000,currency:'IDR',status:'PENDING',expires_at:future()},
 booking:{id:'booking-1',status:'AWAITING_PAYMENT',vendor_id:'vendor-1'},capacity:{id:'cap-1',status:'HELD',expires_at:future()},
 events:[],ledger:[],settlements:[],history:[],outbox:[]};
 snapshot=null;
}
function handle(sql,params=[]){
 if(sql==='BEGIN'){snapshot=structuredClone(state);return {rows:[]};}
 if(sql==='COMMIT'){snapshot=null;return {rows:[]};}
 if(sql==='ROLLBACK'){if(snapshot)state=snapshot;return {rows:[]};}
 if(sql.includes('FROM payments p JOIN bookings b ON b.id=p.booking_id WHERE p.provider_order_reference'))
  return {rows:[{...state.payment,booking_status:state.booking.status,vendor_id:state.booking.vendor_id}]};
 if(sql.includes('INSERT INTO payment_events')){
  if(state.events.some(e=>e.id===params[2]))return {rows:[]};
  state.events.push({id:params[2],provider:params[1],processed:false});return {rows:[{id:params[2]}]};
 }
 if(sql.includes('SELECT * FROM capacity_reservations WHERE booking_id='))return {rows:[state.capacity]};
 if(sql.includes("UPDATE payments SET status='PAID'")){state.payment.status='PAID';return {rows:[]};}
 if(sql.includes('UPDATE payments SET status=$2::payment_status')){state.payment.status=params[1];return {rows:[]};}
 if(sql.includes("UPDATE capacity_reservations SET status='COMMITTED'")){state.capacity.status='COMMITTED';return {rows:[]};}
 if(sql.includes('UPDATE capacity_reservations SET status=CASE')){state.capacity.status=params[1]==='EXPIRED'?'EXPIRED':'RELEASED';return {rows:[]};}
 if(sql.includes("UPDATE bookings SET status='CONFIRMED'")){state.booking.status='CONFIRMED';return {rows:[]};}
 if(sql.includes("UPDATE bookings SET status='EXPIRED'")){state.booking.status='EXPIRED';return {rows:[]};}
 if(sql.includes('INSERT INTO booking_status_history')){state.history.push(params);return {rows:[]};}
 if(sql.includes('SELECT commission_rate_bps FROM booking_policy_snapshots'))return {rows:[{commission_rate_bps:500}]};
 if(sql.includes('INSERT INTO ledger_entries')){
  let type;
  if(sql.includes("'PAYMENT_RECEIVED'"))type='PAYMENT_RECEIVED';
  else if(sql.includes("'SERVICE_EARNING'"))type='SERVICE_EARNING';
  else if(sql.includes("'PLATFORM_COMMISSION'"))type='PLATFORM_COMMISSION';
  else throw Error('Unexpected ledger SQL: '+sql);
  state.ledger.push({type,amount:params[4]});
  return {rows:type==='SERVICE_EARNING'?[{id:'earning-ledger-1'}]:[]};
 }
 if(sql.includes('INSERT INTO settlement_items')){state.settlements.push({amount:params[3],status:'PENDING'});return {rows:[]};}
 if(sql.includes('INSERT INTO outbox_events')){state.outbox.push(params);return {rows:[]};}
 if(sql.includes('UPDATE payment_events SET processed_at')){const x=state.events.find(e=>e.id===params[0]);if(x)x.processed=true;return {rows:[]};}
 throw Error('Unmocked SQL: '+sql);
}
beforeEach(reset);
test('mock checkout reports only local simulation, no Midtrans token or charge',()=>{
 const c=createMockCheckout(state.payment);
 assert.equal(c.provider,'MOCK');assert.equal(c.amount,100000);
 assert.match(c.simulation_endpoint,/\/dev\/payments\/pay-1\/simulate$/);
 assert.equal(c.redirect_url,undefined);assert.equal(c.token,undefined);
 assert.throws(()=>createMockCheckout({...state.payment,provider:'MIDTRANS'}),{code:'PAYMENT_PROVIDER_UNAVAILABLE'});
});
test('mock simulation endpoint gate denies non-loopback request',()=>{
 const call=(ip)=>{let err='not-called';requireLocalMockPayments({socket:{remoteAddress:ip}},null,e=>err=e);return err;};
 assert.equal(call('::1'),undefined);
 assert.equal(call('127.0.0.1'),undefined);
 assert.equal(call('192.168.1.2').code,'NOT_FOUND');
});
test('mock PAID commits capacity, confirms booking, posts Rp95k vendor and Rp5k commission once',async()=>{
 const body=createMockPaymentEvent(state.payment,'PAID');
 const r=await applyVerifiedPaymentEvent(body,'MOCK');
 assert.equal(r.status,'PAID');assert.equal(state.payment.status,'PAID');
 assert.equal(state.capacity.status,'COMMITTED');assert.equal(state.booking.status,'CONFIRMED');
 assert.deepEqual(state.ledger.map(x=>[x.type,x.amount]),[
  ['PAYMENT_RECEIVED',100000],['SERVICE_EARNING',95000],['PLATFORM_COMMISSION',5000]]);
 assert.deepEqual(state.settlements,[{amount:95000,status:'PENDING'}]);
 assert.equal(state.events.length,1);assert.equal(state.events[0].provider,'MOCK');assert.equal(state.outbox.length,1);
 const repeat=await applyVerifiedPaymentEvent(body,'MOCK');
 assert.equal(repeat.duplicate,true);assert.equal(state.ledger.length,3);
 await assert.rejects(applyVerifiedPaymentEvent(createMockPaymentEvent(state.payment,'FAILED'),'MOCK'),{code:'PAYMENT_NOT_PAYABLE'});
});
test('mock FAILED releases capacity; repeated failure cannot create a second event',async()=>{
 const b=createMockPaymentEvent(state.payment,'FAILED');
 const r=await applyVerifiedPaymentEvent(b,'MOCK');
 assert.equal(r.status,'FAILED');assert.equal(state.payment.status,'FAILED');
 assert.equal(state.booking.status,'EXPIRED');assert.equal(state.capacity.status,'RELEASED');
 assert.equal(state.ledger.length,0);assert.equal((await applyVerifiedPaymentEvent(b,'MOCK')).duplicate,true);
 assert.equal(state.events.length,1);
});
test('mock EXPIRED expires capacity with no earnings',async()=>{
 await applyVerifiedPaymentEvent(createMockPaymentEvent(state.payment,'EXPIRED'),'MOCK');
 assert.equal(state.payment.status,'EXPIRED');assert.equal(state.capacity.status,'EXPIRED');assert.equal(state.ledger.length,0);
});
test('mock refuses expired holds and amount tampering and mismatched provider',async()=>{
 state.capacity.expires_at=new Date(Date.now()-60_000).toISOString();
 await assert.rejects(applyVerifiedPaymentEvent(createMockPaymentEvent(state.payment,'PAID'),'MOCK'),{code:'PAYMENT_NOT_PAYABLE'});
 assert.equal(state.payment.status,'PENDING');assert.equal(state.events.length,0);
 state.capacity.expires_at=future();
 await assert.rejects(applyVerifiedPaymentEvent({...createMockPaymentEvent(state.payment,'PAID'),gross_amount:'1'},'MOCK'),{code:'PAYMENT_AMOUNT_MISMATCH'});
 assert.equal(state.payment.status,'PENDING');
 await assert.rejects(applyVerifiedPaymentEvent(createMockPaymentEvent(state.payment,'PAID'),'MIDTRANS'),{code:'PAYMENT_PROVIDER_MISMATCH'});
 assert.equal(state.ledger.length,0);
});
test('mock refund completes locally, without contacting Midtrans',async()=>{
 const original=global.fetch;global.fetch=()=>{throw Error('Unexpected external request');};
 try{
  const result=await submitRefund({id:'refund-1',amount:40000},{provider:'MOCK'});
  assert.deepEqual(result,{provider_ref:'mock-refund-refund-1',ambiguous:false,succeeded:true});
 }finally{global.fetch=original;}
});
test('production cannot boot with mock payments flag enabled',()=>{
 const result=spawnSync(process.execPath,['-e',"require('./dist/config/env')"],{
  cwd:process.cwd(),env:{...process.env,NODE_ENV:'production',PAWPALS_ENABLE_MOCK_PAYMENTS:'true'},encoding:'utf8'});
 assert.notEqual(result.status,0);assert.match(result.stderr,/forbidden in production/);
});
