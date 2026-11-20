# PawPals PDB-12 validation gates

After applying all migrations to a clean `pawpals_db`:

1. Run `001_schema_validation.sql`.
2. Verify each migration can be replayed from a fresh empty database in order.
3. Run application/integration tests for the agreed invariants:
   - capacity=1 race: two concurrent requests for last slot -> exactly one succeeds;
   - duplicate payment webhook -> one canonical financial effect;
   - late PAID on EXPIRED booking -> Booking remains EXPIRED, no capacity reconfirm;
   - concurrent refunds -> REQUESTED+PROCESSING+SUCCEEDED never exceed Payment.amount;
   - cancellation fault reclassification never rewrites terminal Booking state;
   - failed reschedule rolls back to old schedule/capacity;
   - two payout workers cannot actively allocate the same SettlementItem;
   - ambiguous payout remains PROCESSING/ALLOCATED and is not blindly retried;
   - definitive FAILED payout may release allocation and reallocate later;
   - post-payout refund creates NEGATIVE_ADJUSTMENT rather than rewriting PAID/SETTLED history;
   - private media classes are enforced for verification, pet, booking and incident evidence.
4. Only after these pass, mark the Physical DB baseline as FROZEN.

Concurrency tests require separate database sessions/processes and therefore are intentionally integration tests, not a single migration statement.
