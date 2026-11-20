-- PawPals PDB-02/03/08: ERD-09 Cancellation, Attribution, Reschedule
BEGIN;

CREATE TABLE booking_cancellations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  cancelled_by cancellation_actor NOT NULL,
  fault_party cancellation_fault_party NOT NULL,
  reason_code varchar(100),
  reason_text text,
  calculated_refund_amount bigint NOT NULL,
  retained_settlement_base_amount bigint NOT NULL,
  policy_evaluation_snapshot_json jsonb NOT NULL,
  fault_finalized_at timestamptz,
  claim_window_ends_at timestamptz NOT NULL,
  cancelled_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_cancellation_amounts CHECK (calculated_refund_amount >= 0 AND retained_settlement_base_amount >= 0),
  CONSTRAINT ck_cancellation_claim_window CHECK (claim_window_ends_at >= cancelled_at),
  CONSTRAINT ck_vendor_cancellation_fault CHECK (cancelled_by <> 'VENDOR' OR fault_party = 'VENDOR')
);

CREATE TABLE cancellation_attribution_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_cancellation_id uuid NOT NULL REFERENCES booking_cancellations(id) ON DELETE RESTRICT,
  from_fault_party cancellation_fault_party,
  to_fault_party cancellation_fault_party NOT NULL,
  changed_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vendor_cancellation_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_cancellation_id uuid NOT NULL UNIQUE REFERENCES booking_cancellations(id) ON DELETE RESTRICT,
  status vendor_cancellation_claim_status NOT NULL DEFAULT 'OPEN',
  customer_claim_text text,
  vendor_response_text text,
  vendor_response_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  opened_at timestamptz NOT NULL DEFAULT now(),
  vendor_responded_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendor_claim_response_time CHECK (vendor_response_by_account_id IS NULL OR vendor_responded_at IS NOT NULL),
  CONSTRAINT ck_vendor_claim_resolved_time CHECK (status <> 'RESOLVED' OR resolved_at IS NOT NULL)
);

CREATE TABLE reschedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  mode reschedule_mode NOT NULL,
  status reschedule_status NOT NULL DEFAULT 'PENDING',
  initiated_by_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  decided_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  old_start_at timestamptz NOT NULL,
  old_end_at timestamptz NOT NULL,
  old_occupied_end_at timestamptz NOT NULL,
  proposed_start_at timestamptz NOT NULL,
  proposed_end_at timestamptz NOT NULL,
  proposed_occupied_end_at timestamptz NOT NULL,
  old_capacity_reservation_id uuid,
  new_capacity_reservation_id uuid,
  requested_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_reschedule_old_time CHECK (old_start_at < old_end_at AND old_end_at <= old_occupied_end_at),
  CONSTRAINT ck_reschedule_new_time CHECK (proposed_start_at < proposed_end_at AND proposed_end_at <= proposed_occupied_end_at),
  CONSTRAINT ck_reschedule_decision_time CHECK (status NOT IN ('APPLIED','DECLINED') OR decided_at IS NOT NULL),
  CONSTRAINT ck_reschedule_applied_time CHECK (status <> 'APPLIED' OR applied_at IS NOT NULL)
);

CREATE TABLE booking_schedule_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  reschedule_id uuid,
  revision_no integer NOT NULL,
  scheduled_start_at timestamptz NOT NULL,
  scheduled_end_at timestamptz NOT NULL,
  occupied_end_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_booking_schedule_revision CHECK (revision_no > 0),
  CONSTRAINT ck_booking_schedule_time CHECK (scheduled_start_at < scheduled_end_at AND scheduled_end_at <= occupied_end_at),
  CONSTRAINT uq_booking_schedule_revision UNIQUE (booking_id, revision_no)
);

COMMIT;
