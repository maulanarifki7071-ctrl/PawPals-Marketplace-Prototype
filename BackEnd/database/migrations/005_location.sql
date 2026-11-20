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
