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
