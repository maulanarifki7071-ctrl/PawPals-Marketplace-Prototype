-- PawPals PDB-02/03: ERD-11 Booking Chat, Milestone, Review
-- Media FKs are added in migration 017.
BEGIN;

CREATE TABLE booking_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  sender_account_id uuid REFERENCES accounts(id) ON DELETE RESTRICT,
  message_type chat_message_type NOT NULL,
  body_text text,
  attachment_media_object_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_chat_message_payload CHECK (
    (message_type = 'TEXT' AND body_text IS NOT NULL AND sender_account_id IS NOT NULL) OR
    (message_type = 'IMAGE' AND attachment_media_object_id IS NOT NULL AND sender_account_id IS NOT NULL) OR
    (message_type = 'SYSTEM' AND sender_account_id IS NULL)
  )
);

CREATE TABLE booking_chat_read_states (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  last_read_message_id uuid REFERENCES booking_chat_messages(id) ON DELETE RESTRICT,
  last_read_at timestamptz,
  CONSTRAINT uq_booking_chat_read_state UNIQUE (booking_id, account_id)
);

CREATE TABLE booking_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  created_by_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  milestone_type varchar(80) NOT NULL,
  description text,
  media_object_id uuid,
  occurred_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE RESTRICT,
  reviewer_account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  rating smallint NOT NULL,
  comment text,
  is_visible boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_review_rating CHECK (rating BETWEEN 1 AND 5)
);

COMMIT;
