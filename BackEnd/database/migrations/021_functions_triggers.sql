-- PawPals PDB-05/06/07/08/09: database guards for critical cross-domain invariants.
-- Service-layer transactions remain authoritative for workflows; these triggers are a final integrity net.
BEGIN;

-- ------------------------------------------------------------
-- Generic updated_at
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'accounts','account_credentials','vendors','vendor_applications','vendor_verification_documents',
    'customer_profiles','customer_addresses','vendor_locations','pets','pet_safety_profiles',
    'vendor_services','service_packages','bookings','payments','refunds','settlement_items',
    'vendor_payout_accounts','payouts','reviews','support_cases'
  ] LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION pawpals_set_updated_at()', 'trg_' || t || '_updated_at', t);
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- Vendor / service privacy and activation guards
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_guard_vendor_location()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_type vendor_type;
BEGIN
  SELECT vendor_type INTO v_type FROM vendors WHERE id = NEW.vendor_id;
  IF NEW.location_type = 'PUBLIC_BUSINESS' AND v_type <> 'BUSINESS' THEN
    RAISE EXCEPTION 'PUBLIC_BUSINESS location requires BUSINESS vendor';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_vendor_location_guard
BEFORE INSERT OR UPDATE ON vendor_locations
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_vendor_location();

CREATE OR REPLACE FUNCTION pawpals_guard_vendor_service()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_vendor_status vendor_status;
BEGIN
  IF NEW.status = 'ACTIVE' THEN
    SELECT status INTO v_vendor_status FROM vendors WHERE id = NEW.vendor_id;
    IF v_vendor_status <> 'ACTIVE' THEN
      RAISE EXCEPTION 'ACTIVE service requires ACTIVE vendor';
    END IF;
    IF NEW.origin_vendor_location_id IS NULL THEN
      RAISE EXCEPTION 'ACTIVE service requires origin vendor location';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_vendor_service_guard
BEFORE INSERT OR UPDATE ON vendor_services
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_vendor_service();


CREATE OR REPLACE FUNCTION pawpals_guard_vendor_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.account_id <> OLD.account_id THEN
    RAISE EXCEPTION 'Vendor account identity is immutable';
  END IF;
  IF NEW.vendor_type <> OLD.vendor_type AND EXISTS (
    SELECT 1 FROM vendor_applications va WHERE va.vendor_id=OLD.id AND va.status <> 'DRAFT'
  ) THEN
    RAISE EXCEPTION 'Vendor type is immutable after application submission';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_vendor_identity_guard
BEFORE UPDATE ON vendors
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_vendor_identity();

CREATE OR REPLACE FUNCTION pawpals_guard_pet_owner()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.owner_account_id <> OLD.owner_account_id THEN
    RAISE EXCEPTION 'Pet ownership is immutable in PawPals MVP';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_pet_owner_guard
BEFORE UPDATE OF owner_account_id ON pets
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_pet_owner();

CREATE OR REPLACE FUNCTION pawpals_guard_vendor_application_submit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_account_status account_status;
DECLARE v_account_id uuid;
BEGIN
  IF NEW.status = 'SUBMITTED' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT v.account_id, a.status INTO v_account_id, v_account_status
    FROM vendors v JOIN accounts a ON a.id = v.account_id
    WHERE v.id = NEW.vendor_id;
    IF v_account_status <> 'ACTIVE' THEN
      RAISE EXCEPTION 'Vendor application SUBMITTED requires ACTIVE account';
    END IF;
    IF NEW.terms_version IS NULL OR NEW.terms_accepted_at IS NULL THEN
      RAISE EXCEPTION 'Vendor application SUBMITTED requires accepted terms';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM vendor_services vs
      JOIN service_packages sp ON sp.vendor_service_id = vs.id
      WHERE vs.vendor_id = NEW.vendor_id
    ) THEN
      RAISE EXCEPTION 'Vendor application SUBMITTED requires at least one service with pricing/package';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_vendor_application_submit_guard
BEFORE INSERT OR UPDATE OF status ON vendor_applications
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_vendor_application_submit();

-- ------------------------------------------------------------
-- Booking snapshots, eligibility and location provenance
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_guard_booking_item()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
DECLARE p pets%ROWTYPE;
DECLARE sp service_packages%ROWTYPE;
DECLARE vs vendor_services%ROWTYPE;
DECLARE v_vendor_status vendor_status;
DECLARE v_account_status account_status;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = NEW.booking_id FOR UPDATE;
  SELECT * INTO p FROM pets WHERE id = NEW.pet_id;
  SELECT * INTO sp FROM service_packages WHERE id = NEW.service_package_id;
  SELECT * INTO vs FROM vendor_services WHERE id = b.vendor_service_id;
  SELECT status INTO v_vendor_status FROM vendors WHERE id = b.vendor_id;
  SELECT status INTO v_account_status FROM accounts WHERE id = b.customer_account_id;

  IF p.owner_account_id <> b.customer_account_id THEN
    RAISE EXCEPTION 'Booking pet must belong to booking customer';
  END IF;
  IF sp.vendor_service_id <> b.vendor_service_id THEN
    RAISE EXCEPTION 'Booking package must belong to booking service';
  END IF;
  IF v_account_status <> 'ACTIVE' OR v_vendor_status <> 'ACTIVE' OR vs.status <> 'ACTIVE' OR sp.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Booking requires ACTIVE customer, vendor, service and package';
  END IF;
  IF b.scheduled_start_at < now() + make_interval(mins => vs.minimum_notice_minutes) THEN
    RAISE EXCEPTION 'Booking violates service minimum notice';
  END IF;
  IF b.scheduled_end_at <> b.scheduled_start_at + make_interval(mins => sp.duration_minutes) THEN
    RAISE EXCEPTION 'Booking scheduled_end_at must equal start + package duration';
  END IF;
  IF b.occupied_end_at <> b.scheduled_end_at + make_interval(mins => vs.buffer_after_minutes) THEN
    RAISE EXCEPTION 'Booking occupied_end_at must equal service end + buffer';
  END IF;
  IF NEW.price_amount_snapshot <> sp.price_amount OR
     NEW.duration_minutes_snapshot <> sp.duration_minutes OR
     NEW.buffer_after_minutes_snapshot <> vs.buffer_after_minutes OR
     NEW.minimum_notice_minutes_snapshot <> vs.minimum_notice_minutes OR
     b.total_amount <> sp.price_amount OR b.currency <> sp.currency THEN
    RAISE EXCEPTION 'Booking snapshot provenance mismatch';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_booking_item_guard
BEFORE INSERT OR UPDATE ON booking_items
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_item();

CREATE OR REPLACE FUNCTION pawpals_guard_booking_location_snapshot()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
DECLARE vs vendor_services%ROWTYPE;
DECLARE vl vendor_locations%ROWTYPE;
DECLARE actual_distance double precision;
DECLARE snap geography(Point,4326);
BEGIN
  SELECT * INTO b FROM bookings WHERE id = NEW.booking_id;
  SELECT * INTO vs FROM vendor_services WHERE id = b.vendor_service_id;
  IF vs.origin_vendor_location_id IS NULL THEN
    RAISE EXCEPTION 'Booking service has no origin location';
  END IF;
  SELECT * INTO vl FROM vendor_locations WHERE id = vs.origin_vendor_location_id;
  snap := ST_SetSRID(ST_MakePoint(NEW.longitude::double precision, NEW.latitude::double precision),4326)::geography;

  IF NEW.delivery_mode_snapshot::text <> vs.delivery_mode::text THEN
    RAISE EXCEPTION 'Booking delivery mode snapshot differs from service';
  END IF;

  IF vs.delivery_mode = 'AT_CUSTOMER' THEN
    actual_distance := ST_Distance(vl.location, snap);
    IF NEW.service_radius_meters_snapshot IS DISTINCT FROM vs.service_radius_meters THEN
      RAISE EXCEPTION 'Service radius snapshot mismatch';
    END IF;
    IF NEW.distance_meters_snapshot IS NULL OR NEW.distance_meters_snapshot > vs.service_radius_meters THEN
      RAISE EXCEPTION 'Customer location outside service radius';
    END IF;
    IF abs(NEW.distance_meters_snapshot - round(actual_distance)::integer) > 2 THEN
      RAISE EXCEPTION 'Distance snapshot differs from PostGIS authoritative distance';
    END IF;
  ELSE
    IF ST_Distance(vl.location, snap) > 2 THEN
      RAISE EXCEPTION 'AT_VENDOR snapshot must use vendor service location';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_booking_location_snapshot_guard
BEFORE INSERT OR UPDATE ON booking_location_snapshots
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_location_snapshot();

CREATE OR REPLACE FUNCTION pawpals_guard_booking_snapshot_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status booking_status;
DECLARE v_booking_id uuid;
BEGIN
  v_booking_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.booking_id ELSE NEW.booking_id END;
  SELECT status INTO v_status FROM bookings WHERE id = v_booking_id;
  IF v_status <> 'CREATED' THEN
    RAISE EXCEPTION 'Booking snapshots are immutable after CREATED state';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_booking_item_immutable AFTER UPDATE OR DELETE ON booking_items
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_snapshot_mutation();
CREATE TRIGGER trg_booking_location_immutable AFTER UPDATE OR DELETE ON booking_location_snapshots
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_snapshot_mutation();
CREATE TRIGGER trg_booking_policy_immutable AFTER UPDATE OR DELETE ON booking_policy_snapshots
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_snapshot_mutation();

CREATE OR REPLACE FUNCTION pawpals_guard_booking_terminal_state()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('COMPLETED','EXPIRED','CUSTOMER_CANCELLED','VENDOR_CANCELLED','PLATFORM_CANCELLED')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Terminal booking status cannot be rewritten';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_booking_terminal_state
BEFORE UPDATE OF status ON bookings
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_terminal_state();


CREATE OR REPLACE FUNCTION pawpals_guard_booking_core_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.customer_account_id <> OLD.customer_account_id OR
     NEW.vendor_id <> OLD.vendor_id OR
     NEW.vendor_service_id <> OLD.vendor_service_id OR
     NEW.total_amount <> OLD.total_amount OR
     NEW.currency <> OLD.currency THEN
    RAISE EXCEPTION 'Booking customer/vendor/service/price/currency are immutable after creation';
  END IF;

  IF (NEW.scheduled_start_at,NEW.scheduled_end_at,NEW.occupied_end_at)
     IS DISTINCT FROM (OLD.scheduled_start_at,OLD.scheduled_end_at,OLD.occupied_end_at)
     AND OLD.status <> 'CREATED' THEN
    IF NOT EXISTS (
      SELECT 1 FROM reschedules r
      WHERE r.booking_id=OLD.id
        AND r.status IN ('PENDING','APPLIED')
        AND r.proposed_start_at=NEW.scheduled_start_at
        AND r.proposed_end_at=NEW.scheduled_end_at
        AND r.proposed_occupied_end_at=NEW.occupied_end_at
    ) THEN
      RAISE EXCEPTION 'Booking schedule may change only through Reschedule flow';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_booking_core_update
BEFORE UPDATE ON bookings
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_booking_core_update();

-- ------------------------------------------------------------
-- Availability / capacity functions and deferred integrity
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_interval_is_available(
  p_service uuid, p_start timestamptz, p_end timestamptz
) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE cursor_at timestamptz := p_start;
DECLARE r record;
BEGIN
  FOR r IN
    SELECT starts_at, ends_at
    FROM service_availability_windows
    WHERE vendor_service_id = p_service
      AND ends_at > p_start AND starts_at < p_end
    ORDER BY starts_at
  LOOP
    IF r.starts_at > cursor_at THEN RETURN false; END IF;
    cursor_at := GREATEST(cursor_at, r.ends_at);
    IF cursor_at >= p_end THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION pawpals_effective_capacity(
  p_service uuid, p_start timestamptz, p_end timestamptz
) RETURNS integer LANGUAGE plpgsql STABLE AS $$
DECLARE v_base integer;
DECLARE cursor_at timestamptz := p_start;
DECLARE v_min integer := NULL;
DECLARE r record;
BEGIN
  SELECT base_capacity INTO v_base FROM vendor_services WHERE id = p_service;
  IF v_base IS NULL THEN RAISE EXCEPTION 'Unknown vendor service %', p_service; END IF;

  FOR r IN
    SELECT starts_at, ends_at, capacity
    FROM service_capacity_overrides
    WHERE vendor_service_id = p_service
      AND ends_at > p_start AND starts_at < p_end
    ORDER BY starts_at
  LOOP
    IF r.starts_at > cursor_at THEN
      v_min := CASE WHEN v_min IS NULL THEN v_base ELSE LEAST(v_min, v_base) END;
    END IF;
    v_min := CASE WHEN v_min IS NULL THEN r.capacity ELSE LEAST(v_min, r.capacity) END;
    cursor_at := GREATEST(cursor_at, r.ends_at);
  END LOOP;

  IF cursor_at < p_end OR v_min IS NULL THEN
    v_min := CASE WHEN v_min IS NULL THEN v_base ELSE LEAST(v_min, v_base) END;
  END IF;
  RETURN v_min;
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

    IF NOT pawpals_interval_is_available(r.vendor_service_id, r.starts_at, r.service_ends_at) THEN
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
CREATE CONSTRAINT TRIGGER ct_capacity_deferred_guard
AFTER INSERT OR UPDATE ON capacity_reservations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_capacity_deferred_guard();

-- ------------------------------------------------------------
-- Payment / refund invariants
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_guard_payment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = NEW.booking_id;
  IF NEW.amount <> b.total_amount OR NEW.currency <> b.currency THEN
    RAISE EXCEPTION 'Payment amount/currency must equal Booking';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'PAID' AND NEW.status <> 'PAID' THEN
    RAISE EXCEPTION 'PAID payment cannot downgrade';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payment_guard
BEFORE INSERT OR UPDATE ON payments
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_payment();

CREATE OR REPLACE FUNCTION pawpals_guard_refund_row()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p payments%ROWTYPE;
DECLARE b bookings%ROWTYPE;
DECLARE v_vendor_account uuid;
BEGIN
  SELECT * INTO p FROM payments WHERE id = NEW.payment_id;
  SELECT * INTO b FROM bookings WHERE id = p.booking_id;
  IF TG_OP='UPDATE' AND (NEW.payment_id<>OLD.payment_id OR NEW.amount<>OLD.amount OR NEW.currency<>OLD.currency OR NEW.initiator_type<>OLD.initiator_type OR NEW.initiated_by_account_id IS DISTINCT FROM OLD.initiated_by_account_id) THEN
    RAISE EXCEPTION 'Refund financial/initiator fields are immutable; use corrective Refund row';
  END IF;
  IF NEW.currency <> p.currency THEN RAISE EXCEPTION 'Refund currency must equal Payment'; END IF;

  IF NEW.initiator_type = 'CUSTOMER' AND NEW.initiated_by_account_id <> b.customer_account_id THEN
    RAISE EXCEPTION 'Customer refund initiator must be booking customer';
  ELSIF NEW.initiator_type = 'VENDOR' THEN
    SELECT account_id INTO v_vendor_account FROM vendors WHERE id = b.vendor_id;
    IF NEW.initiated_by_account_id <> v_vendor_account THEN
      RAISE EXCEPTION 'Vendor refund initiator must be booking vendor account';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_refund_row_guard
BEFORE INSERT OR UPDATE ON refunds
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_refund_row();

CREATE OR REPLACE FUNCTION pawpals_refund_total_deferred_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_payment_id uuid := COALESCE(NEW.payment_id, OLD.payment_id);
DECLARE v_paid bigint;
DECLARE v_reserved bigint;
BEGIN
  SELECT amount INTO v_paid FROM payments WHERE id = v_payment_id FOR UPDATE;
  SELECT COALESCE(sum(amount),0) INTO v_reserved
  FROM refunds
  WHERE payment_id = v_payment_id
    AND status IN ('REQUESTED','PROCESSING','SUCCEEDED');
  IF v_reserved > v_paid THEN
    RAISE EXCEPTION 'Refund ceiling exceeded: % > %', v_reserved, v_paid;
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_refund_total_guard
AFTER INSERT OR UPDATE ON refunds
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_refund_total_deferred_guard();

-- ------------------------------------------------------------
-- Booking final-state cross-domain integrity
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_booking_deferred_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
DECLARE v_count integer;
DECLARE p_status payment_status;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = COALESCE(NEW.id, OLD.id) FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;

  IF b.status IN ('AWAITING_PAYMENT','CONFIRMED','IN_PROGRESS','COMPLETED','EXPIRED','CUSTOMER_CANCELLED','VENDOR_CANCELLED','PLATFORM_CANCELLED') THEN
    SELECT count(*) INTO v_count FROM booking_items WHERE booking_id = b.id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Booking requires exactly one BookingItem'; END IF;
    SELECT count(*) INTO v_count FROM booking_location_snapshots WHERE booking_id = b.id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Booking requires exactly one BookingLocationSnapshot'; END IF;
    SELECT count(*) INTO v_count FROM booking_policy_snapshots WHERE booking_id = b.id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Booking requires exactly one BookingPolicySnapshot'; END IF;
  END IF;

  IF b.status = 'AWAITING_PAYMENT' THEN
    SELECT status INTO p_status FROM payments WHERE booking_id = b.id;
    IF p_status IS DISTINCT FROM 'PENDING' THEN RAISE EXCEPTION 'AWAITING_PAYMENT requires PENDING Payment'; END IF;
    SELECT count(*) INTO v_count FROM capacity_reservations cr
      WHERE cr.booking_id=b.id AND cr.status='HELD' AND cr.expires_at > now();
    IF v_count <> 1 THEN RAISE EXCEPTION 'AWAITING_PAYMENT requires one unexpired HELD capacity'; END IF;
  ELSIF b.status IN ('CONFIRMED','IN_PROGRESS','COMPLETED') THEN
    SELECT status INTO p_status FROM payments WHERE booking_id = b.id;
    IF p_status IS DISTINCT FROM 'PAID' THEN RAISE EXCEPTION '% requires PAID Payment', b.status; END IF;
    SELECT count(*) INTO v_count FROM capacity_reservations cr
      WHERE cr.booking_id=b.id AND cr.status='COMMITTED';
    IF v_count <> 1 THEN RAISE EXCEPTION '% requires one COMMITTED capacity reservation', b.status; END IF;
  ELSIF b.status IN ('EXPIRED','CUSTOMER_CANCELLED','VENDOR_CANCELLED','PLATFORM_CANCELLED') THEN
    SELECT count(*) INTO v_count FROM capacity_reservations cr
      WHERE cr.booking_id=b.id AND (cr.status='COMMITTED' OR (cr.status='HELD' AND cr.expires_at > now()));
    IF v_count <> 0 THEN RAISE EXCEPTION 'Expired/cancelled Booking cannot retain blocking capacity'; END IF;
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_booking_deferred_guard
AFTER INSERT OR UPDATE ON bookings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_booking_deferred_guard();

-- ------------------------------------------------------------
-- Cancellation / reschedule integrity
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_guard_cancellation_core_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.booking_id<>OLD.booking_id OR NEW.cancelled_by<>OLD.cancelled_by OR
     NEW.calculated_refund_amount<>OLD.calculated_refund_amount OR
     NEW.retained_settlement_base_amount<>OLD.retained_settlement_base_amount OR
     NEW.policy_evaluation_snapshot_json<>OLD.policy_evaluation_snapshot_json OR
     NEW.claim_window_ends_at<>OLD.claim_window_ends_at OR
     NEW.cancelled_at<>OLD.cancelled_at THEN
    RAISE EXCEPTION 'Cancellation execution/policy/financial snapshot fields are immutable';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_cancellation_core_update
BEFORE UPDATE ON booking_cancellations
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_cancellation_core_update();

CREATE OR REPLACE FUNCTION pawpals_cancellation_deferred_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c booking_cancellations%ROWTYPE;
DECLARE b bookings%ROWTYPE;
DECLARE ps booking_policy_snapshots%ROWTYPE;
DECLARE expected booking_status;
BEGIN
  SELECT * INTO c FROM booking_cancellations WHERE id = COALESCE(NEW.id, OLD.id);
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO b FROM bookings WHERE id = c.booking_id FOR UPDATE;
  SELECT * INTO ps FROM booking_policy_snapshots WHERE booking_id = c.booking_id;

  expected := CASE c.cancelled_by
    WHEN 'CUSTOMER' THEN 'CUSTOMER_CANCELLED'::booking_status
    WHEN 'VENDOR' THEN 'VENDOR_CANCELLED'::booking_status
    ELSE 'PLATFORM_CANCELLED'::booking_status END;
  IF b.status <> expected THEN
    RAISE EXCEPTION 'Booking cancellation actor does not match terminal Booking status';
  END IF;
  IF c.calculated_refund_amount + c.retained_settlement_base_amount <> b.total_amount THEN
    RAISE EXCEPTION 'Cancellation refund + retained base must equal Booking total';
  END IF;
  IF c.claim_window_ends_at <> c.cancelled_at + make_interval(mins => ps.cancellation_claim_window_minutes) THEN
    RAISE EXCEPTION 'Cancellation claim window must come from BookingPolicySnapshot';
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_cancellation_guard
AFTER INSERT OR UPDATE ON booking_cancellations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_cancellation_deferred_guard();

CREATE OR REPLACE FUNCTION pawpals_guard_vendor_claim_response()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_expected uuid;
BEGIN
  IF NEW.vendor_response_by_account_id IS NOT NULL THEN
    SELECT v.account_id INTO v_expected
    FROM booking_cancellations bc
    JOIN bookings b ON b.id = bc.booking_id
    JOIN vendors v ON v.id = b.vendor_id
    WHERE bc.id = NEW.booking_cancellation_id;
    IF NEW.vendor_response_by_account_id <> v_expected THEN
      RAISE EXCEPTION 'Vendor claim response account must be the booking vendor account';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_vendor_claim_response_guard
BEFORE INSERT OR UPDATE ON vendor_cancellation_claims
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_vendor_claim_response();

CREATE OR REPLACE FUNCTION pawpals_guard_reschedule_row()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
DECLARE v_vendor_account uuid;
DECLARE ps booking_policy_snapshots%ROWTYPE;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = NEW.booking_id;
  SELECT account_id INTO v_vendor_account FROM vendors WHERE id = b.vendor_id;
  SELECT * INTO ps FROM booking_policy_snapshots WHERE booking_id = b.id;

  IF (TG_OP = 'INSERT' OR NEW.status IN ('PENDING','APPLIED','DECLINED')) AND b.status <> 'CONFIRMED' THEN
    RAISE EXCEPTION 'Reschedule creation/application/decision requires CONFIRMED Booking';
  END IF;
  IF NEW.mode = 'CUSTOMER_SELF' THEN
    IF NEW.initiated_by_account_id <> b.customer_account_id THEN RAISE EXCEPTION 'CUSTOMER_SELF must be initiated by booking customer'; END IF;
    IF NEW.proposed_start_at < now() + make_interval(mins => ps.customer_self_reschedule_min_notice_minutes) THEN
      RAISE EXCEPTION 'CUSTOMER_SELF reschedule violates policy minimum notice';
    END IF;
  ELSE
    IF NEW.initiated_by_account_id <> v_vendor_account THEN RAISE EXCEPTION 'VENDOR_PROPOSAL must be initiated by vendor account'; END IF;
    IF NEW.status IN ('APPLIED','DECLINED') AND NEW.decided_by_account_id <> b.customer_account_id THEN
      RAISE EXCEPTION 'Vendor proposal decision must be made by booking customer';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_reschedule_row_guard
BEFORE INSERT OR UPDATE ON reschedules
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_reschedule_row();

CREATE OR REPLACE FUNCTION pawpals_reschedule_deferred_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r reschedules%ROWTYPE;
DECLARE b bookings%ROWTYPE;
DECLARE old_status capacity_reservation_status;
DECLARE new_status capacity_reservation_status;
BEGIN
  SELECT * INTO r FROM reschedules WHERE id = COALESCE(NEW.id, OLD.id);
  IF NOT FOUND OR r.status <> 'APPLIED' THEN RETURN NULL; END IF;
  SELECT * INTO b FROM bookings WHERE id = r.booking_id FOR UPDATE;

  IF b.scheduled_start_at <> r.proposed_start_at OR b.scheduled_end_at <> r.proposed_end_at OR b.occupied_end_at <> r.proposed_occupied_end_at THEN
    RAISE EXCEPTION 'APPLIED reschedule must update Booking to proposed schedule';
  END IF;
  IF r.old_capacity_reservation_id IS NULL OR r.new_capacity_reservation_id IS NULL THEN
    RAISE EXCEPTION 'APPLIED reschedule requires old and new capacity reservations';
  END IF;
  SELECT status INTO old_status FROM capacity_reservations WHERE id=r.old_capacity_reservation_id;
  SELECT status INTO new_status FROM capacity_reservations WHERE id=r.new_capacity_reservation_id;
  IF old_status <> 'RELEASED' OR new_status <> 'COMMITTED' THEN
    RAISE EXCEPTION 'APPLIED paid reschedule requires old RELEASED and new COMMITTED capacity';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM booking_schedule_history h WHERE h.booking_id=r.booking_id AND h.reschedule_id=r.id) THEN
    RAISE EXCEPTION 'APPLIED reschedule requires BookingScheduleHistory';
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_reschedule_guard
AFTER INSERT OR UPDATE ON reschedules
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_reschedule_deferred_guard();

-- ------------------------------------------------------------
-- Ledger / settlement / payout
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_ledger_append_only()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'LedgerEntry is append-only; use corrective/reversal entry';
END;
$$;
CREATE TRIGGER trg_ledger_no_update BEFORE UPDATE ON ledger_entries FOR EACH ROW EXECUTE FUNCTION pawpals_ledger_append_only();
CREATE TRIGGER trg_ledger_no_delete BEFORE DELETE ON ledger_entries FOR EACH ROW EXECUTE FUNCTION pawpals_ledger_append_only();

CREATE OR REPLACE FUNCTION pawpals_guard_ledger_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
DECLARE p payments%ROWTYPE;
DECLARE r refunds%ROWTYPE;
BEGIN
  IF NEW.booking_id IS NOT NULL THEN
    SELECT * INTO b FROM bookings WHERE id=NEW.booking_id;
    IF NEW.currency <> b.currency THEN RAISE EXCEPTION 'Ledger currency differs from Booking'; END IF;
    IF NEW.vendor_id IS NOT NULL AND NEW.vendor_id <> b.vendor_id THEN RAISE EXCEPTION 'Ledger vendor differs from Booking vendor'; END IF;
  END IF;
  IF NEW.payment_id IS NOT NULL THEN
    SELECT * INTO p FROM payments WHERE id=NEW.payment_id;
    IF NEW.currency <> p.currency THEN RAISE EXCEPTION 'Ledger currency differs from Payment'; END IF;
    IF NEW.booking_id IS NOT NULL AND NEW.booking_id <> p.booking_id THEN RAISE EXCEPTION 'Ledger Payment belongs to another Booking'; END IF;
  END IF;
  IF NEW.refund_id IS NOT NULL THEN
    SELECT * INTO r FROM refunds WHERE id=NEW.refund_id;
    IF NEW.currency <> r.currency THEN RAISE EXCEPTION 'Ledger currency differs from Refund'; END IF;
    IF NEW.payment_id IS NOT NULL AND NEW.payment_id <> r.payment_id THEN RAISE EXCEPTION 'Ledger Refund belongs to another Payment'; END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_ledger_insert_guard BEFORE INSERT ON ledger_entries
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_ledger_insert();

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
    IF NOT FOUND OR c.fault_finalized_at IS NULL OR now() < c.claim_window_ends_at THEN
      RAISE EXCEPTION 'Cancellation compensation requires final attribution and ended claim window';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_settlement_guard BEFORE INSERT OR UPDATE ON settlement_items
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_settlement();

CREATE OR REPLACE FUNCTION pawpals_guard_payout()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a vendor_payout_accounts%ROWTYPE;
BEGIN
  IF TG_OP='UPDATE' AND (NEW.vendor_id<>OLD.vendor_id OR NEW.payout_account_id<>OLD.payout_account_id OR NEW.total_amount<>OLD.total_amount OR NEW.currency<>OLD.currency) THEN
    RAISE EXCEPTION 'Payout vendor/account/amount/currency are immutable';
  END IF;
  SELECT * INTO a FROM vendor_payout_accounts WHERE id=NEW.payout_account_id;
  IF a.vendor_id <> NEW.vendor_id THEN RAISE EXCEPTION 'Payout account belongs to another Vendor'; END IF;
  IF NEW.status IN ('QUEUED','PROCESSING') OR (TG_OP='INSERT' AND NEW.status='PAID') THEN
    IF a.is_active IS NOT TRUE OR a.verified_at IS NULL OR (a.security_hold_until IS NOT NULL AND a.security_hold_until > now()) THEN
      RAISE EXCEPTION 'Payout account is not eligible for payout processing';
    END IF;
  END IF;
  IF TG_OP='UPDATE' AND OLD.status='PAID' AND NEW.status <> 'PAID' THEN
    RAISE EXCEPTION 'PAID payout cannot downgrade';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payout_guard BEFORE INSERT OR UPDATE ON payouts
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_payout();

CREATE OR REPLACE FUNCTION pawpals_guard_payout_item()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p payouts%ROWTYPE;
DECLARE s settlement_items%ROWTYPE;
BEGIN
  SELECT * INTO p FROM payouts WHERE id=NEW.payout_id FOR UPDATE;
  SELECT * INTO s FROM settlement_items WHERE id=NEW.settlement_item_id FOR UPDATE;
  IF TG_OP='UPDATE' AND (NEW.payout_id<>OLD.payout_id OR NEW.settlement_item_id<>OLD.settlement_item_id OR NEW.amount_signed<>OLD.amount_signed OR NEW.allocated_at<>OLD.allocated_at) THEN
    RAISE EXCEPTION 'PayoutItem allocation identity/amount are immutable';
  END IF;
  IF p.vendor_id <> s.vendor_id THEN RAISE EXCEPTION 'PayoutItem Vendor mismatch'; END IF;
  IF p.currency <> s.currency THEN RAISE EXCEPTION 'PayoutItem currency mismatch'; END IF;
  IF NEW.amount_signed <> s.amount_signed THEN RAISE EXCEPTION 'MVP requires full SettlementItem allocation'; END IF;

  IF TG_OP='INSERT' OR (OLD.released_at IS NOT NULL AND NEW.released_at IS NULL) THEN
    IF s.status NOT IN ('AVAILABLE','ALLOCATED') THEN RAISE EXCEPTION 'SettlementItem must be AVAILABLE for allocation'; END IF;
  END IF;
  IF TG_OP='UPDATE' AND OLD.released_at IS NULL AND NEW.released_at IS NOT NULL AND p.status <> 'FAILED' THEN
    RAISE EXCEPTION 'Active payout allocation may be released only after definitive FAILED payout';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payout_item_guard BEFORE INSERT OR UPDATE ON payout_items
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_payout_item();

CREATE OR REPLACE FUNCTION pawpals_check_payout_integrity(p_payout_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p payouts%ROWTYPE;
DECLARE v_sum bigint;
DECLARE v_bad integer;
DECLARE v_active integer;
BEGIN
  SELECT * INTO p FROM payouts WHERE id=p_payout_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT COALESCE(sum(amount_signed),0), count(*)
    INTO v_sum, v_active
  FROM payout_items
  WHERE payout_id=p.id AND released_at IS NULL;

  SELECT count(*) INTO v_bad
  FROM payout_items pi
  JOIN settlement_items s ON s.id=pi.settlement_item_id
  WHERE pi.payout_id=p.id AND pi.released_at IS NULL
    AND (s.vendor_id<>p.vendor_id OR s.currency<>p.currency);
  IF v_bad>0 THEN RAISE EXCEPTION 'Payout contains mismatched SettlementItem'; END IF;

  IF p.status IN ('QUEUED','PROCESSING','PAID') AND v_sum <> p.total_amount THEN
    RAISE EXCEPTION 'Payout total must equal active PayoutItems sum';
  END IF;

  IF p.status IN ('QUEUED','PROCESSING') AND EXISTS (
    SELECT 1 FROM payout_items pi
    JOIN settlement_items s ON s.id=pi.settlement_item_id
    WHERE pi.payout_id=p.id AND pi.released_at IS NULL AND s.status<>'ALLOCATED'
  ) THEN
    RAISE EXCEPTION 'QUEUED/PROCESSING payout requires active SettlementItems ALLOCATED';
  END IF;

  IF p.status='PAID' AND EXISTS (
    SELECT 1 FROM payout_items pi
    JOIN settlement_items s ON s.id=pi.settlement_item_id
    WHERE pi.payout_id=p.id AND pi.released_at IS NULL AND s.status<>'SETTLED'
  ) THEN
    RAISE EXCEPTION 'PAID payout requires all active SettlementItems SETTLED';
  END IF;

  IF p.status='FAILED' AND v_active <> 0 THEN
    RAISE EXCEPTION 'Definitive FAILED payout must release all active allocations';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pawpals_payout_deferred_from_payout()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pawpals_check_payout_integrity(NEW.id);
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_payout_from_payout
AFTER INSERT OR UPDATE ON payouts DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_payout_deferred_from_payout();

CREATE OR REPLACE FUNCTION pawpals_payout_deferred_from_item()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pawpals_check_payout_integrity(NEW.payout_id);
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_payout_from_item
AFTER INSERT OR UPDATE ON payout_items DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION pawpals_payout_deferred_from_item();

CREATE OR REPLACE FUNCTION pawpals_payout_item_no_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'PayoutItem history cannot be deleted; release allocation using released_at';
END;
$$;
CREATE TRIGGER trg_payout_item_no_delete BEFORE DELETE ON payout_items
FOR EACH ROW EXECUTE FUNCTION pawpals_payout_item_no_delete();

CREATE OR REPLACE FUNCTION pawpals_refund_no_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Refund history cannot be deleted; use corrective Refund rows';
END;
$$;
CREATE TRIGGER trg_refund_no_delete BEFORE DELETE ON refunds
FOR EACH ROW EXECUTE FUNCTION pawpals_refund_no_delete();

-- ------------------------------------------------------------
-- Interaction / review participant guards
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_is_booking_participant(p_booking uuid, p_account uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM bookings b JOIN vendors v ON v.id=b.vendor_id
    WHERE b.id=p_booking AND (b.customer_account_id=p_account OR v.account_id=p_account)
  );
$$;

CREATE OR REPLACE FUNCTION pawpals_guard_chat_message()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.sender_account_id IS NOT NULL AND NOT pawpals_is_booking_participant(NEW.booking_id, NEW.sender_account_id) THEN
    RAISE EXCEPTION 'Chat sender must be booking participant';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_chat_message_participant BEFORE INSERT OR UPDATE ON booking_chat_messages
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_chat_message();

CREATE OR REPLACE FUNCTION pawpals_guard_chat_read()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT pawpals_is_booking_participant(NEW.booking_id, NEW.account_id) THEN
    RAISE EXCEPTION 'Chat read state account must be booking participant';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_chat_read_participant BEFORE INSERT OR UPDATE ON booking_chat_read_states
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_chat_read();

CREATE OR REPLACE FUNCTION pawpals_guard_milestone()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT pawpals_is_booking_participant(NEW.booking_id, NEW.created_by_account_id) THEN
    RAISE EXCEPTION 'Milestone creator must be booking participant';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_milestone_participant BEFORE INSERT OR UPDATE ON booking_milestones
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_milestone();

CREATE OR REPLACE FUNCTION pawpals_guard_review()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE;
BEGIN
  SELECT * INTO b FROM bookings WHERE id=NEW.booking_id;
  IF b.status <> 'COMPLETED' THEN RAISE EXCEPTION 'Review requires COMPLETED Booking'; END IF;
  IF NEW.reviewer_account_id <> b.customer_account_id THEN RAISE EXCEPTION 'Reviewer must be Booking customer'; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_review_guard BEFORE INSERT OR UPDATE ON reviews
FOR EACH ROW EXECUTE FUNCTION pawpals_guard_review();

-- ------------------------------------------------------------
-- Media classification guards
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pawpals_assert_media_class(p_media uuid, p_expected data_classification)
RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE v_class data_classification;
BEGIN
  IF p_media IS NULL THEN RETURN; END IF;
  SELECT data_class INTO v_class FROM media_objects WHERE id=p_media AND deleted_at IS NULL;
  IF v_class IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'MediaObject % must have classification %', p_media, p_expected;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pawpals_guard_vendor_doc_media() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pawpals_assert_media_class(NEW.media_object_id,'VERIFICATION_SENSITIVE'); RETURN NEW; END; $$;
CREATE TRIGGER trg_vendor_doc_media BEFORE INSERT OR UPDATE ON vendor_verification_documents FOR EACH ROW EXECUTE FUNCTION pawpals_guard_vendor_doc_media();

CREATE OR REPLACE FUNCTION pawpals_guard_pet_media() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pawpals_assert_media_class(NEW.photo_media_object_id,'PET_SENSITIVE'); RETURN NEW; END; $$;
CREATE TRIGGER trg_pet_media BEFORE INSERT OR UPDATE ON pets FOR EACH ROW EXECUTE FUNCTION pawpals_guard_pet_media();

CREATE OR REPLACE FUNCTION pawpals_guard_chat_media() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pawpals_assert_media_class(NEW.attachment_media_object_id,'BOOKING_PRIVATE'); RETURN NEW; END; $$;
CREATE TRIGGER trg_chat_media BEFORE INSERT OR UPDATE ON booking_chat_messages FOR EACH ROW EXECUTE FUNCTION pawpals_guard_chat_media();

CREATE OR REPLACE FUNCTION pawpals_guard_milestone_media() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pawpals_assert_media_class(NEW.media_object_id,'BOOKING_PRIVATE'); RETURN NEW; END; $$;
CREATE TRIGGER trg_milestone_media BEFORE INSERT OR UPDATE ON booking_milestones FOR EACH ROW EXECUTE FUNCTION pawpals_guard_milestone_media();

CREATE OR REPLACE FUNCTION pawpals_guard_case_evidence_media() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pawpals_assert_media_class(NEW.media_object_id,'INCIDENT_RESTRICTED'); RETURN NEW; END; $$;
CREATE TRIGGER trg_case_evidence_media BEFORE INSERT OR UPDATE ON case_evidence FOR EACH ROW EXECUTE FUNCTION pawpals_guard_case_evidence_media();

COMMIT;
