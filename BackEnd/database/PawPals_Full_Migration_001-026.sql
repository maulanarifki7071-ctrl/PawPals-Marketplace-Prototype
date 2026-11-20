-- ===========================================================================
-- 001_extensions.sql
-- ===========================================================================
-- PawPals PDB-01: PostgreSQL foundation / required extensions
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

COMMIT;

-- ===========================================================================
-- 002_enums.sql
-- ===========================================================================
-- PawPals PDB-01: canonical enums. Values mirror the frozen State Machines / Logical ERD.
BEGIN;

CREATE TYPE account_status AS ENUM ('PENDING_PHONE_VERIFICATION','ACTIVE','DISABLED');
CREATE TYPE session_status AS ENUM ('ACTIVE','EXPIRED','REVOKED');
CREATE TYPE otp_purpose AS ENUM ('PHONE_VERIFICATION','PASSWORD_RESET','PAYOUT_ACCOUNT_CHANGE','SENSITIVE_PROFILE_CHANGE');
CREATE TYPE otp_status AS ENUM ('PENDING','VERIFIED','EXPIRED','LOCKED','CANCELLED');
CREATE TYPE otp_channel AS ENUM ('WHATSAPP','SMS');
CREATE TYPE otp_delivery_status AS ENUM ('QUEUED','SENT','DELIVERED','FAILED');
CREATE TYPE role_assignment_status AS ENUM ('ACTIVE','REVOKED');

CREATE TYPE vendor_type AS ENUM ('INDIVIDUAL','BUSINESS');
CREATE TYPE vendor_status AS ENUM ('PENDING_APPROVAL','ACTIVE','SUSPENDED');
CREATE TYPE vendor_application_status AS ENUM ('DRAFT','SUBMITTED','UNDER_REVIEW','NEEDS_REVISION','APPROVED','REJECTED');
CREATE TYPE verification_document_type AS ENUM ('KTP','VERIFICATION_SELFIE','NIB_BUSINESS_EVIDENCE','PROFESSIONAL_CREDENTIAL','PORTFOLIO');
CREATE TYPE verification_document_status AS ENUM ('SUBMITTED','VERIFIED','NEEDS_REPLACEMENT','REJECTED');

CREATE TYPE vendor_location_type AS ENUM ('VERIFICATION_PRIVATE','OPERATIONAL_PRIVATE','PUBLIC_BUSINESS');
CREATE TYPE service_delivery_mode AS ENUM ('AT_VENDOR','AT_CUSTOMER');
CREATE TYPE service_status AS ENUM ('DRAFT','ACTIVE','INACTIVE');

CREATE TYPE booking_status AS ENUM ('CREATED','AWAITING_PAYMENT','CONFIRMED','IN_PROGRESS','COMPLETED','EXPIRED','CUSTOMER_CANCELLED','VENDOR_CANCELLED','PLATFORM_CANCELLED');
CREATE TYPE booking_transition_actor_type AS ENUM ('ACCOUNT','SYSTEM');
CREATE TYPE booking_delivery_mode_snapshot AS ENUM ('AT_VENDOR','AT_CUSTOMER');
CREATE TYPE capacity_reservation_status AS ENUM ('HELD','COMMITTED','RELEASED','EXPIRED');

CREATE TYPE payment_status AS ENUM ('PENDING','PAID','FAILED','EXPIRED');
CREATE TYPE refund_status AS ENUM ('REQUESTED','PROCESSING','SUCCEEDED','FAILED');
CREATE TYPE refund_initiator_type AS ENUM ('SYSTEM','CUSTOMER','VENDOR','ADMIN');

CREATE TYPE cancellation_actor AS ENUM ('CUSTOMER','VENDOR','PLATFORM');
CREATE TYPE cancellation_fault_party AS ENUM ('PENDING_REVIEW','CUSTOMER','VENDOR','PLATFORM');
CREATE TYPE vendor_cancellation_claim_status AS ENUM ('OPEN','VENDOR_ADMITTED','VENDOR_DENIED','UNDER_REVIEW','RESOLVED');
CREATE TYPE reschedule_mode AS ENUM ('CUSTOMER_SELF','VENDOR_PROPOSAL');
CREATE TYPE reschedule_status AS ENUM ('PENDING','APPLIED','DECLINED','FAILED','CANCELLED');

CREATE TYPE settlement_source_type AS ENUM ('SERVICE_EARNING','CANCELLATION_COMPENSATION','NEGATIVE_ADJUSTMENT');
CREATE TYPE settlement_status AS ENUM ('PENDING','HOLD','AVAILABLE','ALLOCATED','SETTLED','REVERSED');
CREATE TYPE payout_status AS ENUM ('QUEUED','PROCESSING','PAID','FAILED');
CREATE TYPE ledger_posting_type AS ENUM (
  'PAYMENT_RECEIVED','SERVICE_EARNING','SERVICE_EARNING_REVERSAL',
  'PLATFORM_COMMISSION','PLATFORM_COMMISSION_REVERSAL',
  'CANCELLATION_COMPENSATION','CANCELLATION_COMPENSATION_REVERSAL',
  'REFUND','NEGATIVE_ADJUSTMENT','PAYOUT_DISBURSED'
);

CREATE TYPE chat_message_type AS ENUM ('TEXT','SYSTEM','IMAGE');

CREATE TYPE case_type AS ENUM ('REPORT','INCIDENT','DISPUTE','PAYMENT_EXCEPTION');
CREATE TYPE case_status AS ENUM ('OPEN','TRIAGED','INVESTIGATING','RESOLVED','CLOSED');
CREATE TYPE case_actor_type AS ENUM ('ACCOUNT','ADMIN','SYSTEM');
CREATE TYPE audit_actor_type AS ENUM ('SYSTEM','ACCOUNT','ADMIN','PROVIDER');
CREATE TYPE data_classification AS ENUM ('ACCOUNT_PRIVATE','VERIFICATION_SENSITIVE','FINANCIAL_SENSITIVE','PET_SENSITIVE','BOOKING_PRIVATE','INCIDENT_RESTRICTED');

CREATE TYPE outbox_event_status AS ENUM ('PENDING','PUBLISHED','DEAD_LETTER');

COMMIT;

-- ===========================================================================
-- 003_auth.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-01 Account, OTP, Session, RBAC
BEGIN;

CREATE TABLE accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 varchar(20) NOT NULL UNIQUE,
  email varchar(255) UNIQUE,
  display_name varchar(150) NOT NULL,
  status account_status NOT NULL DEFAULT 'PENDING_PHONE_VERIFICATION',
  phone_verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_accounts_phone_e164 CHECK (phone_e164 ~ '^\\+[1-9][0-9]{7,14}$'),
  CONSTRAINT ck_accounts_verified_when_nonpending CHECK (status = 'PENDING_PHONE_VERIFICATION' OR phone_verified_at IS NOT NULL)
);

CREATE TABLE account_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE RESTRICT,
  password_hash text NOT NULL,
  password_algorithm varchar(50),
  password_updated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE otp_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  purpose otp_purpose NOT NULL,
  status otp_status NOT NULL DEFAULT 'PENDING',
  attempt_count integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL,
  expires_at timestamptz NOT NULL,
  verified_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_otp_attempts CHECK (attempt_count >= 0 AND max_attempts > 0 AND attempt_count <= max_attempts),
  CONSTRAINT ck_otp_expiry_after_creation CHECK (expires_at > created_at),
  CONSTRAINT ck_otp_verified_timestamp CHECK (status <> 'VERIFIED' OR verified_at IS NOT NULL),
  CONSTRAINT ck_otp_consumed_after_verified CHECK (consumed_at IS NULL OR verified_at IS NOT NULL)
);

CREATE TABLE otp_delivery_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  otp_challenge_id uuid NOT NULL REFERENCES otp_challenges(id) ON DELETE RESTRICT,
  channel otp_channel NOT NULL,
  provider varchar(50),
  provider_reference varchar(255),
  status otp_delivery_status NOT NULL DEFAULT 'QUEUED',
  sent_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_otp_delivery_timestamps CHECK (
    (status <> 'SENT' OR sent_at IS NOT NULL) AND
    (status <> 'DELIVERED' OR delivered_at IS NOT NULL) AND
    (status <> 'FAILED' OR failed_at IS NOT NULL)
  )
);

CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  session_token_hash text NOT NULL UNIQUE,
  status session_status NOT NULL DEFAULT 'ACTIVE',
  ip_address varchar(64),
  user_agent text,
  last_seen_at timestamptz,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_auth_session_expiry CHECK (expires_at > created_at),
  CONSTRAINT ck_auth_session_revoked_timestamp CHECK (status <> 'REVOKED' OR revoked_at IS NOT NULL),
  CONSTRAINT ck_auth_session_active_not_revoked CHECK (status <> 'ACTIVE' OR revoked_at IS NULL)
);

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code varchar(80) NOT NULL UNIQUE,
  name varchar(120) NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code varchar(120) NOT NULL UNIQUE,
  module varchar(80) NOT NULL,
  name varchar(150) NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE role_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_role_permissions UNIQUE (role_id, permission_id)
);

CREATE TABLE account_role_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  assigned_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  status role_assignment_status NOT NULL DEFAULT 'ACTIVE',
  assigned_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CONSTRAINT ck_role_assignment_revoked_at CHECK (
    (status = 'ACTIVE' AND revoked_at IS NULL) OR
    (status = 'REVOKED' AND revoked_at IS NOT NULL)
  )
);

COMMIT;

-- ===========================================================================
-- 004_vendor.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-02 Vendor Registration & Verification
-- Media FKs are added after media_objects exists in migration 017.
BEGIN;

CREATE TABLE vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE RESTRICT,
  vendor_type vendor_type NOT NULL,
  public_display_name varchar(180) NOT NULL,
  business_name varchar(180),
  status vendor_status NOT NULL DEFAULT 'PENDING_APPROVAL',
  approved_at timestamptz,
  suspended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendor_status_timestamps CHECK (
    (status = 'PENDING_APPROVAL') OR
    (status = 'ACTIVE' AND approved_at IS NOT NULL) OR
    (status = 'SUSPENDED' AND approved_at IS NOT NULL AND suspended_at IS NOT NULL)
  )
);

CREATE TABLE vendor_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  status vendor_application_status NOT NULL DEFAULT 'DRAFT',
  declared_identity_name varchar(180),
  business_name varchar(180),
  representative_name varchar(180),
  reviewed_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  submitted_at timestamptz,
  review_started_at timestamptz,
  decided_at timestamptz,
  decision_reason text,
  terms_version varchar(80),
  terms_accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendor_application_terms CHECK (
    status = 'DRAFT' OR (terms_version IS NOT NULL AND terms_accepted_at IS NOT NULL)
  ),
  CONSTRAINT ck_vendor_application_submitted_at CHECK (status = 'DRAFT' OR submitted_at IS NOT NULL),
  CONSTRAINT ck_vendor_application_review_time CHECK (
    status NOT IN ('UNDER_REVIEW','NEEDS_REVISION','APPROVED','REJECTED') OR review_started_at IS NOT NULL
  ),
  CONSTRAINT ck_vendor_application_decision_time CHECK (
    status NOT IN ('APPROVED','REJECTED') OR decided_at IS NOT NULL
  )
);

CREATE TABLE vendor_application_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_application_id uuid NOT NULL REFERENCES vendor_applications(id) ON DELETE RESTRICT,
  from_status vendor_application_status,
  to_status vendor_application_status NOT NULL,
  changed_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vendor_verification_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_application_id uuid NOT NULL REFERENCES vendor_applications(id) ON DELETE RESTRICT,
  document_type verification_document_type NOT NULL,
  status verification_document_status NOT NULL DEFAULT 'SUBMITTED',
  media_object_id uuid NOT NULL UNIQUE,
  reviewed_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  review_reason text,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_verification_document_verified_at CHECK (status <> 'VERIFIED' OR verified_at IS NOT NULL)
);

COMMIT;

-- ===========================================================================
-- 005_location.sql
-- ===========================================================================
-- PawPals PDB-02/03/04: ERD-03 Location + PostGIS physical representation.
-- latitude/longitude remain the logical inputs; location is generated and is authoritative for spatial queries.
BEGIN;

CREATE TABLE customer_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE customer_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  label varchar(80),
  address_line1 text NOT NULL,
  address_line2 text,
  city varchar(120),
  province varchar(120),
  postal_code varchar(20),
  latitude numeric(9,6) NOT NULL,
  longitude numeric(9,6) NOT NULL,
  location geography(Point,4326) GENERATED ALWAYS AS (
    ST_SetSRID(ST_MakePoint(longitude::double precision, latitude::double precision),4326)::geography
  ) STORED,
  geocoding_provider varchar(50),
  provider_reference varchar(255),
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_customer_address_lat CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT ck_customer_address_lon CHECK (longitude BETWEEN -180 AND 180)
);

CREATE TABLE vendor_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  location_type vendor_location_type NOT NULL,
  address_line1 text,
  city varchar(120),
  province varchar(120),
  latitude numeric(9,6) NOT NULL,
  longitude numeric(9,6) NOT NULL,
  location geography(Point,4326) GENERATED ALWAYS AS (
    ST_SetSRID(ST_MakePoint(longitude::double precision, latitude::double precision),4326)::geography
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendor_location_lat CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT ck_vendor_location_lon CHECK (longitude BETWEEN -180 AND 180)
);

COMMIT;

-- ===========================================================================
-- 006_pet.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-04 Pet Profile & Safety
-- Media FK is added in migration 017 after media_objects is created.
BEGIN;

CREATE TABLE pets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  name varchar(120) NOT NULL,
  species_code varchar(50) NOT NULL,
  breed varchar(120),
  birth_date date,
  sex varchar(30),
  weight_kg numeric(6,2),
  size_code varchar(50),
  photo_media_object_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_pet_weight CHECK (weight_kg IS NULL OR weight_kg > 0)
);

CREATE TABLE pet_safety_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pet_id uuid NOT NULL UNIQUE REFERENCES pets(id) ON DELETE RESTRICT,
  is_reactive boolean,
  aggression_history boolean,
  escape_risk boolean,
  leash_behavior_notes text,
  handling_sensitivity_notes text,
  allergy_notes text,
  known_health_history text,
  medication_notes text,
  routine_notes text,
  emergency_contact_name varchar(150),
  emergency_contact_phone varchar(30),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;

-- ===========================================================================
-- 007_service.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-05 Vendor Service, Package, Availability, Capacity Config
BEGIN;

CREATE TABLE vendor_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  origin_vendor_location_id uuid,
  category_code varchar(80) NOT NULL,
  name varchar(180) NOT NULL,
  description text,
  delivery_mode service_delivery_mode NOT NULL,
  service_radius_meters integer,
  minimum_notice_minutes integer NOT NULL,
  buffer_after_minutes integer NOT NULL,
  base_capacity integer NOT NULL,
  status service_status NOT NULL DEFAULT 'DRAFT',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendor_service_notice CHECK (minimum_notice_minutes >= 0),
  CONSTRAINT ck_vendor_service_buffer CHECK (buffer_after_minutes >= 0),
  CONSTRAINT ck_vendor_service_capacity CHECK (base_capacity >= 1),
  CONSTRAINT ck_vendor_service_delivery_radius CHECK (
    (delivery_mode = 'AT_VENDOR' AND service_radius_meters IS NULL) OR
    (delivery_mode = 'AT_CUSTOMER' AND service_radius_meters IS NOT NULL AND service_radius_meters > 0)
  ),
  CONSTRAINT ck_vendor_service_active_origin CHECK (status <> 'ACTIVE' OR origin_vendor_location_id IS NOT NULL)
);

CREATE TABLE service_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_service_id uuid NOT NULL REFERENCES vendor_services(id) ON DELETE RESTRICT,
  name varchar(150) NOT NULL,
  description text,
  duration_minutes integer NOT NULL,
  price_amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  is_active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_service_package_duration CHECK (duration_minutes > 0),
  CONSTRAINT ck_service_package_price CHECK (price_amount >= 0),
  CONSTRAINT ck_service_package_currency CHECK (currency = 'IDR')
);

CREATE TABLE vendor_service_pet_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_service_id uuid NOT NULL UNIQUE REFERENCES vendor_services(id) ON DELETE RESTRICT,
  accepted_species_json jsonb NOT NULL,
  accepted_size_codes_json jsonb,
  accepts_reactive boolean NOT NULL,
  accepts_aggressive_history boolean NOT NULL,
  deterministic_restrictions_json jsonb,
  context_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE service_availability_windows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_service_id uuid NOT NULL REFERENCES vendor_services(id) ON DELETE RESTRICT,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_service_availability_range CHECK (starts_at < ends_at)
);

CREATE TABLE service_capacity_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_service_id uuid NOT NULL REFERENCES vendor_services(id) ON DELETE RESTRICT,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  capacity integer NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_service_capacity_override_range CHECK (starts_at < ends_at),
  CONSTRAINT ck_service_capacity_override_value CHECK (capacity >= 0)
);

COMMIT;

-- ===========================================================================
-- 008_booking.sql
-- ===========================================================================
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

-- ===========================================================================
-- 009_capacity.sql
-- ===========================================================================
-- PawPals PDB-02/03/05: ERD-07 Capacity Reservation
-- Cross-row overlap/capacity checks are implemented as deferred constraint triggers in migration 021.
BEGIN;

CREATE TABLE capacity_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  vendor_service_id uuid NOT NULL REFERENCES vendor_services(id) ON DELETE RESTRICT,
  service_package_id uuid NOT NULL REFERENCES service_packages(id) ON DELETE RESTRICT,
  status capacity_reservation_status NOT NULL DEFAULT 'HELD',
  capacity_units integer NOT NULL DEFAULT 1,
  starts_at timestamptz NOT NULL,
  service_ends_at timestamptz NOT NULL,
  occupied_ends_at timestamptz NOT NULL,
  expires_at timestamptz,
  committed_at timestamptz,
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_capacity_units_mvp CHECK (capacity_units = 1),
  CONSTRAINT ck_capacity_time CHECK (starts_at < service_ends_at AND service_ends_at <= occupied_ends_at),
  CONSTRAINT ck_capacity_lifecycle CHECK (
    (status <> 'HELD' OR expires_at IS NOT NULL) AND
    (status <> 'COMMITTED' OR committed_at IS NOT NULL) AND
    (status <> 'RELEASED' OR released_at IS NOT NULL) AND
    (status <> 'EXPIRED' OR expires_at IS NOT NULL)
  )
);

COMMIT;

-- ===========================================================================
-- 010_payment_refund.sql
-- ===========================================================================
-- PawPals PDB-02/03/06: ERD-08 Payment, Provider Event, Refund
BEGIN;

CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  provider varchar(50) NOT NULL,
  provider_transaction_id varchar(255) UNIQUE,
  provider_order_reference varchar(255) UNIQUE,
  amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  status payment_status NOT NULL DEFAULT 'PENDING',
  expires_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  failure_code varchar(100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_payment_amount CHECK (amount >= 0),
  CONSTRAINT ck_payment_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_payment_lifecycle CHECK (
    (status <> 'PENDING' OR expires_at IS NOT NULL) AND
    (status <> 'PAID' OR paid_at IS NOT NULL) AND
    (status <> 'FAILED' OR failed_at IS NOT NULL) AND
    (status <> 'EXPIRED' OR expires_at IS NOT NULL)
  )
);

CREATE TABLE payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  provider varchar(50) NOT NULL,
  provider_event_id varchar(255) NOT NULL,
  event_type varchar(100),
  provider_status varchar(100),
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  CONSTRAINT uq_payment_event_provider UNIQUE (provider, provider_event_id)
);

CREATE TABLE refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  status refund_status NOT NULL DEFAULT 'REQUESTED',
  amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  reason_code varchar(100),
  reason_text text,
  initiator_type refund_initiator_type NOT NULL,
  initiated_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  provider_ref varchar(255),
  requested_at timestamptz NOT NULL DEFAULT now(),
  processing_at timestamptz,
  succeeded_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_refund_amount CHECK (amount > 0),
  CONSTRAINT ck_refund_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_refund_initiator CHECK (
    (initiator_type = 'SYSTEM' AND initiated_by_account_id IS NULL) OR
    (initiator_type <> 'SYSTEM' AND initiated_by_account_id IS NOT NULL)
  ),
  CONSTRAINT ck_refund_lifecycle CHECK (
    (status <> 'PROCESSING' OR processing_at IS NOT NULL) AND
    (status <> 'SUCCEEDED' OR succeeded_at IS NOT NULL) AND
    (status <> 'FAILED' OR failed_at IS NOT NULL)
  )
);

CREATE TABLE refund_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_id uuid NOT NULL REFERENCES refunds(id) ON DELETE RESTRICT,
  attempt_no integer NOT NULL,
  provider_request_ref varchar(255),
  is_ambiguous boolean NOT NULL DEFAULT false,
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT ck_refund_attempt_no CHECK (attempt_no > 0),
  CONSTRAINT uq_refund_attempt UNIQUE (refund_id, attempt_no)
);

COMMIT;

-- ===========================================================================
-- 011_cancellation_reschedule.sql
-- ===========================================================================
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

-- ===========================================================================
-- 012_finance.sql
-- ===========================================================================
-- PawPals PDB-02/03/07: ERD-10 Ledger, Settlement, Payout
BEGIN;

CREATE TABLE ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid REFERENCES vendors(id) ON DELETE RESTRICT,
  booking_id uuid REFERENCES bookings(id) ON DELETE RESTRICT,
  payment_id uuid REFERENCES payments(id) ON DELETE RESTRICT,
  refund_id uuid REFERENCES refunds(id) ON DELETE RESTRICT,
  posting_type ledger_posting_type NOT NULL,
  canonical_event_type varchar(80) NOT NULL,
  canonical_event_id varchar(150) NOT NULL,
  amount_signed bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_ledger_amount_nonzero CHECK (amount_signed <> 0),
  CONSTRAINT ck_ledger_currency CHECK (currency = 'IDR'),
  CONSTRAINT uq_ledger_idempotency UNIQUE (canonical_event_type, canonical_event_id, posting_type)
);

CREATE TABLE settlement_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  origin_ledger_entry_id uuid NOT NULL UNIQUE REFERENCES ledger_entries(id) ON DELETE RESTRICT,
  source_type settlement_source_type NOT NULL,
  status settlement_status NOT NULL DEFAULT 'PENDING',
  amount_signed bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  hold_until timestamptz,
  available_at timestamptz,
  settled_at timestamptz,
  reversed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_settlement_amount_sign CHECK (
    (source_type IN ('SERVICE_EARNING','CANCELLATION_COMPENSATION') AND amount_signed > 0) OR
    (source_type = 'NEGATIVE_ADJUSTMENT' AND amount_signed < 0)
  ),
  CONSTRAINT ck_settlement_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_settlement_lifecycle CHECK (
    (status <> 'HOLD' OR hold_until IS NOT NULL) AND
    (status <> 'AVAILABLE' OR available_at IS NOT NULL) AND
    (status <> 'SETTLED' OR settled_at IS NOT NULL) AND
    (status <> 'REVERSED' OR reversed_at IS NOT NULL)
  )
);

CREATE TABLE settlement_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_item_id uuid NOT NULL REFERENCES settlement_items(id) ON DELETE RESTRICT,
  from_status settlement_status,
  to_status settlement_status NOT NULL,
  actor_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vendor_payout_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  bank_code varchar(50) NOT NULL,
  account_holder_name varchar(180) NOT NULL,
  account_number_encrypted text NOT NULL,
  account_number_last4 varchar(4) NOT NULL,
  provider_recipient_ref varchar(255),
  is_active boolean NOT NULL DEFAULT true,
  security_hold_until timestamptz,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_payout_account_last4 CHECK (account_number_last4 ~ '^[0-9]{4}$')
);

CREATE TABLE payouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id uuid NOT NULL REFERENCES vendors(id) ON DELETE RESTRICT,
  payout_account_id uuid NOT NULL REFERENCES vendor_payout_accounts(id) ON DELETE RESTRICT,
  status payout_status NOT NULL DEFAULT 'QUEUED',
  total_amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  provider varchar(50),
  provider_payout_ref varchar(255) UNIQUE,
  scheduled_for timestamptz,
  submitted_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_payout_total CHECK (total_amount > 0),
  CONSTRAINT ck_payout_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_payout_lifecycle CHECK (
    (status <> 'PROCESSING' OR submitted_at IS NOT NULL) AND
    (status <> 'PAID' OR paid_at IS NOT NULL) AND
    (status <> 'FAILED' OR failed_at IS NOT NULL)
  )
);

CREATE TABLE payout_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id uuid NOT NULL REFERENCES payouts(id) ON DELETE RESTRICT,
  settlement_item_id uuid NOT NULL REFERENCES settlement_items(id) ON DELETE RESTRICT,
  amount_signed bigint NOT NULL,
  allocated_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  CONSTRAINT ck_payout_item_nonzero CHECK (amount_signed <> 0)
);

CREATE TABLE payout_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id uuid NOT NULL REFERENCES payouts(id) ON DELETE RESTRICT,
  provider varchar(50) NOT NULL,
  provider_event_id varchar(255) NOT NULL,
  provider_status varchar(100),
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  CONSTRAINT uq_payout_event_provider UNIQUE (provider, provider_event_id)
);

CREATE TABLE payout_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id uuid NOT NULL REFERENCES payouts(id) ON DELETE RESTRICT,
  from_status payout_status,
  to_status payout_status NOT NULL,
  actor_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;

-- ===========================================================================
-- 013_interaction.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-11 Booking Chat, Milestone, Review
-- Media FKs are added in migration 017.
BEGIN;

CREATE TABLE booking_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  sender_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  message_type chat_message_type NOT NULL,
  body_text text,
  attachment_media_object_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_chat_message_payload CHECK (
    (message_type = 'TEXT' AND body_text IS NOT NULL AND sender_account_id IS NOT NULL) OR
    (message_type = 'IMAGE' AND attachment_media_object_id IS NOT NULL AND sender_account_id IS NOT NULL) OR
    (message_type = 'SYSTEM' AND sender_account_id IS NULL)
  )
);

CREATE TABLE booking_chat_read_states (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  last_read_message_id uuid REFERENCES booking_chat_messages(id) ON DELETE RESTRICT,
  last_read_at timestamptz,
  CONSTRAINT uq_booking_chat_read_state UNIQUE (booking_id, account_id)
);

CREATE TABLE booking_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  created_by_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  milestone_type varchar(80) NOT NULL,
  description text,
  media_object_id uuid,
  occurred_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  reviewer_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  rating smallint NOT NULL,
  comment text,
  is_visible boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_review_rating CHECK (rating BETWEEN 1 AND 5)
);

COMMIT;

-- ===========================================================================
-- 014_trust_safety.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-12 Trust & Safety, Evidence, Audit
-- Media FK is added in migration 017.
BEGIN;

CREATE TABLE support_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_type case_type NOT NULL,
  status case_status NOT NULL DEFAULT 'OPEN',
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  pet_id uuid REFERENCES pets(id) ON DELETE RESTRICT,
  opened_by_type case_actor_type NOT NULL,
  reporter_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  assigned_admin_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  category varchar(100) NOT NULL,
  severity varchar(50),
  description text NOT NULL,
  resolution_code varchar(100),
  resolution_notes text,
  opened_at timestamptz NOT NULL DEFAULT now(),
  triaged_at timestamptz,
  investigation_started_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_support_case_opener CHECK (
    (opened_by_type = 'SYSTEM' AND reporter_account_id IS NULL) OR
    (opened_by_type <> 'SYSTEM' AND reporter_account_id IS NOT NULL)
  ),
  CONSTRAINT ck_support_case_state_timestamps CHECK (
    (status NOT IN ('TRIAGED','INVESTIGATING','RESOLVED','CLOSED') OR triaged_at IS NOT NULL) AND
    (status NOT IN ('INVESTIGATING','RESOLVED','CLOSED') OR investigation_started_at IS NOT NULL) AND
    (status NOT IN ('RESOLVED','CLOSED') OR resolved_at IS NOT NULL) AND
    (status <> 'CLOSED' OR closed_at IS NOT NULL)
  )
);

CREATE TABLE case_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES support_cases(id) ON DELETE RESTRICT,
  uploaded_by_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  media_object_id uuid NOT NULL UNIQUE,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE case_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES support_cases(id) ON DELETE RESTRICT,
  from_status case_status,
  to_status case_status NOT NULL,
  changed_by_type case_actor_type NOT NULL,
  changed_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_case_history_actor CHECK (
    (changed_by_type = 'SYSTEM' AND changed_by_account_id IS NULL) OR
    (changed_by_type <> 'SYSTEM' AND changed_by_account_id IS NOT NULL)
  )
);

CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_type audit_actor_type NOT NULL,
  actor_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  action varchar(150) NOT NULL,
  target_type varchar(100) NOT NULL,
  target_id varchar(150) NOT NULL,
  reason text,
  metadata_sanitized_json jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_audit_actor CHECK (
    (actor_type IN ('SYSTEM','PROVIDER') AND actor_account_id IS NULL) OR
    (actor_type IN ('ACCOUNT','ADMIN') AND actor_account_id IS NOT NULL)
  )
);

CREATE TABLE sensitive_access_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  data_class data_classification NOT NULL,
  target_type varchar(100) NOT NULL,
  target_id varchar(150) NOT NULL,
  access_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;

-- ===========================================================================
-- 015_media.sql
-- ===========================================================================
-- PawPals PDB-02/03: ERD-13 cross-cutting MediaObject
BEGIN;

CREATE TABLE media_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uploaded_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  data_class data_classification NOT NULL,
  storage_provider varchar(50),
  object_key text NOT NULL UNIQUE,
  mime_type varchar(150),
  size_bytes bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT ck_media_size CHECK (size_bytes IS NULL OR size_bytes >= 0)
);

COMMIT;

-- ===========================================================================
-- 016_outbox.sql
-- ===========================================================================
-- PawPals PDB-09: Transactional Outbox
BEGIN;

CREATE TABLE outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key varchar(180) NOT NULL UNIQUE,
  aggregate_type varchar(100) NOT NULL,
  aggregate_id uuid NOT NULL,
  event_type varchar(150) NOT NULL,
  payload_json jsonb NOT NULL,
  status outbox_event_status NOT NULL DEFAULT 'PENDING',
  attempt_count integer NOT NULL DEFAULT 0,
  available_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_outbox_attempt_count CHECK (attempt_count >= 0),
  CONSTRAINT ck_outbox_published CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL)
);

COMMIT;

-- ===========================================================================
-- 017_constraints.sql
-- ===========================================================================
-- PawPals PDB-03: cross-domain FK / ownership constraints that require all tables to exist.
BEGIN;

-- Composite uniqueness used by ownership-preserving FKs.
ALTER TABLE vendor_locations ADD CONSTRAINT uq_vendor_locations_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE vendor_services ADD CONSTRAINT uq_vendor_services_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE service_packages ADD CONSTRAINT uq_service_packages_id_service UNIQUE (id, vendor_service_id);
ALTER TABLE bookings ADD CONSTRAINT uq_bookings_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE bookings ADD CONSTRAINT uq_bookings_id_service UNIQUE (id, vendor_service_id);
ALTER TABLE booking_items ADD CONSTRAINT uq_booking_items_booking_package UNIQUE (booking_id, service_package_id);
ALTER TABLE booking_items ADD CONSTRAINT uq_booking_items_booking_pet UNIQUE (booking_id, pet_id);
ALTER TABLE capacity_reservations ADD CONSTRAINT uq_capacity_id_booking UNIQUE (id, booking_id);
ALTER TABLE reschedules ADD CONSTRAINT uq_reschedules_id_booking UNIQUE (id, booking_id);
ALTER TABLE vendor_payout_accounts ADD CONSTRAINT uq_payout_accounts_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE booking_chat_messages ADD CONSTRAINT uq_chat_message_id_booking UNIQUE (id, booking_id);

-- Ownership consistency.
ALTER TABLE vendor_services
  ADD CONSTRAINT fk_vendor_service_origin_same_vendor
  FOREIGN KEY (origin_vendor_location_id, vendor_id)
  REFERENCES vendor_locations(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE bookings
  ADD CONSTRAINT fk_booking_service_same_vendor
  FOREIGN KEY (vendor_service_id, vendor_id)
  REFERENCES vendor_services(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE capacity_reservations
  ADD CONSTRAINT fk_capacity_booking_service
  FOREIGN KEY (booking_id, vendor_service_id)
  REFERENCES bookings(id, vendor_service_id) ON DELETE RESTRICT;

ALTER TABLE capacity_reservations
  ADD CONSTRAINT fk_capacity_package_service
  FOREIGN KEY (service_package_id, vendor_service_id)
  REFERENCES service_packages(id, vendor_service_id) ON DELETE RESTRICT;

ALTER TABLE capacity_reservations
  ADD CONSTRAINT fk_capacity_booking_package
  FOREIGN KEY (booking_id, service_package_id)
  REFERENCES booking_items(booking_id, service_package_id) ON DELETE RESTRICT;

ALTER TABLE reschedules
  ADD CONSTRAINT fk_reschedule_old_capacity_booking
  FOREIGN KEY (old_capacity_reservation_id, booking_id)
  REFERENCES capacity_reservations(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE reschedules
  ADD CONSTRAINT fk_reschedule_new_capacity_booking
  FOREIGN KEY (new_capacity_reservation_id, booking_id)
  REFERENCES capacity_reservations(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE booking_schedule_history
  ADD CONSTRAINT fk_schedule_history_reschedule_booking
  FOREIGN KEY (reschedule_id, booking_id)
  REFERENCES reschedules(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE ledger_entries
  ADD CONSTRAINT fk_ledger_booking_vendor
  FOREIGN KEY (booking_id, vendor_id)
  REFERENCES bookings(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE settlement_items
  ADD CONSTRAINT fk_settlement_booking_vendor
  FOREIGN KEY (booking_id, vendor_id)
  REFERENCES bookings(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE payouts
  ADD CONSTRAINT fk_payout_account_same_vendor
  FOREIGN KEY (payout_account_id, vendor_id)
  REFERENCES vendor_payout_accounts(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE booking_chat_read_states
  ADD CONSTRAINT fk_chat_read_message_same_booking
  FOREIGN KEY (last_read_message_id, booking_id)
  REFERENCES booking_chat_messages(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE support_cases
  ADD CONSTRAINT fk_support_case_pet_same_booking
  FOREIGN KEY (booking_id, pet_id)
  REFERENCES booking_items(booking_id, pet_id) ON DELETE RESTRICT;

-- MediaObject cross-domain links.
ALTER TABLE vendor_verification_documents
  ADD CONSTRAINT fk_vendor_verification_media
  FOREIGN KEY (media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE pets
  ADD CONSTRAINT fk_pet_photo_media
  FOREIGN KEY (photo_media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE booking_chat_messages
  ADD CONSTRAINT fk_chat_attachment_media
  FOREIGN KEY (attachment_media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE booking_milestones
  ADD CONSTRAINT fk_milestone_media
  FOREIGN KEY (media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE case_evidence
  ADD CONSTRAINT fk_case_evidence_media
  FOREIGN KEY (media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

COMMIT;

-- ===========================================================================
-- 018_partial_indexes.sql
-- ===========================================================================
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

-- ===========================================================================
-- 019_postgis_indexes.sql
-- ===========================================================================
-- PawPals PDB-04: PostGIS spatial indexes.
BEGIN;

CREATE INDEX idx_customer_addresses_location_gist
  ON customer_addresses USING gist(location);

CREATE INDEX idx_vendor_locations_location_gist
  ON vendor_locations USING gist(location);

COMMIT;

-- ===========================================================================
-- 020_query_indexes.sql
-- ===========================================================================
-- PawPals PDB-10: query-path indexes. Unique constraints already supply their own indexes.
BEGIN;

CREATE INDEX idx_accounts_status ON accounts(status);
CREATE INDEX idx_otp_account_purpose_status ON otp_challenges(account_id, purpose, status);
CREATE INDEX idx_otp_expires_at ON otp_challenges(expires_at);
CREATE INDEX idx_otp_delivery_challenge_created ON otp_delivery_attempts(otp_challenge_id, created_at);
CREATE INDEX idx_otp_delivery_status ON otp_delivery_attempts(status);
CREATE INDEX idx_auth_session_account_status ON auth_sessions(account_id, status);
CREATE INDEX idx_auth_session_expires ON auth_sessions(expires_at);
CREATE INDEX idx_account_role_status ON account_role_assignments(account_id, status);

CREATE INDEX idx_vendor_application_vendor_status ON vendor_applications(vendor_id, status);
CREATE INDEX idx_vendor_application_history ON vendor_application_status_history(vendor_application_id, created_at);
CREATE INDEX idx_vendor_docs_application_type ON vendor_verification_documents(vendor_application_id, document_type);
CREATE INDEX idx_vendor_docs_application_status ON vendor_verification_documents(vendor_application_id, status);

CREATE INDEX idx_customer_addresses_account ON customer_addresses(account_id);
CREATE INDEX idx_vendor_locations_vendor ON vendor_locations(vendor_id);
CREATE INDEX idx_vendor_locations_type ON vendor_locations(location_type);
CREATE INDEX idx_pets_owner ON pets(owner_account_id);

CREATE INDEX idx_vendor_services_vendor ON vendor_services(vendor_id);
CREATE INDEX idx_vendor_services_status ON vendor_services(status);
CREATE INDEX idx_vendor_services_delivery_mode ON vendor_services(delivery_mode);
CREATE INDEX idx_service_packages_service ON service_packages(vendor_service_id);
CREATE INDEX idx_service_availability_service_time ON service_availability_windows(vendor_service_id, starts_at, ends_at);
CREATE INDEX idx_service_override_service_time ON service_capacity_overrides(vendor_service_id, starts_at, ends_at);

CREATE INDEX idx_bookings_customer ON bookings(customer_account_id);
CREATE INDEX idx_bookings_vendor ON bookings(vendor_id);
CREATE INDEX idx_bookings_vendor_service ON bookings(vendor_service_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_schedule ON bookings(scheduled_start_at);
CREATE INDEX idx_bookings_vendor_status_start ON bookings(vendor_id, status, scheduled_start_at);
CREATE INDEX idx_booking_status_history ON booking_status_history(booking_id, created_at);

CREATE INDEX idx_capacity_service_status ON capacity_reservations(vendor_service_id, status);
CREATE INDEX idx_capacity_service_time ON capacity_reservations(vendor_service_id, starts_at, occupied_ends_at);
CREATE INDEX idx_capacity_expires ON capacity_reservations(expires_at);
CREATE INDEX idx_capacity_booking ON capacity_reservations(booking_id);

CREATE INDEX idx_refunds_payment_status ON refunds(payment_id, status);
CREATE INDEX idx_cancellation_attribution_history ON cancellation_attribution_events(booking_cancellation_id, created_at);
CREATE INDEX idx_reschedules_booking ON reschedules(booking_id);
CREATE INDEX idx_reschedules_booking_mode_status ON reschedules(booking_id, mode, status);

CREATE INDEX idx_ledger_vendor ON ledger_entries(vendor_id);
CREATE INDEX idx_ledger_booking ON ledger_entries(booking_id);
CREATE INDEX idx_settlement_vendor_status ON settlement_items(vendor_id, status);
CREATE INDEX idx_settlement_available ON settlement_items(vendor_id, available_at) WHERE status = 'AVAILABLE';
CREATE INDEX idx_settlement_history ON settlement_status_history(settlement_item_id, created_at);
CREATE INDEX idx_payout_account_vendor ON vendor_payout_accounts(vendor_id);
CREATE INDEX idx_payout_vendor_status ON payouts(vendor_id, status);
CREATE INDEX idx_payout_item_payout ON payout_items(payout_id);
CREATE INDEX idx_payout_item_settlement ON payout_items(settlement_item_id);
CREATE INDEX idx_payout_history ON payout_status_history(payout_id, created_at);

CREATE INDEX idx_chat_booking_created ON booking_chat_messages(booking_id, created_at);
CREATE INDEX idx_milestone_booking_occurred ON booking_milestones(booking_id, occurred_at);

CREATE INDEX idx_case_booking ON support_cases(booking_id);
CREATE INDEX idx_case_status ON support_cases(status);
CREATE INDEX idx_case_type ON support_cases(case_type);
CREATE INDEX idx_case_assigned_admin ON support_cases(assigned_admin_account_id);
CREATE INDEX idx_case_evidence_case ON case_evidence(case_id);
CREATE INDEX idx_case_history ON case_status_history(case_id, created_at);
CREATE INDEX idx_audit_actor ON audit_logs(actor_account_id);
CREATE INDEX idx_audit_target ON audit_logs(target_type, target_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at);
CREATE INDEX idx_sensitive_access_actor ON sensitive_access_logs(actor_account_id);
CREATE INDEX idx_sensitive_access_class ON sensitive_access_logs(data_class);
CREATE INDEX idx_sensitive_access_target ON sensitive_access_logs(target_type, target_id);
CREATE INDEX idx_sensitive_access_created ON sensitive_access_logs(created_at);

CREATE INDEX idx_outbox_pending ON outbox_events(available_at) WHERE status = 'PENDING';
CREATE INDEX idx_outbox_aggregate ON outbox_events(aggregate_type, aggregate_id);

COMMIT;

-- ===========================================================================
-- 021_functions_triggers.sql
-- ===========================================================================
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

-- ===========================================================================
-- 022_seed_rbac.sql
-- ===========================================================================
-- PawPals PDB-11: minimal RBAC seed aligned to agreed Admin bundles.
-- Permission codes are deliberately limited to current MVP domains.
BEGIN;

INSERT INTO roles (code, name, description) VALUES
  ('SUPER_ADMIN','Super Admin','Critical administration and complete permission bundle.'),
  ('OPERATIONS_ADMIN','Operations Admin','Vendor verification and operational booking administration.'),
  ('FINANCE_ADMIN','Finance Admin','Payment, refund, ledger, settlement and payout operations.'),
  ('TRUST_SAFETY_ADMIN','Trust & Safety Admin','Incident, dispute, report and restricted evidence handling.')
ON CONFLICT (code) DO NOTHING;

INSERT INTO permissions (code,module,name,description) VALUES
  ('admin.rbac.manage','admin','Manage RBAC','Manage admin role and permission assignments.'),
  ('audit.view','admin','View Audit','View system/admin audit records.'),
  ('operations.vendor_application.review','operations','Review Vendor Application','Review vendor onboarding applications and verification documents.'),
  ('operations.vendor.suspend','operations','Suspend Vendor','Apply operational vendor suspension.'),
  ('operations.booking.view','operations','View Booking','View booking data required for operations.'),
  ('finance.payment.view','finance','View Payments','View payment and provider event data.'),
  ('finance.refund.manage','finance','Manage Refunds','Create/process/reconcile refunds.'),
  ('finance.ledger.view','finance','View Ledger','View append-only ledger and settlements.'),
  ('finance.payout.manage','finance','Manage Payouts','Queue/process/reconcile vendor payouts.'),
  ('trust_safety.case.manage','trust_safety','Manage Cases','Triage, investigate, resolve and close support cases.'),
  ('trust_safety.sensitive_access','trust_safety','Access Restricted Evidence','Access case-authorized sensitive/restricted evidence.')
ON CONFLICT (code) DO NOTHING;

-- SUPER_ADMIN receives all current permissions.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.code='SUPER_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
  'operations.vendor_application.review','operations.vendor.suspend','operations.booking.view','audit.view'
) WHERE r.code='OPERATIONS_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
  'finance.payment.view','finance.refund.manage','finance.ledger.view','finance.payout.manage','audit.view'
) WHERE r.code='FINANCE_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
  'trust_safety.case.manage','trust_safety.sensitive_access','audit.view'
) WHERE r.code='TRUST_SAFETY_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

COMMIT;

-- ===========================================================================
-- 023_fix_phone_e164.sql
-- ===========================================================================
-- PawPals runtime hotfix: correct E.164 regex escaping.
BEGIN;

ALTER TABLE accounts
  DROP CONSTRAINT IF EXISTS ck_accounts_phone_e164;

ALTER TABLE accounts
  ADD CONSTRAINT ck_accounts_phone_e164
  CHECK (phone_e164 ~ '^[+][1-9][0-9]{7,14}$');

COMMIT;

-- Optional verification:
SELECT
  '+6289990001001' ~ '^[+][1-9][0-9]{7,14}$' AS valid_e164_should_be_true,
  '08123456789'    ~ '^[+][1-9][0-9]{7,14}$' AS local_format_should_be_false;

-- ===========================================================================
-- 024_final_api_cross_review_fixes.sql
-- ===========================================================================
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

-- ===========================================================================
-- 025_capacity_settlement_guard_fixes.sql
-- ===========================================================================
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

-- ===========================================================================
-- 026_outbox_consumptions.sql
-- ===========================================================================
-- Durable downstream acknowledgement. Never equate queue publish with delivery.
BEGIN;
CREATE TABLE outbox_consumptions (
  event_key varchar(180) PRIMARY KEY REFERENCES outbox_events(event_key) ON DELETE RESTRICT,
  processed_at timestamptz NOT NULL DEFAULT now(),
  delivery_target varchar(80) NOT NULL,
  delivery_reference varchar(255)
);
CREATE INDEX ix_outbox_republish ON outbox_events(status,published_at,available_at)
  WHERE status IN ('PENDING','PUBLISHED');
COMMIT;
