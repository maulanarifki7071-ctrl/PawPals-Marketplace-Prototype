-- Correct technical guard defects without altering the frozen business scope.
BEGIN;

CREATE OR REPLACE FUNCTION pawpals_guard_settlement()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE l ledger_entries%ROWTYPE;
DECLARE b bookings%ROWTYPE;
DECLARE c booking_cancellations%ROWTYPE;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF OLD.status='SETTLED' AND NEW.status<>'SETTLED' THEN RAISE EXCEPTION 'SETTLED settlement cannot be rewritten'; END IF;
    IF NEW.vendor_id<>OLD.vendor_id OR NEW.booking_id<>OLD.booking_id OR NEW.origin_ledger_entry_id<>OLD.origin_ledger_entry_id OR NEW.source_type<>OLD.source_type OR NEW.amount_signed<>OLD.amount_signed OR NEW.currency<>OLD.currency THEN
      RAISE EXCEPTION 'Settlement entitlement fields are immutable';
    END IF;
  END IF;
  SELECT * INTO l FROM ledger_entries WHERE id=NEW.origin_ledger_entry_id;
  SELECT * INTO b FROM bookings WHERE id=NEW.booking_id;
  IF NEW.vendor_id <> b.vendor_id THEN RAISE EXCEPTION 'Settlement vendor differs from Booking'; END IF;
  IF NEW.currency <> l.currency OR NEW.amount_signed <> l.amount_signed THEN RAISE EXCEPTION 'Settlement must match origin LedgerEntry amount/currency'; END IF;
  IF l.booking_id IS NOT NULL AND l.booking_id <> NEW.booking_id THEN RAISE EXCEPTION 'Settlement origin LedgerEntry belongs to another Booking'; END IF;
  IF l.vendor_id IS NOT NULL AND l.vendor_id <> NEW.vendor_id THEN RAISE EXCEPTION 'Settlement origin LedgerEntry belongs to another Vendor'; END IF;

  IF NEW.source_type = 'SERVICE_EARNING' AND NEW.status IN ('HOLD','AVAILABLE','ALLOCATED','SETTLED') AND b.status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'Service earning cannot progress past PENDING before Booking COMPLETED';
  END IF;
  IF NEW.source_type = 'CANCELLATION_COMPENSATION' AND NEW.status IN ('HOLD','AVAILABLE','ALLOCATED','SETTLED') THEN
    SELECT * INTO c FROM booking_cancellations WHERE booking_id=NEW.booking_id;
    IF NOT FOUND OR c.fault_finalized_at IS NULL OR (NEW.status IN ('AVAILABLE','ALLOCATED','SETTLED') AND now() < c.claim_window_ends_at) THEN
      RAISE EXCEPTION 'Cancellation compensation requires final attribution and ended claim window';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION pawpals_capacity_deferred_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r capacity_reservations%ROWTYPE;
DECLARE b bookings%ROWTYPE;
DECLARE v_blocking_count integer;
DECLARE v_used integer;
DECLARE v_effective integer;
BEGIN
  SELECT * INTO r FROM capacity_reservations WHERE id = COALESCE(NEW.id, OLD.id);
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Serialize all capacity decisions for the same booking/service.
  SELECT * INTO b FROM bookings WHERE id = r.booking_id FOR UPDATE;
  PERFORM 1 FROM vendor_services WHERE id = r.vendor_service_id FOR UPDATE;

  IF r.status = 'COMMITTED' OR (r.status = 'HELD' AND r.expires_at > now()) THEN
    IF r.starts_at <> b.scheduled_start_at OR r.service_ends_at <> b.scheduled_end_at OR r.occupied_ends_at <> b.occupied_end_at THEN
      RAISE EXCEPTION 'Blocking capacity interval must equal current booking schedule';
    END IF;

    SELECT count(*) INTO v_blocking_count
    FROM capacity_reservations cr
    WHERE cr.booking_id = r.booking_id
      AND (cr.status = 'COMMITTED' OR (cr.status = 'HELD' AND cr.expires_at > now()));
    IF v_blocking_count > 1 THEN
      RAISE EXCEPTION 'Booking may have only one blocking capacity reservation after commit';
    END IF;

    IF NOT pawpals_interval_is_available(r.vendor_service_id, r.starts_at, r.occupied_ends_at) THEN
      RAISE EXCEPTION 'Requested service interval is outside vendor availability';
    END IF;

    v_effective := pawpals_effective_capacity(r.vendor_service_id, r.starts_at, r.occupied_ends_at);
    SELECT COALESCE(sum(cr.capacity_units),0) INTO v_used
    FROM capacity_reservations cr
    WHERE cr.vendor_service_id = r.vendor_service_id
      AND (cr.status = 'COMMITTED' OR (cr.status = 'HELD' AND cr.expires_at > now()))
      AND cr.starts_at < r.occupied_ends_at
      AND cr.occupied_ends_at > r.starts_at;

    IF v_used > v_effective THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: capacity % exceeds effective capacity %', v_used, v_effective;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

COMMIT;
