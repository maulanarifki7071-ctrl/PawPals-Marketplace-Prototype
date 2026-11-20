const {test}=require('node:test');
const assert=require('node:assert/strict');
process.env.NODE_ENV='test';
const {postRefundSucceeded}=require('../dist/shared/domain/finance');
const {bookingResponseForVendor}=require('../dist/modules/bookings/router');
const {providerRefundOutcome}=require('../dist/jobs/reconciliation-jobs');
const {outboxJobId}=require('../dist/jobs/outbox-events');
const {canonicalPaymentOutcome,verifyMidtransWebhook}=require('../dist/shared/providers/payment');
const {signS3Url}=require('../dist/shared/providers/media');
const {csrfOriginGuard}=require('../dist/middleware/csrf-origin');

function ledgerHarness({status='COMPLETED',paid=100000,refund=50000,commissionBps=500,settlementAmount=95000,settlementStatus='AVAILABLE',faultParty=null,retained=0}={}){
 const state={refundLedger:new Set(),commissionNet:status==='CUSTOMER_CANCELLED'?2500:5000,commissionAdjustments:[],rows:[{status:settlementStatus,amount_signed:settlementAmount,hold_until:new Date(Date.now()+3600000)}],adjustments:[],events:[],queries:[]};
 const id='11111111-1111-4111-8111-111111111111';
 const tx={async query(sql,params=[]){state.queries.push(sql);
  if(sql.includes('SELECT p.booking_id,b.vendor_id'))return {rows:[{booking_id:'booking-1',vendor_id:'vendor-1'}]};
  if(sql.includes('INSERT INTO ledger_entries')&&sql.includes("'REFUND'")){
   if(state.refundLedger.has(params[4]))return {rows:[]};
   state.refundLedger.add(params[4]);return {rows:[{id:'refund-ledger'}]};
  }
  if(sql.includes('SELECT b.id,b.vendor_id,b.status'))return {rows:[{id:'booking-1',vendor_id:'vendor-1',status,payment_id:'payment-1',payment_amount:paid,payment_status:'PAID',commission_rate_bps:commissionBps,fault_party:faultParty,retained_settlement_base_amount:retained}]};
  if(sql.includes('SELECT COALESCE(sum(amount),0)::bigint total FROM refunds'))return {rows:[{total:refund}]};
  if(sql.includes('SELECT COALESCE(sum(amount_signed),0)::bigint net FROM ledger_entries'))return {rows:[{net:state.commissionNet}]};
  if(sql.includes('INSERT INTO ledger_entries')&&sql.includes('PLATFORM_COMMISSION_REVERSAL')){state.commissionNet+=params[4];state.commissionAdjustments.push(params[4]);return {rows:[]};}
  if(sql.includes('SELECT COALESCE(sum(amount_signed),0)::bigint net FROM settlement_items'))return {rows:[{net:state.rows.filter(r=>r.status!=='REVERSED').reduce((sum,x)=>sum+x.amount_signed,0)}]};
  if(sql.includes('INSERT INTO ledger_entries')&&sql.includes('NEGATIVE_ADJUSTMENT')){if(state.events.includes(params[3]))return {rows:[]};state.events.push(params[3]);state.adjustments.push(params[4]);return {rows:[{id:`adjustment-${state.adjustments.length}`}]};}
  if(sql.includes('SELECT status,hold_until FROM settlement_items'))return {rows:state.rows.filter(x=>['PENDING','HOLD','AVAILABLE'].includes(x.status)).slice(0,1)};
  if(sql.includes('INSERT INTO settlement_items')){state.rows.push({status:params[3],amount_signed:params[4],hold_until:params[5]});return {rows:[]};}
  throw new Error(`Unmocked SQL: ${sql}`);
 }};
 return {tx,state,id};
}
test('paid booking partial refund deducts vendor net after commission, not gross customer refund',async()=>{
 const h=ledgerHarness();await postRefundSucceeded(h.tx,{id:h.id,payment_id:'payment-1',amount:50000});
 assert.deepEqual(h.state.adjustments,[-47500]);
 assert.deepEqual(h.state.commissionAdjustments,[-2500]);
 assert.equal(h.state.rows.reduce((sum,r)=>sum+r.amount_signed,0),47500);
});
test('refund posting is idempotent across duplicate provider notifications',async()=>{
 const h=ledgerHarness();for(let i=0;i<2;i++)await postRefundSucceeded(h.tx,{id:h.id,payment_id:'payment-1',amount:50000});
 assert.equal(h.state.adjustments.length,1);
 assert.equal(h.state.refundLedger.size,1);
});
test('refund on HOLD settlement keeps debit on HOLD until settlement release',async()=>{
 const h=ledgerHarness({settlementStatus:'HOLD'});await postRefundSucceeded(h.tx,{id:h.id,payment_id:'payment-1',amount:50000});
 assert.equal(h.state.rows[1].status,'HOLD');assert.ok(h.state.rows[1].hold_until);
});
test('settled payout cannot be rewritten: corrective refund creates AVAILABLE vendor debt',async()=>{
 const h=ledgerHarness({settlementStatus:'SETTLED'});await postRefundSucceeded(h.tx,{id:h.id,payment_id:'payment-1',amount:100000});
 assert.equal(h.state.rows[0].status,'SETTLED');assert.equal(h.state.rows[1].status,'AVAILABLE');assert.equal(h.state.rows[1].amount_signed,-47500);
});
test('customer cancellation compensation net is not debited twice on its contractual refund',async()=>{
 const h=ledgerHarness({status:'CUSTOMER_CANCELLED',refund:50000,settlementAmount:47500,settlementStatus:'HOLD',faultParty:'CUSTOMER',retained:50000});
 await postRefundSucceeded(h.tx,{id:h.id,payment_id:'payment-1',amount:50000});
 assert.equal(h.state.adjustments.length,0);
});
test('unresolved vendor fault claim does not create premature vendor debit',async()=>{
 const h=ledgerHarness({status:'CUSTOMER_CANCELLED',faultParty:'PENDING_REVIEW'});
 await postRefundSucceeded(h.tx,{id:h.id,payment_id:'payment-1',amount:50000});assert.equal(h.state.adjustments.length,0);
});
test('vendor booking awaiting payment hides private snapshots and exact address',()=>{
 const row={id:'booking',status:'AWAITING_PAYMENT',total_amount:12000,pet_snapshot_json:{safety:{medication:'private'}},compatibility_snapshot_json:{},address_snapshot:'private street',latitude:-6.2,longitude:106.8,booking_specific_notes:'private'};
 const safe=bookingResponseForVendor(row);
 for(const field of ['pet_snapshot_json','compatibility_snapshot_json','address_snapshot','latitude','longitude','booking_specific_notes'])assert.equal(field in safe,false);
 assert.equal(safe.id,'booking');assert.equal(bookingResponseForVendor({...row,status:'CONFIRMED'}).address_snapshot,'private street');
});
test('Midtrans classification never confirms a fraud challenge or denial',()=>{
 assert.equal(canonicalPaymentOutcome({transaction_status:'capture',fraud_status:'challenge'}),'PENDING');
 assert.equal(canonicalPaymentOutcome({transaction_status:'capture',fraud_status:'deny'}),'FAILED');
 assert.equal(canonicalPaymentOutcome({transaction_status:'settlement'}),'PAID');
 assert.equal(canonicalPaymentOutcome({transaction_status:'expire'}),'EXPIRED');
});
test('Midtrans webhook without key cannot authenticate',()=>{
 process.env.ALLOW_UNVERIFIED_DEV_WEBHOOK='false';
 assert.equal(verifyMidtransWebhook({order_id:'x',status_code:'200',gross_amount:'100'}),false);
});
test('refund status is unknown until provider identifies exact refund key and amount',()=>{
 const refunds=[{refund_key:'pawpals-refund-id-a',amount:50000,status:'success'}];
 assert.equal(providerRefundOutcome({refunds},'id-a',50000),'SUCCEEDED');
 assert.equal(providerRefundOutcome({refunds},'id-a',30000),'UNKNOWN');
 assert.equal(providerRefundOutcome({refunds},'id-b',50000),'UNKNOWN');
 assert.equal(providerRefundOutcome({refunds:[{...refunds[0],status:'failed'}]},'id-a',50000),'FAILED');
});
test('Outbox job IDs are safe, stable and different per recovery attempt',()=>{
 const a=outboxJobId('booking:123:paid',1),b=outboxJobId('booking:123:paid',2);
 assert.match(a,/^[0-9a-f]{64}$/);assert.notEqual(a,b);assert.equal(a,outboxJobId('booking:123:paid',1));
});
test('storage provider does not issue placeholder URLs when unconfigured',()=>{
 delete process.env.MEDIA_S3_ENDPOINT;delete process.env.MEDIA_S3_BUCKET;
 assert.throws(()=>signS3Url('PUT','private/a'),{code:'MEDIA_STORAGE_UNAVAILABLE'});
});
test('S3 signature only uses private bucket path and short-lived signed upload',()=>{
 Object.assign(process.env,{MEDIA_S3_ENDPOINT:'https://private-s3.example',MEDIA_S3_BUCKET:'private',MEDIA_S3_ACCESS_KEY_ID:'exampleaccess',MEDIA_S3_SECRET_ACCESS_KEY:'secret'});
 const url=new URL(signS3Url('PUT','private/pet/abc',600,'image/jpeg'));
 assert.equal(url.pathname,'/private/private/pet/abc');assert.equal(url.searchParams.get('X-Amz-Expires'),'600');
 assert.equal(url.searchParams.get('X-Amz-SignedHeaders'),'content-type;host');assert.match(url.searchParams.get('X-Amz-Signature'),/^[0-9a-f]{64}$/);
});
test('cross origin cookie-auth writes are denied; same origin allowed',()=>{
 const invoke=(origin)=>{let got;csrfOriginGuard({method:'POST',account:{id:'user'},headers:{origin,host:'pawpals.example'},secure:true},{},err=>got=err);return got;};
 assert.equal(invoke('https://outside.example').code,'CSRF_ORIGIN_FORBIDDEN');
 assert.equal(invoke('https://pawpals.example'),undefined);
});
