-- PawPals PDB-09: Transactional Outbox
BEGIN;

CREATE TABLE outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key varchar(180) NOT NULL UNIQUE,
  aggregate_type varchar(100) NOT NULL,
  aggregate_id uuid NOT NULL,
  event_type varchar(150) NOT NULL,
  payload_json jsonb NOT NULL,
  status outbox_event_status NOT NULL DEFAULT 'PENDING',
  attempt_count integer NOT NULL DEFAULT 0,
  available_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_outbox_attempt_count CHECK (attempt_count >= 0),
  CONSTRAINT ck_outbox_published CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL)
);

COMMIT;
