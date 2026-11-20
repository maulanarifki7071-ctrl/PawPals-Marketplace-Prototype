import {query,transaction} from '../shared/db/database';
import {decryptSensitive} from '../shared/security/encryption';
import {verifyDisbursementRecipient,isDisbursementConfigured,submitDisbursement,fetchDisbursementStatus,disbursementProviderName,PayoutResult} from '../shared/providers/disbursement';
import {outbox} from '../shared/domain/audit';

export async function verifyPendingRecipients(limit=20):Promise<number>{
 if(!isDisbursementConfigured())return 0;
 const rows=await query<any>(`SELECT pa.id,pa.bank_code,pa.account_holder_name,pa.account_number_encrypted
 FROM vendor_payout_accounts pa JOIN vendors v ON v.id=pa.vendor_id
 WHERE pa.is_active=true AND pa.verified_at IS NULL AND v.status='ACTIVE'
 ORDER BY pa.created_at LIMIT $1`,[limit]);let n=0;
 for(const a of rows.rows){
  try{
   const verified=await verifyDisbursementRecipient({id:a.id,bank_code:a.bank_code,account_holder_name:a.account_holder_name,account_number:decryptSensitive(a.account_number_encrypted)});
   if(verified.verified){await query(`UPDATE vendor_payout_accounts SET verified_at=now(),provider_recipient_ref=$2,updated_at=now()
    WHERE id=$1 AND verified_at IS NULL AND is_active=true`,[a.id,verified.ref]);n++;}
  }catch{/* Provider failure is not an account approval. Next tick will retry. */}
 }
 return n;
}

async function finalizePayout(id:string,result:PayoutResult,reason='PROVIDER_STATUS_RECONCILED'){
 return transaction(async tx=>{
  const p=(await tx.query(`SELECT * FROM payouts WHERE id=$1 FOR UPDATE`,[id])).rows[0];
  if(!p||['PAID','FAILED'].includes(p.status))return false;
  if(result==='PROCESSING')return false;
  const to=result==='PAID'?'PAID':'FAILED';
  await tx.query(`UPDATE payouts SET status=$2::payout_status,paid_at=CASE WHEN $2::payout_status='PAID'::payout_status THEN now() ELSE NULL END,
   failed_at=CASE WHEN $2::payout_status='FAILED'::payout_status THEN now() ELSE NULL END,
   failure_reason=CASE WHEN $2::payout_status='FAILED'::payout_status THEN $3 ELSE NULL END,updated_at=now() WHERE id=$1`,[id,to,reason]);
  await tx.query(`INSERT INTO payout_status_history(payout_id,from_status,to_status,reason) VALUES($1,$2,$3,$4)`,[id,p.status,to,reason]);
  if(to==='PAID'){
   await tx.query(`UPDATE settlement_items SET status='SETTLED',settled_at=now(),updated_at=now()
    WHERE id IN (SELECT settlement_item_id FROM payout_items WHERE payout_id=$1) AND status='ALLOCATED'`,[id]);
   await tx.query(`INSERT INTO settlement_status_history(settlement_item_id,from_status,to_status,reason)
    SELECT settlement_item_id,'ALLOCATED','SETTLED','PROVIDER_VERIFIED_PAYOUT' FROM payout_items WHERE payout_id=$1`,[id]);
   await tx.query(`INSERT INTO ledger_entries(vendor_id,posting_type,canonical_event_type,canonical_event_id,amount_signed)
    VALUES($1,'PAYOUT_DISBURSED','PAYOUT_PAID',$2,$3) ON CONFLICT DO NOTHING`,[p.vendor_id,id,-Number(p.total_amount)]);
  }else{
   await tx.query(`UPDATE settlement_items SET status='AVAILABLE',available_at=now(),updated_at=now()
    WHERE id IN (SELECT settlement_item_id FROM payout_items WHERE payout_id=$1) AND status='ALLOCATED'`,[id]);
   await tx.query(`INSERT INTO settlement_status_history(settlement_item_id,from_status,to_status,reason)
    SELECT settlement_item_id,'ALLOCATED','AVAILABLE','PAYOUT_FAILED_RELEASED' FROM payout_items WHERE payout_id=$1`,[id]);
   await tx.query(`UPDATE payout_items SET released_at=now() WHERE payout_id=$1 AND released_at IS NULL`,[id]);
  }
  await outbox(tx,`payout:${id}:${to.toLowerCase()}`,'PAYOUT',id,`PAYOUT_${to}`,{});
  return true;
 });
}

export async function dispatchQueuedPayouts(limit=20):Promise<number>{
 if(!isDisbursementConfigured())return 0;
 const list=await query<any>(`SELECT p.id FROM payouts p WHERE p.status='QUEUED' ORDER BY p.created_at LIMIT $1`,[limit]);let n=0;
 for(const r of list.rows){
  const payload=await transaction(async tx=>{
   const p=(await tx.query(`SELECT p.*,pa.provider_recipient_ref,pa.verified_at,pa.security_hold_until,pa.is_active
    FROM payouts p JOIN vendor_payout_accounts pa ON pa.id=p.payout_account_id WHERE p.id=$1 FOR UPDATE OF p`,[r.id])).rows[0];
   if(!p||p.status!=='QUEUED')return null;
   if(!p.is_active||!p.verified_at||!p.provider_recipient_ref||p.security_hold_until&&new Date(p.security_hold_until)>new Date())return null;
   const conflict=await tx.query(`SELECT 1 FROM payout_items pi JOIN settlement_items si ON si.id=pi.settlement_item_id
    WHERE pi.payout_id=$1 AND (EXISTS(SELECT 1 FROM refunds rf JOIN payments pm ON pm.id=rf.payment_id
     WHERE pm.booking_id=si.booking_id AND rf.status IN ('REQUESTED','PROCESSING'))
    OR EXISTS(SELECT 1 FROM support_cases c WHERE c.booking_id=si.booking_id AND c.status IN ('OPEN','TRIAGED','INVESTIGATING'))) LIMIT 1`,[p.id]);
   if(conflict.rows[0])return null;
   await tx.query(`UPDATE payouts SET status='PROCESSING',provider=$2,provider_payout_ref=$1,submitted_at=now(),updated_at=now() WHERE id=$1`,[p.id,disbursementProviderName()]);
   await tx.query(`INSERT INTO payout_status_history(payout_id,from_status,to_status,reason)
    VALUES($1,'QUEUED','PROCESSING','PROVIDER_DISPATCH_STARTED')`,[p.id]);
   return {id:p.id,recipientRef:p.provider_recipient_ref,amount:Number(p.total_amount)};
  });
  if(!payload)continue;
  // A transport timeout is ambiguous: retain PROCESSING and only POLL provider status.
  try{const status=await submitDisbursement(payload);await finalizePayout(payload.id,status.status,'PROVIDER_DISPATCH_RESULT');}catch{/* Reconcile before considering any retry. */}
  n++;
 }
 return n;
}
export async function reconcileProcessingPayouts(limit=50):Promise<number>{
 if(!isDisbursementConfigured())return 0;
 const list=await query<any>(`SELECT id FROM payouts WHERE status='PROCESSING' ORDER BY submitted_at LIMIT $1`,[limit]);let n=0;
 for(const p of list.rows){
  try{
   const s=await fetchDisbursementStatus(p.id);
   if(await finalizePayout(p.id,s.status))n++;
  }catch(error){
   // Do not guess provider outcomes. Log only an error code and internal payout id,
   // never provider credentials, account details or full request payloads.
   const code=(error as {code?:unknown})?.code;
   console.error('PawPals payout reconciliation failed',{payout_id:p.id,error_code:typeof code==='string'?code:'UNKNOWN'});
  }
 }
 return n;
}
export async function reconcilePayoutById(id:string){
 if(!isDisbursementConfigured())return {payout_id:id,reconciliation:'PROVIDER_NOT_CONFIGURED'};
 const result=await fetchDisbursementStatus(id);await finalizePayout(id,result.status);
 const p=(await query<any>(`SELECT status FROM payouts WHERE id=$1`,[id])).rows[0];return {payout_id:id,status:p?.status??'UNKNOWN',reconciliation:'PROVIDER_VERIFIED'};
}
