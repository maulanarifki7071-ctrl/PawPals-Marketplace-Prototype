import 'dotenv/config';
import express from 'express';
import { errorHandler } from './middleware/error-handler';
import { notFoundHandler } from './middleware/not-found';
import { requestIdMiddleware } from './middleware/request-id';
import { loadSession } from './middleware/auth';
import {csrfOriginGuard} from './middleware/csrf-origin';
import { authRouter } from './modules/auth/router';
import { accountsRouter } from './modules/accounts/router';
import { vendorRouter } from './modules/vendors/router';
import { locationRouter } from './modules/locations/router';
import { petRouter } from './modules/pets/router';
import { serviceRouter } from './modules/services/router';
import { bookingRouter } from './modules/bookings/router';
import { paymentRouter } from './modules/payments/router';
import { cancellationRouter } from './modules/cancellations/router';
import { financeRouter } from './modules/finance/router';
import { interactionRouter } from './modules/interactions/router';
import { trustSafetyRouter } from './modules/trust-safety/router';
import { adminRouter } from './modules/admin/router';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use((_req:any,res:any,next:any)=>{res.setHeader?.('X-Content-Type-Options','nosniff');res.setHeader?.('Referrer-Policy','no-referrer');next();});
  app.use(express.json({ limit: '1mb' }));
  app.use(requestIdMiddleware);
  app.use(loadSession);
  app.use(csrfOriginGuard);

  // Frozen contract base path. Routers below contain only OpenAPI AC-01..AC-12 endpoints.
  const base='/api/v1';
  app.use(base,authRouter);
  app.use(base,accountsRouter);
  app.use(base,vendorRouter);
  app.use(base,locationRouter);
  app.use(base,petRouter);
  app.use(base,serviceRouter);
  app.use(base,bookingRouter);
  app.use(base,paymentRouter);
  app.use(base,cancellationRouter);
  app.use(base,financeRouter);
  app.use(base,interactionRouter);
  app.use(base,trustSafetyRouter);
  app.use(base,adminRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
