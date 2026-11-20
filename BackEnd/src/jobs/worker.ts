import 'dotenv/config';
import {expirePaymentHolds,processRequestedRefunds,releaseEligibleSettlements,allocateScheduledPayouts} from './domain-jobs';
import {reconcilePendingPayments,reconcileProcessingRefunds} from './reconciliation-jobs';
import {verifyPendingRecipients,dispatchQueuedPayouts,reconcileProcessingPayouts} from './payout-jobs';
import {publishOutboxToBullMq,consumeOutboxEvent} from './outbox-events';
import {closeDatabase} from '../shared/db/database';
import {env} from '../config/env';

let queue:any,consumer:any,redis:any;
let lastRedisLog=0;function reportRedis(error:any){if(Date.now()-lastRedisLog>60000){lastRedisLog=Date.now();console.warn('Redis/queue unavailable; outbox events remain pending:',String(error?.message??error));}}
if(process.env.REDIS_URL){
 const Bull=require('bullmq'),Redis=require('ioredis');
 redis=new Redis(process.env.REDIS_URL,{maxRetriesPerRequest:null});
 redis.on('error',reportRedis);
 queue=new Bull.Queue('pawpals-domain-events',{connection:redis});
 consumer=new Bull.Worker('pawpals-domain-events',async(job:any)=>consumeOutboxEvent(job.data.event_key),{
  connection:redis,concurrency:4,
 });
 queue.on('error',reportRedis);consumer.on('error',reportRedis);
 consumer.on('failed',(job:any,error:any)=>console.error('outbox consumer failed',{job_id:job?.id,error:String(error?.message??error)}));
}else if(env.nodeEnv==='production')throw new Error('REDIS_URL is required for the production worker.');

let running=false,stopped=false;
export async function tick(){
 if(running||stopped)return;
 running=true;
 try{
  // Reconcile provider payments before expiring local holds; no blind retries.
  const payments=await reconcilePendingPayments();
  const refundsReconciled=await reconcileProcessingRefunds();
  const expired=await expirePaymentHolds();
  const refunds=await processRequestedRefunds();
  const recipients=await verifyPendingRecipients();
  const payoutsReconciled=await reconcileProcessingPayouts();
  const settlements=await releaseEligibleSettlements();
  let payouts=0;
  // Weekly payout: Monday UTC. The exact cadence is configurable through deployment scheduler.
  if(new Date().getUTCDay()===1)payouts=await allocateScheduledPayouts();
  const payoutsDispatched=await dispatchQueuedPayouts();
  const delivered=queue&&redis?.status==='ready'?await publishOutboxToBullMq(queue):0;
  if(Object.values({payments,refundsReconciled,expired,refunds,recipients,payoutsReconciled,settlements,payouts,payoutsDispatched,delivered}).some(x=>x>0))
   console.log('PawPals worker activity',{payments,refundsReconciled,expired,refunds,recipients,payoutsReconciled,settlements,payouts,payoutsDispatched,delivered});
 }catch(error){console.error('PawPals worker tick failed',error);}
 finally{running=false;}
}
const interval=setInterval(()=>void tick(),60_000);
void tick();
async function stop(){if(stopped)return;stopped=true;clearInterval(interval);
 try{await consumer?.close();await queue?.close();await redis?.quit();await closeDatabase();}catch(e){console.error('Worker shutdown error',e);}}
process.on('SIGTERM',()=>void stop());process.on('SIGINT',()=>void stop());
