-- PawPals PDB-04: PostGIS spatial indexes.
BEGIN;

CREATE INDEX idx_customer_addresses_location_gist
  ON customer_addresses USING gist(location);

CREATE INDEX idx_vendor_locations_location_gist
  ON vendor_locations USING gist(location);

COMMIT;
