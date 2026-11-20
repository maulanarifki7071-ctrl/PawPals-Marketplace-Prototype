import {createHash,createHmac} from 'node:crypto';
import {query,transaction} from '../shared/db/database';

export function outboxJobId(key:string,attempt:number){return createHash('sha256').update(`${key}#${attempt}`).digest('hex');}
/**
 * Deliver outbox events to an idempotent notification/operations gateway.
 * The receiver MUST deduplicate by event_key. A successful HTTP 2xx is required
 * before acknowledging the database row. No configured gateway => no false delivery.
 */
export async function consumeOutboxEvent(eventKey:string):Promise<void>{
 const exists=await query(`SELECT 1 FROM outbox_consumptions WHERE event_key=$1`,[eventKey]);
 if(exists.rows[0])return;
 const e=(await query<any>(`SELECT * FROM outbox_events WHERE event_key=$1 AND status='PUBLISHED'`,[eventKey])).rows[0];
 if(!e)throw new Error('OUTBOX_EVENT_NOT_PUBLISHED');
 const url=process.env.NOTIFICATION_WEBHOOK_URL,secret=process.env.NOTIFICATION_WEBHOOK_SECRET;
 if(!url||!secret)throw new Error('NOTIFICATION_GATEWAY_UNCONFIGURED');
 const parsed=new URL(url);
 if(parsed.protocol!=='https:'&&!(process.env.NODE_ENV!=='production'&&['localhost','127.0.0.1'].includes(parsed.hostname)))throw new Error('NOTIFICATION_GATEWAY_REQUIRES_HTTPS');
 const payload=JSON.stringify({event_key:e.event_key,event_type:e.event_type,aggregate_type:e.aggregate_type,aggregate_id:e.aggregate_id,payload:e.payload_json});
 const signature=createHmac('sha256',secret).update(payload).digest('hex');
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
 try{
  const r=await fetch(url,{method:'POST',headers:{'content-type':'application/json','X-PawPals-Event-Key':eventKey,'X-PawPals-Signature':signature},body:payload,signal:controller.signal});
  if(!r.ok)throw new Error(`NOTIFICATION_GATEWAY_HTTP_${r.status}`);
 }finally{clearTimeout(timer);}
 await transaction(async tx=>{
  await tx.query(`INSERT INTO outbox_consumptions(event_key,delivery_target) VALUES($1,'WEBHOOK') ON CONFLICT DO NOTHING`,[eventKey]);
 });
}
/** Publish or re-publish unacknowledged events, never losing records on failure. */
export async function publishOutboxToBullMq(queue:any,limit=100):Promise<number>{
 return transaction(async tx=>{
  const rows=await tx.query(`SELECT e.* FROM outbox_events e
  WHERE ((e.status='PENDING' AND e.available_at<=now())
   OR (e.status='PUBLISHED' AND e.published_at<now()-interval '5 minutes'))
   AND NOT EXISTS(SELECT 1 FROM outbox_consumptions c WHERE c.event_key=e.event_key)
  ORDER BY e.created_at FOR UPDATE OF e SKIP LOCKED LIMIT $1`,[limit]);
  let n=0;
  for(const e of rows.rows){
   if(Number(e.attempt_count)>=8){
    await tx.query(`UPDATE outbox_events SET status='DEAD_LETTER',last_error='Delivery acknowledgement not received after 8 publish cycles' WHERE id=$1`,[e.id]);continue;
   }
   const attempt=Number(e.attempt_count)+1;
   await queue.add(e.event_type,{event_key:e.event_key},{jobId:outboxJobId(e.event_key,attempt),attempts:5,backoff:{type:'exponential',delay:10000},removeOnComplete:1000,removeOnFail:1000});
   await tx.query(`UPDATE outbox_events SET status='PUBLISHED',published_at=now(),attempt_count=$2,last_error=NULL WHERE id=$1`,[e.id,attempt]);n++;
  }
  return n;
 });
}
