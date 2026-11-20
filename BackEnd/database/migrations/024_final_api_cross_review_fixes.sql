-- ============================================================================
-- migrations/024_final_api_cross_review_fixes.sql
-- PawPals — Final API Cross-Review database corrections
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- PRE-FLIGHT DATA SAFETY
-- --------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM service_packages WHERE price_amount <= 0) THEN
    RAISE EXCEPTION
      'PDB-024 preflight failed: service_packages contains price_amount <= 0';
  END IF;

  IF EXISTS (SELECT 1 FROM booking_items WHERE price_amount_snapshot <= 0) THEN
    RAISE EXCEPTION
      'PDB-024 preflight failed: booking_items contains price_amount_snapshot <= 0';
  END IF;

  IF EXISTS (SELECT 1 FROM bookings WHERE total_amount <= 0) THEN
    RAISE EXCEPTION
      'PDB-024 preflight failed: bookings contains total_amount <= 0';
  END IF;

  IF EXISTS (SELECT 1 FROM payments WHERE amount <= 0) THEN
    RAISE EXCEPTION
      'PDB-024 preflight failed: payments contains amount <= 0';
  END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- FIX 1: availability must cover full occupied interval, including buffer.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_capacity_deferred_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  r capacity_reservations%ROWTYPE;
  b bookings%ROWTYPE;
  v_blocking_count integer;
  v_used integer;
  v_effective integer;
BEGIN
  SELECT *
  INTO r
  FROM capacity_reservations
  WHERE id = COALESCE(NEW.id, OLD.id);

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Serialize all capacity decisions for the same booking/service.
  SELECT *
  INTO b
  FROM bookings
  WHERE id = r.booking_id
  FOR UPDATE;

  PERFORM 1
  FROM vendor_services
  WHERE id = r.vendor_service_id
  FOR UPDATE;

  IF r.status = 'COMMITTED'
     OR (r.status = 'HELD' AND r.expires_at > now()) THEN

    IF r.starts_at <> b.scheduled_start_at
       OR r.service_ends_at <> b.scheduled_end_at
       OR r.occupied_ends_at <> b.occupied_end_at THEN
      RAISE EXCEPTION
        'Blocking capacity interval must equal current booking schedule';
    END IF;

    SELECT count(*)
    INTO v_blocking_count
    FROM capacity_reservations cr
    WHERE cr.booking_id = r.booking_id
      AND (
        cr.status = 'COMMITTED'
        OR (cr.status = 'HELD' AND cr.expires_at > now())
      );

    IF v_blocking_count > 1 THEN
      RAISE EXCEPTION
        'Booking may have only one blocking capacity reservation after commit';
    END IF;

    IF NOT pawpals_interval_is_available(
      r.vendor_service_id,
      r.starts_at,
      r.occupied_ends_at
    ) THEN
      RAISE EXCEPTION
        'Requested occupied interval is outside vendor availability';
    END IF;

    v_effective := pawpals_effective_capacity(
      r.vendor_service_id,
      r.starts_at,
      r.occupied_ends_at
    );

    SELECT COALESCE(sum(cr.capacity_units), 0)
    INTO v_used
    FROM capacity_reservations cr
    WHERE cr.vendor_service_id = r.vendor_service_id
      AND (
        cr.status = 'COMMITTED'
        OR (cr.status = 'HELD' AND cr.expires_at > now())
      )
      AND cr.starts_at < r.occupied_ends_at
      AND cr.occupied_ends_at > r.starts_at;

    IF v_used > v_effective THEN
      RAISE EXCEPTION
        'SLOT_UNAVAILABLE: capacity % exceeds effective capacity %',
        v_used,
        v_effective;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- Existing constraint trigger ct_capacity_deferred_guard continues to call
-- this same function and does not need to be recreated.

-- --------------------------------------------------------------------------
-- FIX 2: Rp0/free booking is outside the frozen MVP.
-- Tighten all canonical price/amount fields in the paid-booking chain.
-- --------------------------------------------------------------------------
ALTER TABLE service_packages
  DROP CONSTRAINT IF EXISTS ck_service_package_price;

ALTER TABLE service_packages
  ADD CONSTRAINT ck_service_package_price
  CHECK (price_amount > 0);

ALTER TABLE booking_items
  DROP CONSTRAINT IF EXISTS ck_booking_item_price;

ALTER TABLE booking_items
  ADD CONSTRAINT ck_booking_item_price
  CHECK (price_amount_snapshot > 0);

ALTER TABLE bookings
  DROP CONSTRAINT IF EXISTS ck_booking_amount;

ALTER TABLE bookings
  ADD CONSTRAINT ck_booking_amount
  CHECK (total_amount > 0);

ALTER TABLE payments
  DROP CONSTRAINT IF EXISTS ck_payment_amount;

ALTER TABLE payments
  ADD CONSTRAINT ck_payment_amount
  CHECK (amount > 0);

COMMIT;

-- --------------------------------------------------------------------------
-- POST-MIGRATION VERIFICATION (read-only)
-- --------------------------------------------------------------------------
SELECT
  current_database() AS database_name,
  pg_get_functiondef(
    'pawpals_capacity_deferred_guard()'::regprocedure
  ) AS capacity_guard_definition;

SELECT
  c.conrelid::regclass AS table_name,
  c.conname AS constraint_name,
  pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE
  (c.conrelid = 'service_packages'::regclass AND c.conname = 'ck_service_package_price')
  OR
  (c.conrelid = 'booking_items'::regclass AND c.conname = 'ck_booking_item_price')
  OR
  (c.conrelid = 'bookings'::regclass AND c.conname = 'ck_booking_amount')
  OR
  (c.conrelid = 'payments'::regclass AND c.conname = 'ck_payment_amount')
ORDER BY c.conrelid::regclass::text, c.conname;

-- ============================================================================
-- END migrations/024_final_api_cross_review_fixes.sql
-- ============================================================================
