import type {Request,Response,NextFunction} from 'express';
import {AppError} from '../shared/errors/app-error';
/** Reject cross-origin cookie-authenticated writes; does not apply to provider webhooks. */
export function csrfOriginGuard(req:Request,_res:Response,next:NextFunction){
 if(['GET','HEAD','OPTIONS'].includes(req.method)||!req.account)return next();
 const origin=req.headers.origin;
 if(!origin)return next(); // non-browser calls; authenticated server sessions still required.
 const allow=(process.env.APP_ALLOWED_ORIGINS??'').split(',').map((x:string)=>x.trim()).filter(Boolean);
 const forwardedHost=(req.headers.host??'').toString();
 const proto=(req as any).secure?'https':'http';
 const same=`${proto}://${forwardedHost}`;
 if(origin===same||allow.includes(origin))return next();
 return next(new AppError(403,'CSRF_ORIGIN_FORBIDDEN','Cross-origin authenticated writes are not permitted.'));
}
