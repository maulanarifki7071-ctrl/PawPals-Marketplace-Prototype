import express from 'express';
import {asyncHandler} from '../../shared/http/async-handler';
import {ok,page,pagination} from '../../shared/http/respond';
import {bodyObject,requireUuid,integer,requireString,requireEnum} from '../../shared/http/validate';
import {query,transaction} from '../../shared/db/database';
import {requireActive,requirePermission} from '../../middleware/auth';
import {AppError} from '../../shared/errors/app-error';
import {verifyMidtransWebhook,createMidtransCheckout,submitRefund} from '../../shared/providers/payment';
import {applyVerifiedPaymentEvent} from '../../shared/domain/payment-events';
import {createMockCheckout,createMockPaymentEvent,requireLocalMockPayments,MockOutcome} from '../../shared/providers/mock-payment';
import {createRefundObligation,postRefundSucceeded} from '../../shared/domain/finance';
import {audit,outbox} from '../../shared/domain/audit';
export const paymentRouter=express.Router();

paymentRouter.post('/payments/:id/checkout-session',requireActive,asyncHandler(async(req,res)=>{
 const id=requireUuid(req.params.id);
 const r=await query<any>(`SELECT p.*,b.customer_account_id,a.display_name FROM payments p
  JOIN bookings b ON b.id=p.booking_id JOIN accounts a ON a.id=b.customer_account_id
  WHERE p.id=$1 AND b.customer_account_id=$2`,[id,req.account.id]);
 const p=r.rows[0];
 if(!p)throw new AppError(404,'PAYMENT_NOT_FOUND','Payment not found.');
 if(p.status!=='PENDING'||new Date(p.expires_at)<=new Date())throw new AppError(409,'PAYMENT_NOT_PAYABLE','Payment is not payable from its current state.');
 if(p.provider==='MOCK')return ok(res,createMockCheckout(p));
 if(p.provider==='MIDTRANS')return ok(res,await createMidtransCheckout(p,{display_name:p.display_name}));
 throw new AppError(503,'PAYMENT_PROVIDER_UNAVAILABLE','Unsupported payment provider.');
}));
// Deliberately absent unless explicit opt-in AND loopback AND owner session.
// This is NOT the public Midtrans webhook, and it never trusts client amount/order values.
paymentRouter.post('/dev/payments/:id/simulate',requireActive,requireLocalMockPayments,asyncHandler(async(req,res)=>{
 const id=requireUuid(req.params.id);
 const b=bodyObject(req.body);
 const outcome=requireEnum(b,'outcome',['PAID','FAILED','EXPIRED']) as MockOutcome;
 if(Object.keys(b).some(k=>k!=='outcome'))throw new AppError(400,'VALIDATION_ERROR','Only outcome may be supplied.');
 const r=await query<any>(`SELECT p.*,b.customer_account_id FROM payments p JOIN bookings b ON b.id=p.booking_id
  WHERE p.id=$1 AND b.customer_account_id=$2 AND p.provider='MOCK'`,[id,req.account.id]);
 const p=r.rows[0];
 if(!p)throw new AppError(404,'PAYMENT_NOT_FOUND','Mock payment not found.');
 if(p.status!=='PENDING'){
  if(p.status===outcome){ok(res,{duplicate:true,payment_id:p.id,status:p.status,provider:'MOCK'});return;}
  throw new AppError(409,'PAYMENT_NOT_PAYABLE','Payment is already in a terminal state.');
 }
 if(outcome==='PAID'&&new Date(p.expires_at)<=new Date())
  throw new AppError(409,'PAYMENT_NOT_PAYABLE','Payment hold has expired. Create a new booking.');
 const result=await applyVerifiedPaymentEvent(createMockPaymentEvent(p,outcome),'MOCK');
 ok(res,{...result,provider:'MOCK',simulated:true});
}));
paymentRouter.get('/payments/:id',requireActive,asyncHandler(async(req,res)=>{const r=await query<any>(`SELECT p.id,p.booking_id,p.provider,p.provider_order_reference,p.amount,p.currency,p.status,p.expires_at,p.paid_at,p.failed_at,p.failure_code,p.created_at,p.updated_at FROM payments p JOIN bookings b ON b.id=p.booking_id WHERE p.id=$1 AND b.customer_account_id=$2`,[requireUuid(req.params.id),req.account.id]);if(!r.rows[0])throw new AppError(404,'PAYMENT_NOT_FOUND','Payment not found.');ok(res,r.rows[0]);}));
paymentRouter.post('/webhooks/midtrans/payments',asyncHandler(async(req,res)=>{
 const body=bodyObject(req.body);
 if(!verifyMidtransWebhook(body))throw new AppError(401,'INVALID_PROVIDER_SIGNATURE','Invalid payment provider signature.');
 ok(res,await applyVerifiedPaymentEvent(body));
}));
paymentRouter.get('/bookings/:id/refunds',requireActive,asyncHandler(async(req,res)=>{const r=await query<any>(`SELECT rf.* FROM refunds rf JOIN payments p ON p.id=rf.payment_id JOIN bookings b ON b.id=p.booking_id WHERE b.id=$1 AND b.customer_account_id=$2 ORDER BY rf.created_at DESC`,[requireUuid(req.params.id),req.account.id]);if(!r.rows.length){const b=await query(`SELECT 1 FROM bookings WHERE id=$1 AND customer_account_id=$2`,[req.params.id,req.account.id]);if(!b.rows[0])throw new AppError(404,'BOOKING_NOT_FOUND','Booking not found.');}ok(res,{items:r.rows});}));
const financeView=requirePermission('finance.payment.view'),refundManage=requirePermission('finance.refund.manage');
paymentRouter.get('/admin/payments',requireActive,financeView,asyncHandler(async(req,res)=>{const {page:p,limit,offset}=pagination(req.query);const [r,c]=await Promise.all([query<any>(`SELECT p.*,b.customer_account_id,b.vendor_id,b.status booking_status FROM payments p JOIN bookings b ON b.id=p.booking_id ORDER BY p.created_at DESC LIMIT $1 OFFSET $2`,[limit,offset]),query<any>(`SELECT count(*)::int total FROM payments`)]);page(res,r.rows,p,limit,c.rows[0].total);}));
paymentRouter.get('/admin/payments/:id',requireActive,financeView,asyncHandler(async(req,res)=>{const r=await query<any>(`SELECT p.*,b.status booking_status,b.customer_account_id,b.vendor_id FROM payments p JOIN bookings b ON b.id=p.booking_id WHERE p.id=$1`,[requireUuid(req.params.id)]);if(!r.rows[0])throw new AppError(404,'PAYMENT_NOT_FOUND','Payment not found.');ok(res,r.rows[0]);}));
paymentRouter.get('/admin/refunds',requireActive,refundManage,asyncHandler(async(req,res)=>{const {page:p,limit,offset}=pagination(req.query);const [r,c]=await Promise.all([query<any>(`SELECT r.*,p.booking_id FROM refunds r JOIN payments p ON p.id=r.payment_id ORDER BY r.created_at DESC LIMIT $1 OFFSET $2`,[limit,offset]),query<any>(`SELECT count(*)::int total FROM refunds`)]);page(res,r.rows,p,limit,c.rows[0].total);}));
paymentRouter.get('/admin/refunds/:id',requireActive,refundManage,asyncHandler(async(req,res)=>{const r=await query<any>(`SELECT r.*,p.booking_id FROM refunds r JOIN payments p ON p.id=r.payment_id WHERE r.id=$1`,[requireUuid(req.params.id)]);if(!r.rows[0])throw new AppError(404,'REFUND_NOT_FOUND','Refund not found.');const a=await query<any>(`SELECT * FROM refund_attempts WHERE refund_id=$1 ORDER BY attempt_no`,[req.params.id]);ok(res,{...r.rows[0],attempts:a.rows});}));
paymentRouter.post('/admin/payments/:id/refunds',requireActive,refundManage,asyncHandler(async(req,res)=>{const pid=requireUuid(req.params.id);const b=bodyObject(req.body),amount=integer(b,'amount',1),reason=requireString(b,'reason',1,3000);let rf:any;try{rf=await transaction(async tx=>{const p=await tx.query(`SELECT * FROM payments WHERE id=$1 FOR UPDATE`,[pid]);if(!p.rows[0])throw new AppError(404,'PAYMENT_NOT_FOUND','Payment not found.');if(p.rows[0].status!=='PAID')throw new AppError(409,'REFUND_NOT_ALLOWED','Corrective refund requires PAID payment.');const r=await createRefundObligation(tx,{paymentId:pid,amount,initiatorType:'ADMIN',initiatedBy:req.account.id,reasonCode:'CORRECTIVE_ADMIN_REFUND',reasonText:reason});await audit(tx,{actorType:'ADMIN',actorId:req.account.id,action:'CORRECTIVE_REFUND_CREATED',targetType:'REFUND',targetId:r.id,reason});await outbox(tx,`refund:${r.id}:requested`,'REFUND',r.id,'REFUND_REQUESTED',{});return r;});}catch(e:any){if(String(e?.message)==='REFUND_EXCEEDS_PAYMENT')throw new AppError(409,'REFUND_AMOUNT_EXCEEDS_AVAILABLE','Refund amount exceeds refundable headroom.');throw e;}ok(res,rf,201);}));
paymentRouter.post('/admin/refunds/:id/retry',requireActive,refundManage,asyncHandler(async(req,res)=>{const id=requireUuid(req.params.id);const reason=requireString(bodyObject(req.body),'reason',1,3000);const pre=await transaction(async tx=>{const r=await tx.query(`SELECT rf.*,p.provider,p.provider_transaction_id,p.provider_order_reference FROM refunds rf JOIN payments p ON p.id=rf.payment_id WHERE rf.id=$1 FOR UPDATE OF rf`,[id]);const rf=r.rows[0];if(!rf||rf.status!=='FAILED')throw new AppError(409,'REFUND_RETRY_NOT_ALLOWED','Refund is not eligible for controlled retry.');const last=(await tx.query(`SELECT * FROM refund_attempts WHERE refund_id=$1 ORDER BY attempt_no DESC LIMIT 1`,[id])).rows[0];if(!last||last.is_ambiguous||!last.completed_at)throw new AppError(409,'REFUND_RETRY_NOT_ALLOWED','Refund is not eligible for controlled retry.');const no=Number(last.attempt_no)+1;await tx.query(`UPDATE refunds SET status='PROCESSING',processing_at=now(),failed_at=NULL,updated_at=now() WHERE id=$1`,[id]);await tx.query(`INSERT INTO refund_attempts(refund_id,attempt_no) VALUES($1,$2)`,[id,no]);await audit(tx,{actorType:'ADMIN',actorId:req.account.id,action:'REFUND_CONTROLLED_RETRY',targetType:'REFUND',targetId:id,reason,metadata:{attempt_no:no}});await outbox(tx,`refund:${id}:retry:${no}`,'REFUND',id,'REFUND_RETRY_STARTED',{attempt_no:no});return {...rf,attempt_no:no};});const provider=await submitRefund(pre,pre);await transaction(async tx=>{await tx.query(`UPDATE refund_attempts SET provider_request_ref=$3,is_ambiguous=$4,completed_at=CASE WHEN $4 THEN NULL ELSE now() END WHERE refund_id=$1 AND attempt_no=$2`,[id,pre.attempt_no,provider.provider_ref??null,provider.ambiguous]);if(provider.succeeded){const rf=(await tx.query(`UPDATE refunds SET status='SUCCEEDED',succeeded_at=now(),updated_at=now() WHERE id=$1 RETURNING *`,[id])).rows[0];await postRefundSucceeded(tx,rf);await outbox(tx,`refund:${id}:succeeded`,'REFUND',id,'REFUND_SUCCEEDED',{retry:true});}else if(provider.terminalFailure)await tx.query(`UPDATE refunds SET status='FAILED',failed_at=now(),updated_at=now() WHERE id=$1`,[id]);});ok(res,{refund_id:id,status:provider.succeeded?'SUCCEEDED':provider.terminalFailure?'FAILED':'PROCESSING',attempt_no:pre.attempt_no});}));
