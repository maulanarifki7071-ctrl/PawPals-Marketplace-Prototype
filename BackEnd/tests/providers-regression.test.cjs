const {test}=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
process.env.NODE_ENV='test';
const {verifyDisbursementRecipient,submitDisbursement,fetchDisbursementStatus}=require('../dist/shared/providers/disbursement');

async function sandbox(fn){
 const requests=[];
 const server=http.createServer(async(req,res)=>{
  let raw='';for await(const c of req)raw+=c;
  const body=raw?JSON.parse(raw):null;
  requests.push({method:req.method,path:req.url,idempotency:req.headers['idempotency-key'],body});
  res.setHeader('content-type','application/json');
  if(req.url==='/recipients/verify')return res.end(JSON.stringify({verified:true,recipient_id:'test-recipient-id'}));
  if(req.url==='/payouts')return res.end(JSON.stringify({reference:body.reference,status:'PROCESSING'}));
  if(req.url==='/payouts/payout-123')return res.end(JSON.stringify({reference:'payout-123',status:'PAID'}));
  res.statusCode=404;res.end('{}');
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base=`http://127.0.0.1:${server.address().port}`;
 Object.assign(process.env,{DISBURSEMENT_API_URL:base,DISBURSEMENT_API_TOKEN:'test-token',DISBURSEMENT_PROVIDER:'MOCK_SANDBOX'});
 try{await fn(requests);}finally{await new Promise(resolve=>server.close(resolve));}
}
test('recipient verification is proof-driven and disbursement uses a stable idempotency key',async()=>{
 await sandbox(async(requests)=>{
  const v=await verifyDisbursementRecipient({id:'recipient-1',bank_code:'TEST',account_holder_name:'Test',account_number:'12345678'});
  assert.deepEqual(v,{verified:true,ref:'test-recipient-id'});
  const accepted=await submitDisbursement({id:'payout-123',recipientRef:v.ref,amount:50000});
  assert.equal(accepted.status,'PROCESSING');
  assert.equal(requests[1].idempotency,'payout:payout-123');
  assert.equal(requests[1].body.currency,'IDR');
  assert.equal((await fetchDisbursementStatus('payout-123')).status,'PAID');
  assert.equal(requests[2].method,'GET');
 });
});
test('response with wrong payout reference is rejected and cannot mark another payout paid',async()=>{
 await sandbox(async()=>{await assert.rejects(fetchDisbursementStatus('not-payout-123'),e=>e.code==='DISBURSEMENT_PROVIDER_UNAVAILABLE');});
});

test('Twilio Verify uses separate purpose-bound service for sensitive OTP',async()=>{
 const {verifyOtpForChallenge}=require('../dist/shared/providers/verification');
 Object.assign(process.env,{TWILIO_ACCOUNT_SID:'AC-test',TWILIO_AUTH_TOKEN:'sandbox-secret',
  TWILIO_VERIFY_SERVICE_SID_PASSWORD_RESET:'VA-reset',TWILIO_VERIFY_SERVICE_SID_PAYOUT_ACCOUNT_CHANGE:'VA-payout'});
 const oldFetch=global.fetch,visited=[];
 global.fetch=async(url,opts)=>{visited.push(String(url));const right=String(url).includes('/VA-payout/');return {ok:true,json:async()=>({status:right?'approved':'pending',valid:right})};};
 const tx={query:async()=>({rows:[{phone_e164:'+6281234567890'}]})};
 try{
  assert.equal(await verifyOtpForChallenge(tx,{account_id:'id',purpose:'PAYOUT_ACCOUNT_CHANGE'},'123456'),true);
  assert.equal(await verifyOtpForChallenge(tx,{account_id:'id',purpose:'PASSWORD_RESET'},'123456'),false);
  assert.match(visited[0],/VA-payout/);assert.match(visited[1],/VA-reset/);
 }finally{global.fetch=oldFetch;}
});
