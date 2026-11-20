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
