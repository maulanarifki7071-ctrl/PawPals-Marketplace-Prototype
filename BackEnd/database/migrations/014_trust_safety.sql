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
