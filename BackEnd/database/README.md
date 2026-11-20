# PawPals Database

PostgreSQL with PostGIS, pgcrypto and btree_gist. The migration scripts are the schema authority. Never run a full baseline over a populated database.

## Migration inventory

- `migrations/001...024`: original baseline.
- `migrations/025_capacity_settlement_guard_fixes.sql`: settlement and occupied-interval guard fixes.
- `migrations/026_outbox_consumptions.sql`: durable consumer acknowledgement.
- `migrations/027_capacity_lock_deadlock_fix.sql`: actual capacity-lock hotfix, restored from the original PawPals hotfix package. Changes only the guard function, not tables or stored data.
- `PawPals_Full_Migration_001-026.sql`: combined migration for **empty databases only**.
- `PawPals_Full_Migration_001-024.sql`: historical baseline, not recommended for new setup.
- `tests/`: SQL validation scripts, for dedicated test databases only.

## Fresh local database

Create an empty development/test database in pgAdmin. In Query Tool, execute `PawPals_Full_Migration_001-026.sql`, then `migrations/027_capacity_lock_deadlock_fix.sql`. Alternatively execute individual migrations in order instead of the combined baseline, not both. With psql use `-v ON_ERROR_STOP=1`. Check the result with the verification SQL below. A fresh setup has not yet been fully verified end to end.

## Existing database

Back up first. If only 001–024 are applied, apply 025 then 026 after review. If 001–026 are already applied, check 027 first. If the hotfix is installed, there is no need to reapply it. Test a missing patch on a disposable `pawpals_capacity_test` database first; apply to the local development database only after backup and successful validation. Do not change production without review.

## Hotfix 027: capacity concurrency

The previous 027 file in the Premium archive was only a SELECT probe. That probe does not install the fix. The restored migration replaces `pawpals_capacity_deferred_guard()` and changes the vendor service row lock from `FOR UPDATE` to `FOR NO KEY UPDATE`, which is compatible with foreign-key `KEY SHARE` locks. It preserves availability, capacity and blocking-reservation checks and retains the booking row lock.

Run this **read-only** check in pgAdmin after 001–026 are installed:

```sql
SELECT position('FOR NO KEY UPDATE' IN
       pg_get_functiondef('public.pawpals_capacity_deferred_guard()'::regprocedure)) > 0
       AS capacity_lock_hotfix_installed;
```

`true` indicates the lock clause is present (not proof that every concurrency path works). `false` indicates the expected clause is absent. If the function is missing, check the database and migration history first.

## Regression tests

From `BackEnd/`, `npm test` includes build, route checks, type checks and regression tests. The three PostgreSQL tests are opt-in. Run the capacity and finance suites separately because they enforce different database names. Use dedicated, local, disposable DBs with the correct migration history. Never use `pawpals_validation` or production for these tests.

Example PowerShell: set `PAWPALS_TEST_DATABASE_URL` privately to a local connection URL ending in `/pawpals_capacity_test`, and set `PAWPALS_ALLOW_INTEGRATION_TESTS=yes`. Run `npm run test:integration`. Expect exactly one successful last-slot reservation and no `40P01` deadlock. Repeat to exercise contention. For finance, set the URL to `/pawpals_finance_test` and run `node --test tests/pawpals_finance_postgres.test.cjs tests/pawpals_settlement_payout_postgres.test.cjs` after building. Clear the temporary environment variables and do not commit credentials.

The restored hotfix is statically compared against migration 025; PostgreSQL execution and concurrency verification must still be performed on the target test database.
