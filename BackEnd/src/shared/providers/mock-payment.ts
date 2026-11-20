import type {Request, Response, NextFunction} from 'express';
import {env} from '../../config/env';
import {AppError} from '../errors/app-error';

export type MockOutcome='PAID'|'FAILED'|'EXPIRED';
const loopbacks=new Set(['127.0.0.1','::1','::ffff:127.0.0.1']);

/** Only a logged-in local developer may invoke the mock provider. */
export function requireLocalMockPayments(req:Request,_res:Response,next:NextFunction):void{
 if(!env.mockPaymentsEnabled||!loopbacks.has(req.socket?.remoteAddress??'')){
  next(new AppError(404,'NOT_FOUND','Not found.'));
  return;
 }
 next();
}

/** Simulated checkout: NO real charge, real provider URL, or fake Midtrans token. */
export function createMockCheckout(p:any){
 if(!env.mockPaymentsEnabled||p.provider!=='MOCK')throw new AppError(503,'PAYMENT_PROVIDER_UNAVAILABLE','Mock payment is disabled.');
 return {provider:'MOCK',mode:'DEVELOPMENT_ONLY',payment_id:p.id,amount:Number(p.amount),currency:p.currency,
  expires_at:p.expires_at,simulation_endpoint:`/api/v1/dev/payments/${p.id}/simulate`,allowed_outcomes:['PAID','FAILED','EXPIRED']};
}

/** Server-constructed event. Client supplies ONLY the outcome, never an amount/order. */
export function createMockPaymentEvent(p:any,outcome:MockOutcome){
 const transactionStatus=outcome==='PAID'?'settlement':outcome==='FAILED'?'failure':'expire';
 return {order_id:p.provider_order_reference,transaction_id:`mock-${p.id}`,transaction_status:transactionStatus,
  status_code:outcome==='PAID'?'200':'400',gross_amount:String(p.amount)};
}
