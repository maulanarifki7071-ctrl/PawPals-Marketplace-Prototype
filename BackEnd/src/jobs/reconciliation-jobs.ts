import {query,transaction} from '../shared/db/database';
import {env} from '../config/env';
import {fetchMidtransStatus} from '../shared/providers/payment';
import {applyVerifiedPaymentEvent} from '../shared/domain/payment-events';
import {postRefundSucceeded} from '../shared/domain/finance';
import {outbox} from '../shared/domain/audit';

/** Poll provider independently of webhook delivery; no client status is authoritative. */
export async function reconcilePendingPayments(limit=50):Promise<number>{
 if(!env.midtransServerKey)return 0;
 const list=await query<any>(`SELECT provider_order_reference FROM payments
  WHERE provider='MIDTRANS' AND status IN ('PENDING','EXPIRED') AND created_at>=now()-interval '30 days'
  ORDER BY expires_at LIMIT $1`,[limit]);let done=0;
 for(const p of list.rows){
  try{
   const body=await fetchMidtransStatus(p.provider_order_reference);
   const status=String(body.transaction_status??'').toLowerCase();
   if(['settlement','capture','deny','cancel','failure','expire'].includes(status)){
    await applyVerifiedPaymentEvent(body);done++;
   }
  }catch{/* Provider unavailability never implies payment failure or success. */}
 }
 return done;
}

/** Only provider evidence for the exact refund_key and amount may settle ambiguity. */
export function providerRefundOutcome(body:any,refundId:string,amount:number):'SUCCEEDED'|'FAILED'|'UNKNOWN'{
 const key=`pawpals-refund-${refundId}`;
 const arr=Array.isArray(body?.refunds)?body.refunds:[];
 const x=arr.find((v:any)=>String(v.refund_key??'')===key&&Number(v.amount)===amount);
 if(!x)return 'UNKNOWN';
 const status=String(x.status??x.refund_status??'').toLowerCase();
 if(['success','succeeded','refunded','completed'].includes(status))return 'SUCCEEDED';
 if(['failed','rejected','cancelled'].includes(status))return 'FAILED';
 return 'UNKNOWN';
}
export async function reconcileProcessingRefunds(limit=50):Promise<number>{
 if(!env.midtransServerKey)return 0;
 const list=await query<any>(`SELECT rf.*,p.provider_order_reference FROM refunds rf
  JOIN payments p ON p.id=rf.payment_id WHERE p.provider='MIDTRANS' AND rf.status='PROCESSING'
  ORDER BY rf.processing_at LIMIT $1`,[limit]);let done=0;
 for(const r of list.rows){
  try{
   const body=await fetchMidtransStatus(r.provider_order_reference);
   const outcome=providerRefundOutcome(body,r.id,Number(r.amount));
   if(outcome==='UNKNOWN')continue;
   const changed=await transaction(async tx=>{
    const rf=(await tx.query(`SELECT * FROM refunds WHERE id=$1 FOR UPDATE`,[r.id])).rows[0];
    if(!rf||rf.status!=='PROCESSING')return false;
    if(outcome==='SUCCEEDED'){
     const success=(await tx.query(`UPDATE refunds SET status='SUCCEEDED',succeeded_at=now(),updated_at=now() WHERE id=$1 RETURNING *`,[r.id])).rows[0];
     await postRefundSucceeded(tx,success);
    }else await tx.query(`UPDATE refunds SET status='FAILED',failed_at=now(),updated_at=now() WHERE id=$1`,[r.id]);
    await tx.query(`UPDATE refund_attempts SET is_ambiguous=false,completed_at=now()
      WHERE refund_id=$1 AND completed_at IS NULL`,[r.id]);
    await outbox(tx,`refund:${r.id}:${outcome.toLowerCase()}`,'REFUND',r.id,`REFUND_${outcome}`,{reconciled:true});
    return true;
   });
   if(changed)done++;
  }catch{/* No blind refund retry after timeout; retain PROCESSING for later reconciliation. */}
 }
 return done;
}
