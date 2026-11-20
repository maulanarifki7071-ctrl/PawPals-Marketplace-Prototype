# AC-12 — Admin / RBAC / Audit

This module is part of the frozen PawPals API Contract implementation.

## HTTP boundary
The canonical route entry is `router.ts`. Supporting domain helpers are placed under `services/`, `repositories/`, `config/`, `jobs/`, `verification/`, and `routes/` when the domain requires that concern.

## Scope rule
No feature outside the frozen AC-01..AC-12 MVP contract is introduced by this module. PostgreSQL remains authoritative for state and concurrency; asynchronous work uses the outbox/worker boundary.
