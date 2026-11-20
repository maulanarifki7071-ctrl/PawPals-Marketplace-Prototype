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
