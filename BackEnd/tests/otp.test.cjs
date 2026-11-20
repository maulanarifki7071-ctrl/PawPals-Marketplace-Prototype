// Regression suite: real routers + real transaction helper, isolated in-memory pg adapter.
// This verifies application transaction boundaries, NOT PostgreSQL locking semantics.
const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
process.env.NODE_ENV = 'test';
process.env.DEV_OTP_CODE = '123456';
delete process.env.REDIS_URL;
const pg = require('pg');
const id = '11111111-1111-4111-8111-111111111111';
const account = '22222222-2222-4222-8222-222222222222';
let state, trace, failUpdate, failSession, serial = Promise.resolve(), seq = 0;
const clone = value => structuredClone(value);
pg.Pool = class {
  async connect() {
    const previous = serial;
    let unlock;
    serial = new Promise(resolve => { unlock = resolve; });
    await previous;
    let snapshot;
    return {
      async query(sql, params = []) {
        sql = sql.replace(/\s+/g, ' ').trim();
        trace.push(sql);
        if (sql === 'BEGIN') { snapshot = clone(state); return { rows: [] }; }
        if (sql === 'COMMIT') return { rows: [] };
        if (sql === 'ROLLBACK') { state = snapshot; return { rows: [] }; }
        if (sql.startsWith('SELECT c.*') || sql.startsWith('SELECT * FROM otp_challenges')) {
          const matches = state.challenge.id === params[0] && (!sql.includes('account_id=$2') || state.challenge.account_id === params[1]);
          return { rows: matches ? [{ ...clone(state.challenge), account_status: state.accountStatus }] : [] };
        }
        if (sql.startsWith('UPDATE otp_challenges')) {
          if (failUpdate) throw new Error('simulated database failure');
          const c = state.challenge;
          if (sql.includes('consumed_at=now()')) {
            const eligible = c.id === params[0] && c.account_id === params[1] && c.purpose === params[2] && c.status === 'VERIFIED' && c.consumed_at === null;
            if (!eligible) return { rows: [] };
            c.consumed_at = new Date(); return { rows: [{ id: c.id }] };
          }
          if (sql.includes('attempt_count=$2')) {
            c.attempt_count = params[1];
            if (c.attempt_count >= c.max_attempts) c.status = 'LOCKED';
          } else if (sql.includes("status='EXPIRED'")) c.status = 'EXPIRED';
          else if (sql.includes("status='LOCKED'")) c.status = 'LOCKED';
          else if (sql.includes("status='VERIFIED'")) { c.status = 'VERIFIED'; c.verified_at = new Date(); }
          else throw new Error(`Unhandled OTP query: ${sql}`);
          return { rows: [] };
        }
        if (sql.startsWith('UPDATE accounts')) {
          if (state.accountStatus !== 'PENDING_PHONE_VERIFICATION') return { rows: [] };
          state.accountStatus = 'ACTIVE'; return { rows: [{ id: account, status: 'ACTIVE' }] };
        }
        if (sql.startsWith('INSERT INTO auth_sessions')) {
          if (failSession) throw new Error('simulated session failure');
          state.sessions++; return { rows: [{ id: 'session', expires_at: new Date(Date.now() + 60000) }] };
        }
        if (sql.startsWith('INSERT INTO audit_logs')) return { rows: [] };
        throw new Error(`Unexpected SQL: ${sql}`);
      },
      release() { unlock(); },
    };
  }
};
const { authRouter } = require('../dist/modules/auth/router');
const { transaction } = require('../dist/shared/db/database');
const { consumeSensitiveOtp } = require('../dist/modules/auth/verification/otp.verification');
const { verifyGrant } = require('../dist/shared/security/tokens');
beforeEach(() => {
  seq++;
  state = { challenge: { id, account_id: account, purpose: 'PASSWORD_RESET', status: 'PENDING', attempt_count: 0, max_attempts: 5, expires_at: new Date(Date.now() + 600000), consumed_at: null }, accountStatus: 'PENDING_PHONE_VERIFICATION', sessions: 0 };
  trace = []; failUpdate = false; failSession = false;
});
function request(sensitive = false, code = '123456', overrides = {}) {
  const path = sensitive ? '/auth/sensitive-otp/verify' : '/auth/otp/verify';
  const route = authRouter.stack.find(layer => layer.route?.path === path).route;
  const cookies = [];
  const req = { body: { challenge_id: id, code, ...(sensitive ? { purpose: 'PAYOUT_ACCOUNT_CHANGE' } : {}), ...overrides }, account: { id: account, status: 'ACTIVE' }, ip: `test-${seq}`, get: () => 'regression-test' };
  const res = { locals: { requestId: 'test' }, status(value) { this.statusCode = value; return this; }, cookie(...args) { cookies.push(args); return this; }, json(body) { resolve({ body, cookies, status: this.statusCode }); } };
  let resolve;
  return new Promise(done => {
    resolve = done;
    let index = 0;
    const next = error => error ? done({ error, cookies }) : route.stack[index++].handle(req, res, next);
    next();
  });
}
for (const sensitive of [false, true]) {
  const name = sensitive ? 'sensitive' : 'public';
  test(`${name}: failures persist, fifth attempt locks, correct code cannot unlock`, async () => {
    if (sensitive) state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
    for (let n = 1; n <= 5; n++) {
      const response = await request(sensitive, '999999');
      assert.equal(response.error.code, n === 5 ? 'OTP_LOCKED' : 'OTP_INVALID');
      assert.equal(state.challenge.attempt_count, n);
      assert.equal(response.cookies.length, 0);
    }
    assert.equal((await request(sensitive)).error.code, 'OTP_LOCKED');
    assert.equal(state.challenge.status, 'LOCKED');
    assert.equal(state.challenge.attempt_count, 5);
    assert.equal(trace.filter(sql => sql === 'COMMIT').length, 6);
    assert.equal(trace.includes('ROLLBACK'), false);
  });
  test(`${name}: expired challenge commits EXPIRED, no authorization`, async () => {
    if (sensitive) state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
    state.challenge.expires_at = new Date(Date.now() - 1000);
    const result = await request(sensitive);
    assert.equal(result.error.code, 'OTP_EXPIRED');
    assert.equal(state.challenge.status, 'EXPIRED');
    assert.equal(result.cookies.length, 0);
    assert.equal(trace.at(-1), 'COMMIT');
  });
  test(`${name}: successful verification issues grant only once`, async () => {
    if (sensitive) state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
    const first = await request(sensitive);
    assert.equal(first.error, undefined);
    const token = first.body.data[sensitive ? 'sensitive_authorization' : 'reset_authorization'];
    assert.equal(verifyGrant(token, sensitive ? 'sensitive' : 'password_reset').cid, id);
    assert.equal((await request(sensitive)).error.code, 'OTP_ALREADY_USED');
    assert.equal(state.challenge.status, 'VERIFIED');
  });
  test(`${name}: database failure rolls back and does not issue authorization`, async () => {
    if (sensitive) state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
    failUpdate = true;
    const result = await request(sensitive, '999999');
    assert.match(result.error.message, /database failure/);
    assert.equal(state.challenge.attempt_count, 0);
    assert.equal(result.cookies.length, 0);
    assert.equal(trace.at(-1), 'ROLLBACK');
  });
}
test('phone activation and session are atomic; repeat verification is rejected', async () => {
  state.challenge.purpose = 'PHONE_VERIFICATION';
  const result = await request();
  assert.equal(result.error, undefined);
  assert.equal(state.accountStatus, 'ACTIVE');
  assert.equal(state.sessions, 1);
  assert.equal(result.cookies[0][0], 'pawpals_session');
  assert.equal((await request()).error.code, 'OTP_ALREADY_USED');
});
test('session failure rolls back both account activation and OTP verification', async () => {
  state.challenge.purpose = 'PHONE_VERIFICATION'; failSession = true;
  const result = await request();
  assert.match(result.error.message, /session failure/);
  assert.equal(state.challenge.status, 'PENDING');
  assert.equal(state.accountStatus, 'PENDING_PHONE_VERIFICATION');
  assert.equal(result.cookies.length, 0);
});
test('public endpoint rejects sensitive-purpose challenge without mutation', async () => {
  state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
  assert.equal((await request()).error.code, 'OTP_PURPOSE_MISMATCH');
  assert.equal(state.challenge.status, 'PENDING');
});
test('sensitive endpoint rejects another account and mismatched purpose', async () => {
  state.challenge.account_id = '33333333-3333-4333-8333-333333333333';
  state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
  assert.equal((await request(true)).error.code, 'OTP_PURPOSE_MISMATCH');
  state.challenge.account_id = account; state.challenge.purpose = 'PASSWORD_RESET';
  assert.equal((await request(true)).error.code, 'OTP_PURPOSE_MISMATCH');
  assert.equal(state.challenge.attempt_count, 0);
});
test('invalid challenge UUID is rejected before database access', async () => {
  assert.equal((await request(false, '123456', { challenge_id: 'invalid' })).error.statusCode, 400);
  assert.equal(trace.length, 0);
});
test('sensitive verification has account-based rate limiting', async () => {
  // Previous tests share this account; use its remaining budget then observe rejection.
  state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
  let limited = false;
  for (let n = 0; n < 31; n++) {
    const response = await request(true, '999999');
    if (response.error?.code === 'RATE_LIMITED') { limited = true; break; }
  }
  assert.equal(limited, true);
});
test('sensitive authorization is consumed once even with competing consumers', async () => {
  state.challenge.status = 'VERIFIED'; state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
  const consume = () => transaction(tx => consumeSensitiveOtp(tx, id, account, 'PAYOUT_ACCOUNT_CHANGE'));
  const results = await Promise.allSettled([consume(), consume()]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, 'STEP_UP_REQUIRED');
  assert.ok(state.challenge.consumed_at);
});
test('failed protected operation rolls back consumption so user can retry', async () => {
  state.challenge.status = 'VERIFIED'; state.challenge.purpose = 'PAYOUT_ACCOUNT_CHANGE';
  await assert.rejects(transaction(async tx => {
    await consumeSensitiveOtp(tx, id, account, 'PAYOUT_ACCOUNT_CHANGE');
    throw new Error('protected update failed');
  }), /protected update failed/);
  assert.equal(state.challenge.consumed_at, null);
  await transaction(tx => consumeSensitiveOtp(tx, id, account, 'PAYOUT_ACCOUNT_CHANGE'));
  assert.ok(state.challenge.consumed_at);
});
test('sensitive consumption rejects wrong owner, purpose and unverified challenge', async () => {
  for (const args of [[id, account, 'PAYOUT_ACCOUNT_CHANGE'], [id, 'other', 'PASSWORD_RESET'], [id, account, 'other']]) {
    await assert.rejects(transaction(tx => consumeSensitiveOtp(tx, ...args)), { code: 'STEP_UP_REQUIRED' });
  }
  assert.equal(state.challenge.consumed_at, null);
});
