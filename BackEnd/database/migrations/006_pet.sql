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
