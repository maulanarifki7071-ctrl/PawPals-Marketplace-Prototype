-- PawPals runtime hotfix: correct E.164 regex escaping.
BEGIN;

ALTER TABLE accounts
  DROP CONSTRAINT IF EXISTS ck_accounts_phone_e164;

ALTER TABLE accounts
  ADD CONSTRAINT ck_accounts_phone_e164
  CHECK (phone_e164 ~ '^[+][1-9][0-9]{7,14}$');

COMMIT;

-- Optional verification:
SELECT
  '+6289990001001' ~ '^[+][1-9][0-9]{7,14}$' AS valid_e164_should_be_true,
  '08123456789'    ~ '^[+][1-9][0-9]{7,14}$' AS local_format_should_be_false;
