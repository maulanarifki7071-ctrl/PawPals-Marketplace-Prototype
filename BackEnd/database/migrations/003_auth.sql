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
