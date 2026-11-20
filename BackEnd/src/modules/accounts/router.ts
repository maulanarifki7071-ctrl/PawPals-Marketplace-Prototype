import express from 'express';
import { asyncHandler } from '../../shared/http/async-handler';
import { ok } from '../../shared/http/respond';
import { requireAuth } from '../../middleware/auth';
import { getCurrentAccount } from './services/accounts.service';

/**
 * AC-01 — Accounts
 *
 * Account self-service endpoints live in this module. Authentication and
 * credential/OTP flows remain in modules/auth.
 */
export const accountsRouter = express.Router();

// GET /api/v1/accounts/me
accountsRouter.get('/accounts/me', requireAuth, asyncHandler(async (req, res) => {
  const account = await getCurrentAccount(req.account.id);
  if (!account) return res.status(404).json({
    error: { code: 'ACCOUNT_NOT_FOUND', message: 'Account not found.' },
    request_id: res.locals.requestId,
  });

  // requireAuth + account-id predicate enforce current-account ownership.
  ok(res, account);
}));
