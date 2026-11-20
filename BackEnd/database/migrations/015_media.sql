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
