-- PawPals PDB-02/03: ERD-06 Booking & immutable snapshots
BEGIN;

CREATE TABLE bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  vendor_service_id uuid NOT NULL REFERENCES vendor_services(id) ON DELETE RESTRICT,
  status booking_status NOT NULL DEFAULT 'CREATED',
  scheduled_start_at timestamptz NOT NULL,
  scheduled_end_at timestamptz NOT NULL,
  occupied_end_at timestamptz NOT NULL,
  total_amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  confirmed_at timestamptz,
  service_started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_booking_time CHECK (scheduled_start_at < scheduled_end_at AND scheduled_end_at <= occupied_end_at),
  CONSTRAINT ck_booking_amount CHECK (total_amount >= 0),
  CONSTRAINT ck_booking_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_booking_state_timestamps CHECK (
    (status NOT IN ('CONFIRMED','IN_PROGRESS','COMPLETED') OR confirmed_at IS NOT NULL) AND
    (status NOT IN ('IN_PROGRESS','COMPLETED') OR service_started_at IS NOT NULL) AND
    (status <> 'COMPLETED' OR completed_at IS NOT NULL) AND
    (status NOT IN ('CUSTOMER_CANCELLED','VENDOR_CANCELLED','PLATFORM_CANCELLED') OR cancelled_at IS NOT NULL)
  )
);

CREATE TABLE booking_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  pet_id uuid NOT NULL REFERENCES pets(id) ON DELETE RESTRICT,
  service_package_id uuid NOT NULL REFERENCES service_packages(id) ON DELETE RESTRICT,
  pet_snapshot_json jsonb NOT NULL,
  compatibility_snapshot_json jsonb NOT NULL,
  service_name_snapshot varchar(180),
  package_name_snapshot varchar(150),
  price_amount_snapshot bigint NOT NULL,
  duration_minutes_snapshot integer NOT NULL,
  buffer_after_minutes_snapshot integer NOT NULL,
  minimum_notice_minutes_snapshot integer NOT NULL,
  booking_specific_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_booking_item_price CHECK (price_amount_snapshot >= 0),
  CONSTRAINT ck_booking_item_duration CHECK (duration_minutes_snapshot > 0),
  CONSTRAINT ck_booking_item_buffer CHECK (buffer_after_minutes_snapshot >= 0),
  CONSTRAINT ck_booking_item_notice CHECK (minimum_notice_minutes_snapshot >= 0)
);

CREATE TABLE booking_location_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  delivery_mode_snapshot booking_delivery_mode_snapshot NOT NULL,
  address_snapshot text NOT NULL,
  latitude numeric(9,6) NOT NULL,
  longitude numeric(9,6) NOT NULL,
  service_radius_meters_snapshot integer,
  distance_meters_snapshot integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_booking_location_lat CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT ck_booking_location_lon CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT ck_booking_location_distance CHECK (distance_meters_snapshot IS NULL OR distance_meters_snapshot >= 0),
  CONSTRAINT ck_booking_location_radius CHECK (service_radius_meters_snapshot IS NULL OR service_radius_meters_snapshot > 0),
  CONSTRAINT ck_booking_location_mode CHECK (
    (delivery_mode_snapshot = 'AT_CUSTOMER' AND service_radius_meters_snapshot IS NOT NULL AND distance_meters_snapshot IS NOT NULL AND distance_meters_snapshot <= service_radius_meters_snapshot) OR
    (delivery_mode_snapshot = 'AT_VENDOR')
  )
);

CREATE TABLE booking_policy_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  policy_version varchar(80) NOT NULL,
  commission_rate_bps integer NOT NULL,
  cancellation_tiers_snapshot_json jsonb NOT NULL,
  payment_hold_minutes integer NOT NULL,
  settlement_hold_minutes integer NOT NULL,
  cancellation_claim_window_minutes integer NOT NULL,
  customer_self_reschedule_min_notice_minutes integer NOT NULL,
  customer_self_reschedule_max_applied_count integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_policy_commission_bps CHECK (commission_rate_bps BETWEEN 0 AND 10000),
  CONSTRAINT ck_policy_payment_hold CHECK (payment_hold_minutes > 0),
  CONSTRAINT ck_policy_settlement_hold CHECK (settlement_hold_minutes >= 0),
  CONSTRAINT ck_policy_claim_window CHECK (cancellation_claim_window_minutes >= 0),
  CONSTRAINT ck_policy_reschedule_notice CHECK (customer_self_reschedule_min_notice_minutes >= 0),
  CONSTRAINT ck_policy_reschedule_count CHECK (customer_self_reschedule_max_applied_count >= 0)
);

CREATE TABLE booking_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  from_status booking_status,
  to_status booking_status NOT NULL,
  actor_type booking_transition_actor_type NOT NULL,
  actor_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_booking_history_actor CHECK (
    (actor_type = 'SYSTEM' AND actor_account_id IS NULL) OR
    (actor_type = 'ACCOUNT' AND actor_account_id IS NOT NULL)
  )
);

COMMIT;
