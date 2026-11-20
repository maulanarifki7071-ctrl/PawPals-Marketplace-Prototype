const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
process.env.NODE_ENV='test';
const pg=require('pg');
const eventKey='booking:test:confirmed';
let data,trace;
pg.Pool=class {async query(sql,params){return handle(sql,params);}async connect(){let snapshot;return {
 async query(sql,params){if(sql==='BEGIN'){snapshot=structuredClone(data);return {rows:[]};}
 if(sql==='COMMIT')return {rows:[]};
 if(sql==='ROLLBACK'){data=snapshot;return {rows:[]};}
 return handle(sql,params);
 },release(){} };}};
function handle(sql,params=[]){trace.push(sql);
 if(sql.includes('SELECT e.* FROM outbox_events')){const e=data.event;const old=e.published_at&&Date.now()-new Date(e.published_at).getTime()>300000;
  return {rows:(!data.consumed&&(e.status==='PENDING'||e.status==='PUBLISHED'&&old))?[{...e}]:[]};}
 if(sql.includes("UPDATE outbox_events SET status='PUBLISHED'")){data.event.status='PUBLISHED';data.event.attempt_count=params[1];data.event.published_at=new Date();return {rows:[]};}
 if(sql.includes("UPDATE outbox_events SET status='DEAD_LETTER'")){data.event.status='DEAD_LETTER';return {rows:[]};}
 if(sql.includes('SELECT 1 FROM outbox_consumptions'))return {rows:data.consumed?[{a:1}]:[]};
 if(sql.includes('SELECT * FROM outbox_events WHERE event_key'))return {rows:data.event.status==='PUBLISHED'?[{...data.event}]:[]};
 if(sql.includes('INSERT INTO outbox_consumptions')){data.consumed=true;return {rows:[]};}
 throw Error('Unexpected SQL: '+sql);
}
const {publishOutboxToBullMq,consumeOutboxEvent}=require('../dist/jobs/outbox-events');
beforeEach(()=>{trace=[];data={event:{id:'event',event_key:eventKey,event_type:'BOOKING_CONFIRMED',aggregate_type:'BOOKING',aggregate_id:'booking-id',payload_json:{booking_id:'booking-id'},status:'PENDING',attempt_count:0},consumed:false};});
test('queue publication failure rolls back outbox status, retry reuses durable event',async()=>{
 const bad={add:async()=>{throw Error('Redis is unavailable');}};
 await assert.rejects(publishOutboxToBullMq(bad),/Redis is unavailable/);
 assert.equal(data.event.status,'PENDING');
 const queue={jobs:[],async add(name,payload,opts){this.jobs.push({name,payload,opts});}};
 assert.equal(await publishOutboxToBullMq(queue),1);
 assert.equal(data.event.status,'PUBLISHED');assert.equal(queue.jobs.length,1);
 assert.match(queue.jobs[0].opts.jobId,/^[0-9a-f]{64}$/);
});
test('missing gateway never marks event consumed and recovery republish uses new job ID',async()=>{
 const queue={jobs:[],async add(name,payload,opts){this.jobs.push({name,payload,opts});}};
 await publishOutboxToBullMq(queue);
 delete process.env.NOTIFICATION_WEBHOOK_URL;delete process.env.NOTIFICATION_WEBHOOK_SECRET;
 await assert.rejects(consumeOutboxEvent(eventKey),/NOTIFICATION_GATEWAY_UNCONFIGURED/);
 assert.equal(data.consumed,false);
 data.event.published_at=new Date(Date.now()-400000);
 assert.equal(await publishOutboxToBullMq(queue),1);
 assert.notEqual(queue.jobs[0].opts.jobId,queue.jobs[1].opts.jobId);
});
test('consumed event is acknowledged once and never republished',async()=>{
 const queue={jobs:[],async add(name,payload,opts){this.jobs.push({name,payload,opts});}};
 await publishOutboxToBullMq(queue);
 process.env.NOTIFICATION_WEBHOOK_URL='https://delivery.example/notifications';process.env.NOTIFICATION_WEBHOOK_SECRET='test-secret';
 const oldFetch=global.fetch;let received=0;
 global.fetch=async(_url,opts)=>{received++;assert.equal(opts.headers['X-PawPals-Event-Key'],eventKey);return {ok:true};};
 try{await consumeOutboxEvent(eventKey);await consumeOutboxEvent(eventKey);
  assert.equal(received,1);data.event.published_at=new Date(Date.now()-400000);
  assert.equal(await publishOutboxToBullMq(queue),0);assert.equal(data.consumed,true);
 }finally{global.fetch=oldFetch;}
});
