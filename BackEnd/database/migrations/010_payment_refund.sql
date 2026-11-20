-- PawPals PDB-02/03/06: ERD-08 Payment, Provider Event, Refund
BEGIN;

CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  provider varchar(50) NOT NULL,
  provider_transaction_id varchar(255) UNIQUE,
  provider_order_reference varchar(255) UNIQUE,
  amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  status payment_status NOT NULL DEFAULT 'PENDING',
  expires_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  failure_code varchar(100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_payment_amount CHECK (amount >= 0),
  CONSTRAINT ck_payment_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_payment_lifecycle CHECK (
    (status <> 'PENDING' OR expires_at IS NOT NULL) AND
    (status <> 'PAID' OR paid_at IS NOT NULL) AND
    (status <> 'FAILED' OR failed_at IS NOT NULL) AND
    (status <> 'EXPIRED' OR expires_at IS NOT NULL)
  )
);

CREATE TABLE payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  provider varchar(50) NOT NULL,
  provider_event_id varchar(255) NOT NULL,
  event_type varchar(100),
  provider_status varchar(100),
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  CONSTRAINT uq_payment_event_provider UNIQUE (provider, provider_event_id)
);

CREATE TABLE refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  status refund_status NOT NULL DEFAULT 'REQUESTED',
  amount bigint NOT NULL,
  currency char(3) NOT NULL DEFAULT 'IDR',
  reason_code varchar(100),
  reason_text text,
  initiator_type refund_initiator_type NOT NULL,
  initiated_by_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  provider_ref varchar(255),
  requested_at timestamptz NOT NULL DEFAULT now(),
  processing_at timestamptz,
  succeeded_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_refund_amount CHECK (amount > 0),
  CONSTRAINT ck_refund_currency CHECK (currency = 'IDR'),
  CONSTRAINT ck_refund_initiator CHECK (
    (initiator_type = 'SYSTEM' AND initiated_by_account_id IS NULL) OR
    (initiator_type <> 'SYSTEM' AND initiated_by_account_id IS NOT NULL)
  ),
  CONSTRAINT ck_refund_lifecycle CHECK (
    (status <> 'PROCESSING' OR processing_at IS NOT NULL) AND
    (status <> 'SUCCEEDED' OR succeeded_at IS NOT NULL) AND
    (status <> 'FAILED' OR failed_at IS NOT NULL)
  )
);

CREATE TABLE refund_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_id uuid NOT NULL REFERENCES refunds(id) ON DELETE RESTRICT,
  attempt_no integer NOT NULL,
  provider_request_ref varchar(255),
  is_ambiguous boolean NOT NULL DEFAULT false,
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT ck_refund_attempt_no CHECK (attempt_no > 0),
  CONSTRAINT uq_refund_attempt UNIQUE (refund_id, attempt_no)
);

COMMIT;
