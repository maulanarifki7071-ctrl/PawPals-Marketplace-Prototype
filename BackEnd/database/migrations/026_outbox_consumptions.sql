-- Durable downstream acknowledgement. Never equate queue publish with delivery.
BEGIN;
CREATE TABLE outbox_consumptions (
  event_key varchar(180) PRIMARY KEY REFERENCES outbox_events(event_key) ON DELETE RESTRICT,
  processed_at timestamptz NOT NULL DEFAULT now(),
  delivery_target varchar(80) NOT NULL,
  delivery_reference varchar(255)
);
CREATE INDEX ix_outbox_republish ON outbox_events(status,published_at,available_at)
  WHERE status IN ('PENDING','PUBLISHED');
COMMIT;
