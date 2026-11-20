import {env} from '../../config/env';
export async function postPaidEconomics(tx:any,payment:any,booking:any){const pol=(await tx.query(`SELECT commission_rate_bps FROM booking_policy_snapshots WHERE booking_id=$1`,[booking.id])).rows[0];const bps=Number(pol?.commission_rate_bps??env.commissionRateBps);const commission=Math.round(Number(payment.amount)*bps/10000),earning=Number(payment.amount)-commission;await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'PAYMENT_RECEIVED','PAYMENT_PAID',$4,$5) ON CONFLICT DO NOTHING`,[booking.vendor_id,booking.id,payment.id,`${payment.id}:received`,Number(payment.amount)]);const le=await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'SERVICE_EARNING','PAYMENT_PAID',$4,$5) ON CONFLICT DO NOTHING RETURNING id`,[booking.vendor_id,booking.id,payment.id,`${payment.id}:earning`,earning]);if(commission>0)await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'PLATFORM_COMMISSION','PAYMENT_PAID',$4,$5) ON CONFLICT DO NOTHING`,[booking.vendor_id,booking.id,payment.id,`${payment.id}:commission`,commission]);if(le.rows[0])await tx.query(`INSERT INTO settlement_items(vendor_id,booking_id,origin_ledger_entry_id,source_type,status,amount_signed) VALUES($1,$2,$3,'SERVICE_EARNING','PENDING',$4)`,[booking.vendor_id,booking.id,le.rows[0].id,earning]);}
export async function createRefundObligation(tx:any,input:{paymentId:string;amount:number;initiatorType:string;initiatedBy?:string|null;reasonCode?:string|null;reasonText?:string|null}){const p=await tx.query(`SELECT * FROM payments WHERE id=$1 FOR UPDATE`,[input.paymentId]);if(!p.rows[0])throw new Error('PAYMENT_NOT_FOUND');const used=await tx.query(`SELECT COALESCE(sum(amount),0)::bigint used FROM refunds WHERE payment_id=$1 AND status IN ('REQUESTED','PROCESSING','SUCCEEDED')`,[input.paymentId]);if(Number(used.rows[0].used)+input.amount>Number(p.rows[0].amount))throw new Error('REFUND_EXCEEDS_PAYMENT');return (await tx.query(`INSERT INTO refunds(payment_id,amount,reason_code,reason_text,initiator_type,initiated_by_account_id) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,[input.paymentId,input.amount,input.reasonCode??null,input.reasonText??null,input.initiatorType,input.initiatedBy??null])).rows[0];}

export async function reverseServiceEconomicsForCancellation(tx:any, booking:any, cancellationEventId:string){
  const earn=await tx.query(`SELECT * FROM ledger_entries WHERE booking_id=$1 AND posting_type='SERVICE_EARNING' ORDER BY created_at LIMIT 1`,[booking.id]);
  if(earn.rows[0]){
    await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'SERVICE_EARNING_REVERSAL','BOOKING_CANCELLATION',$4,$5) ON CONFLICT DO NOTHING`,[booking.vendor_id,booking.id,earn.rows[0].payment_id,`${cancellationEventId}:earning-reversal`,-Math.abs(Number(earn.rows[0].amount_signed))]);
    const items=await tx.query(`SELECT id,status FROM settlement_items WHERE origin_ledger_entry_id=$1 FOR UPDATE`,[earn.rows[0].id]);
    for(const it of items.rows){
      if(['PENDING','HOLD','AVAILABLE'].includes(it.status)){
        await tx.query(`UPDATE settlement_items SET status='REVERSED',reversed_at=now(),updated_at=now() WHERE id=$1`,[it.id]);
        await tx.query(`INSERT INTO settlement_status_history(settlement_item_id,from_status,to_status,reason) VALUES($1,$2,'REVERSED','BOOKING_CANCELLED')`,[it.id,it.status]);
      }
    }
  }
  const commission=await tx.query(`SELECT * FROM ledger_entries WHERE booking_id=$1 AND posting_type='PLATFORM_COMMISSION' AND canonical_event_type='PAYMENT_PAID' ORDER BY created_at LIMIT 1`,[booking.id]);
  if(commission.rows[0]) await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'PLATFORM_COMMISSION_REVERSAL','BOOKING_CANCELLATION',$4,$5) ON CONFLICT DO NOTHING`,[booking.vendor_id,booking.id,commission.rows[0].payment_id,`${cancellationEventId}:commission-reversal`,-Math.abs(Number(commission.rows[0].amount_signed))]);
}

export async function createCancellationCompensation(tx:any, booking:any, cancellation:any, retained:number, commissionRateBps:number){
  if(retained<=0) return null;
  const commission=Math.round(retained*commissionRateBps/10000), earning=retained-commission;
  const payment=(await tx.query(`SELECT id FROM payments WHERE booking_id=$1`,[booking.id])).rows[0];
  if(!payment) return null;
  const le=await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'CANCELLATION_COMPENSATION','CUSTOMER_CANCELLATION',$4,$5) ON CONFLICT DO NOTHING RETURNING id`,[booking.vendor_id,booking.id,payment.id,`${cancellation.id}:compensation`,earning]);
  if(commission>0) await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed) VALUES($1,$2,$3,'PLATFORM_COMMISSION','CUSTOMER_CANCELLATION',$4,$5) ON CONFLICT DO NOTHING`,[booking.vendor_id,booking.id,payment.id,`${cancellation.id}:commission`,commission]);
  if(le.rows[0]){
    const p=(await tx.query(`SELECT settlement_hold_minutes FROM booking_policy_snapshots WHERE booking_id=$1`,[booking.id])).rows[0];
    const holdBase=cancellation.fault_finalized_at && new Date(cancellation.fault_finalized_at)>new Date(cancellation.claim_window_ends_at)?cancellation.fault_finalized_at:cancellation.claim_window_ends_at;
    await tx.query(`INSERT INTO settlement_items(vendor_id,booking_id,origin_ledger_entry_id,source_type,status,amount_signed,hold_until) VALUES($1,$2,$3,'CANCELLATION_COMPENSATION','HOLD',$4,$5::timestamptz + ($6||' minutes')::interval)`,[booking.vendor_id,booking.id,le.rows[0].id,earning,holdBase,String(p?.settlement_hold_minutes??env.settlementHoldMinutes)]);
  }
  return {retained_base:retained,commission,vendor_compensation:earning};
}

/**
 * Align payable vendor funds to the latest canonical paid/refunded and cancellation
 * state. A refund is NOT the vendor deduction: only the vendor's net of commission
 * is deducted. Historical SETTLED/ALLOCATED rows are immutable; compensating
 * negative entries carry the debt forward rather than changing paid history.
 * Caller owns the booking/payment transaction and must lock the booking first.
 */
export async function alignSettlementToBooking(tx:any, bookingId:string, eventId:string):Promise<void>{
  const context=(await tx.query(`SELECT b.id,b.vendor_id,b.status,p.id payment_id,p.amount payment_amount,p.status payment_status,
    bp.commission_rate_bps,bc.fault_party,bc.retained_settlement_base_amount
    FROM bookings b JOIN payments p ON p.booking_id=b.id
    JOIN booking_policy_snapshots bp ON bp.booking_id=b.id
    LEFT JOIN booking_cancellations bc ON bc.booking_id=b.id
    WHERE b.id=$1 FOR UPDATE OF b`,[bookingId])).rows[0];
  if(!context||context.payment_status!=='PAID') return;
  const succeeded=(await tx.query(`SELECT COALESCE(sum(amount),0)::bigint total FROM refunds WHERE payment_id=$1 AND status='SUCCEEDED'`,[context.payment_id])).rows[0];
  if(context.fault_party==='PENDING_REVIEW')return; // No final entitlement while cancellation attribution is unresolved.
  const net=Math.max(0,Number(context.payment_amount)-Number(succeeded.total));
  const cancelled=['CUSTOMER_CANCELLED','VENDOR_CANCELLED','PLATFORM_CANCELLED'].includes(context.status);
  const base=cancelled?(context.fault_party==='CUSTOMER'?Math.min(net,Number(context.retained_settlement_base_amount??0)):0)
    :context.status==='EXPIRED'?0:net;
  const bps=Number(context.commission_rate_bps);
  const targetCommission=Math.round(base*bps/10000);
  const target=base-targetCommission;
  const existingCommission=(await tx.query(`SELECT COALESCE(sum(amount_signed),0)::bigint net FROM ledger_entries
    WHERE booking_id=$1 AND posting_type IN ('PLATFORM_COMMISSION','PLATFORM_COMMISSION_REVERSAL')`,[bookingId])).rows[0];
  const commissionDelta=targetCommission-Number(existingCommission.net);
  if(commissionDelta<0){
   await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed)
    VALUES($1,$2,$3,'PLATFORM_COMMISSION_REVERSAL','COMMISSION_RECONCILIATION',$4,$5)
    ON CONFLICT DO NOTHING`,[context.vendor_id,bookingId,context.payment_id,`${eventId}:commission` ,commissionDelta]);
  }
  const current=(await tx.query(`SELECT COALESCE(sum(amount_signed),0)::bigint net FROM settlement_items
    WHERE booking_id=$1 AND status<>'REVERSED'`,[bookingId])).rows[0];
  const difference=target-Number(current.net);
  if(difference>=0)return; // positive earnings originate in PAYMENT_PAID / CANCELLATION_COMPENSATION.
  const origin=(await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,posting_type,canonical_event_type,canonical_event_id,amount_signed)
    VALUES($1,$2,$3,'NEGATIVE_ADJUSTMENT','SETTLEMENT_RECONCILIATION',$4,$5)
    ON CONFLICT DO NOTHING RETURNING id`,[context.vendor_id,bookingId,context.payment_id,eventId,difference])).rows[0];
  if(!origin)return;
  const open=(await tx.query(`SELECT status,hold_until FROM settlement_items
    WHERE booking_id=$1 AND status IN ('PENDING','HOLD','AVAILABLE') ORDER BY CASE status WHEN 'PENDING' THEN 0 WHEN 'HOLD' THEN 1 ELSE 2 END LIMIT 1 FOR UPDATE`,[bookingId])).rows[0];
  // Negative adjustments follow unsettled funds' clock; already allocated/paid
  // vendor funds instead create an available debit against future payouts.
  const status=open?.status==='PENDING'?'PENDING':open?.status==='HOLD'?'HOLD':'AVAILABLE';
  const holdUntil=status==='HOLD'?open.hold_until:null;
  await tx.query(`INSERT INTO settlement_items(vendor_id,booking_id,origin_ledger_entry_id,source_type,status,amount_signed,hold_until,available_at)
    VALUES($1,$2,$3,'NEGATIVE_ADJUSTMENT',$4::settlement_status,$5,$6,CASE WHEN $4::settlement_status='AVAILABLE'::settlement_status THEN now() ELSE NULL END)`,
    [context.vendor_id,bookingId,origin.id,status,difference,holdUntil]);
}

export async function postRefundSucceeded(tx:any, refund:any){
  const ctx=(await tx.query(`SELECT p.booking_id,b.vendor_id FROM payments p JOIN bookings b ON b.id=p.booking_id WHERE p.id=$1`,[refund.payment_id])).rows[0];
  if(!ctx)return;
  const le=await tx.query(`INSERT INTO ledger_entries(vendor_id,booking_id,payment_id,refund_id,posting_type,canonical_event_type,canonical_event_id,amount_signed)
    VALUES($1,$2,$3,$4,'REFUND','REFUND_SUCCEEDED',$5,$6) ON CONFLICT DO NOTHING RETURNING id`,
    [ctx.vendor_id,ctx.booking_id,refund.payment_id,refund.id,refund.id,-Math.abs(Number(refund.amount))]);
  if(le.rows[0])await alignSettlementToBooking(tx,ctx.booking_id,`refund:${refund.id}:vendor-adjustment`);
}
