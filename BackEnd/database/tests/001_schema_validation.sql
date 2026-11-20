-- PawPals PDB-12: non-destructive structural validation after migrations.
-- Run in pawpals_db. Each query should return the expected rows/counts.

-- Extensions
SELECT extname FROM pg_extension WHERE extname IN ('pgcrypto','postgis','btree_gist') ORDER BY extname;

-- Core table presence
SELECT table_name
FROM information_schema.tables
WHERE table_schema='public'
  AND table_name IN (
    'accounts','vendors','vendor_services','service_packages','pets','bookings','booking_items',
    'capacity_reservations','payments','refunds','ledger_entries','settlement_items','payouts',
    'support_cases','media_objects','outbox_events'
  )
ORDER BY table_name;

-- Partial unique indexes / important indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND indexname IN (
    'uq_account_role_active','uq_customer_default_address','uq_vendor_active_payout_account',
    'uq_active_settlement_allocation','uq_customer_self_reschedule_applied',
    'idx_customer_addresses_location_gist','idx_vendor_locations_location_gist','idx_outbox_pending'
  )
ORDER BY indexname;

-- Exclusion constraints
SELECT conname, contype
FROM pg_constraint
WHERE conname IN ('ex_service_availability_no_overlap','ex_service_capacity_override_no_overlap')
ORDER BY conname;

-- Critical constraint triggers
SELECT tgname, tgenabled
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN ('ct_capacity_deferred_guard','ct_refund_total_guard','ct_booking_deferred_guard','ct_cancellation_guard','ct_reschedule_guard','ct_payout_from_payout','ct_payout_from_item')
ORDER BY tgname;
