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
