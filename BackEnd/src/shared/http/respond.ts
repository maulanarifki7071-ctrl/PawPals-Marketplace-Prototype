import type { Response } from 'express';
export function ok(res:Response, data:any, status=200): void { res.status(status).json({ data, request_id: res.locals.requestId }); }
export function noContent(res:Response): void { res.status(204).end(); }
export function page(res:Response, items:any[], current:number, limit:number, total:number): void {
  ok(res,{items,page:current,limit,total,total_pages: total === 0 ? 0 : Math.ceil(total/limit)});
}
export function pagination(q:Record<string,any>): {page:number;limit:number;offset:number} {
  const p = Number(q.page ?? 1), l = Number(q.limit ?? 20);
  const page = Number.isInteger(p)&&p>=1?p:1; const limit=Number.isInteger(l)&&l>=1&&l<=100?l:20;
  return {page,limit,offset:(page-1)*limit};
}
