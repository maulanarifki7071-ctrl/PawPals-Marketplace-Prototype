-- PawPals PDB-03: partial unique + exclusion constraints.
BEGIN;

CREATE UNIQUE INDEX uq_account_role_active
  ON account_role_assignments(account_id, role_id)
  WHERE status = 'ACTIVE';

CREATE UNIQUE INDEX uq_customer_default_address
  ON customer_addresses(account_id)
  WHERE is_default = true;

CREATE UNIQUE INDEX uq_vendor_active_payout_account
  ON vendor_payout_accounts(vendor_id)
  WHERE is_active = true;

CREATE UNIQUE INDEX uq_active_settlement_allocation
  ON payout_items(settlement_item_id)
  WHERE released_at IS NULL;

CREATE UNIQUE INDEX uq_customer_self_reschedule_applied
  ON reschedules(booking_id)
  WHERE mode = 'CUSTOMER_SELF' AND status = 'APPLIED';

-- [start,end) ranges: touching boundaries are allowed, true overlap is rejected.
ALTER TABLE service_availability_windows
  ADD CONSTRAINT ex_service_availability_no_overlap
  EXCLUDE USING gist (
    vendor_service_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE service_capacity_overrides
  ADD CONSTRAINT ex_service_capacity_override_no_overlap
  EXCLUDE USING gist (
    vendor_service_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) DEFERRABLE INITIALLY IMMEDIATE;

COMMIT;
