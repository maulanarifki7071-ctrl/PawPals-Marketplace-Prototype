import type { NextFunction, Request, Response } from 'express';
import { createRequestId } from '../shared/http/request-id';

export function requestIdMiddleware(
  _req: Request,
  res: Response,
  next: NextFunction,
): void {
  res.locals.requestId = createRequestId();
  next();
}
