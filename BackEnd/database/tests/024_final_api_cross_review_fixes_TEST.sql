-- ============================================================================
-- PawPals PDB-024 Behavioral Validation
-- File: 024_final_api_cross_review_fixes_TEST.sql
--
-- Purpose:
--   A) Prove availability uses the full occupied interval (service + buffer).
--   B) Prove a boundary ending exactly at availability end is accepted.
--   C) Prove Rp0 package/booking/payment paths are rejected.
--
-- SAFETY:
--   Everything runs inside one transaction and ends with ROLLBACK.
--   The development database is left clean after a successful test run.
-- ============================================================================

BEGIN;

-- Make the capacity constraint trigger fire immediately for this validation.
SET CONSTRAINTS ct_capacity_deferred_guard IMMEDIATE;

-- --------------------------------------------------------------------------
-- 0. TEST FIXTURES
-- --------------------------------------------------------------------------

-- Active Vendor account.
INSERT INTO accounts (
  id, phone_e164, display_name, status, phone_verified_at
) VALUES (
  '02400000-0000-0000-0000-000000000001',
  '+6289900240001',
  'PDB024 Vendor Test',
  'ACTIVE',
  now()
);

-- Active Customer account.
INSERT INTO accounts (
  id, phone_e164, display_name, status, phone_verified_at
) VALUES (
  '02400000-0000-0000-0000-000000000002',
  '+6289900240002',
  'PDB024 Customer Test',
  'ACTIVE',
  now()
);

INSERT INTO vendors (
  id,
  account_id,
  vendor_type,
  public_display_name,
  status,
  approved_at
) VALUES (
  '02400000-0000-0000-0000-000000000010',
  '02400000-0000-0000-0000-000000000001',
  'INDIVIDUAL',
  'PDB024 Test Vendor',
  'ACTIVE',
  now()
);

INSERT INTO vendor_locations (
  id,
  vendor_id,
  location_type,
  address_line1,
  city,
  province,
  latitude,
  longitude
) VALUES (
  '02400000-0000-0000-0000-000000000020',
  '02400000-0000-0000-0000-000000000010',
  'OPERATIONAL_PRIVATE',
  'PDB024 Test Location',
  'Jakarta',
  'DKI Jakarta',
  -6.200000,
  106.816666
);

-- 60-minute package + 30-minute buffer.
INSERT INTO vendor_services (
  id,
  vendor_id,
  origin_vendor_location_id,
  category_code,
  name,
  delivery_mode,
  service_radius_meters,
  minimum_notice_minutes,
  buffer_after_minutes,
  base_capacity,
  status
) VALUES (
  '02400000-0000-0000-0000-000000000030',
  '02400000-0000-0000-0000-000000000010',
  '02400000-0000-0000-0000-000000000020',
  'PDB024_TEST',
  'PDB024 Test Service',
  'AT_VENDOR',
  NULL,
  0,
  30,
  1,
  'ACTIVE'
);

INSERT INTO service_packages (
  id,
  vendor_service_id,
  name,
  duration_minutes,
  price_amount,
  currency,
  is_active
) VALUES (
  '02400000-0000-0000-0000-000000000040',
  '02400000-0000-0000-0000-000000000030',
  'PDB024 60 Minute Package',
  60,
  100000,
  'IDR',
  true
);

-- Availability ends at 17:00.
INSERT INTO service_availability_windows (
  id,
  vendor_service_id,
  starts_at,
  ends_at
) VALUES (
  '02400000-0000-0000-0000-000000000050',
  '02400000-0000-0000-0000-000000000030',
  '2030-01-15 09:00:00+07',
  '2030-01-15 17:00:00+07'
);

INSERT INTO pets (
  id,
  owner_account_id,
  name,
  species_code
) VALUES (
  '02400000-0000-0000-0000-000000000060',
  '02400000-0000-0000-0000-000000000002',
  'PDB024 Test Pet',
  'DOG'
);

-- --------------------------------------------------------------------------
-- 1. NEGATIVE AVAILABILITY TEST
--
-- Service itself fits:
--   16:00 -> 17:00
-- But the 30-minute buffer does not:
--   occupied interval = 16:00 -> 17:30
--
-- Expected: capacity reservation is REJECTED.
-- --------------------------------------------------------------------------

INSERT INTO bookings (
  id,
  customer_account_id,
  vendor_id,
  vendor_service_id,
  status,
  scheduled_start_at,
  scheduled_end_at,
  occupied_end_at,
  total_amount,
  currency
) VALUES (
  '02400000-0000-0000-0000-000000000101',
  '02400000-0000-0000-0000-000000000002',
  '02400000-0000-0000-0000-000000000010',
  '02400000-0000-0000-0000-000000000030',
  'CREATED',
  '2030-01-15 16:00:00+07',
  '2030-01-15 17:00:00+07',
  '2030-01-15 17:30:00+07',
  100000,
  'IDR'
);

INSERT INTO booking_items (
  id,
  booking_id,
  pet_id,
  service_package_id,
  pet_snapshot_json,
  compatibility_snapshot_json,
  service_name_snapshot,
  package_name_snapshot,
  price_amount_snapshot,
  duration_minutes_snapshot,
  buffer_after_minutes_snapshot,
  minimum_notice_minutes_snapshot
) VALUES (
  '02400000-0000-0000-0000-000000000111',
  '02400000-0000-0000-0000-000000000101',
  '02400000-0000-0000-0000-000000000060',
  '02400000-0000-0000-0000-000000000040',
  '{"test": true}'::jsonb,
  '{"eligible": true}'::jsonb,
  'PDB024 Test Service',
  'PDB024 60 Minute Package',
  100000,
  60,
  30,
  0
);

DO $$
BEGIN
  BEGIN
    INSERT INTO capacity_reservations (
      id,
      booking_id,
      vendor_service_id,
      service_package_id,
      status,
      capacity_units,
      starts_at,
      service_ends_at,
      occupied_ends_at,
      expires_at
    ) VALUES (
      '02400000-0000-0000-0000-000000000121',
      '02400000-0000-0000-0000-000000000101',
      '02400000-0000-0000-0000-000000000030',
      '02400000-0000-0000-0000-000000000040',
      'HELD',
      1,
      '2030-01-15 16:00:00+07',
      '2030-01-15 17:00:00+07',
      '2030-01-15 17:30:00+07',
      '2030-01-15 16:15:00+07'
    );

    RAISE EXCEPTION
      'TEST FAILED: occupied interval ending 17:30 was incorrectly accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%outside vendor availability%' THEN
        RAISE NOTICE
          'PASS TEST 1: 16:00-17:00 service + buffer to 17:30 was rejected';
      ELSE
        RAISE;
      END IF;
  END;
END;
$$;

-- --------------------------------------------------------------------------
-- 2. BOUNDARY TEST
--
-- Service:
--   15:30 -> 16:30
-- Buffer:
--   16:30 -> 17:00
-- Occupied end touches availability end exactly.
--
-- Expected: ACCEPTED because PawPals uses [start,end) semantics.
-- --------------------------------------------------------------------------

INSERT INTO bookings (
  id,
  customer_account_id,
  vendor_id,
  vendor_service_id,
  status,
  scheduled_start_at,
  scheduled_end_at,
  occupied_end_at,
  total_amount,
  currency
) VALUES (
  '02400000-0000-0000-0000-000000000102',
  '02400000-0000-0000-0000-000000000002',
  '02400000-0000-0000-0000-000000000010',
  '02400000-0000-0000-0000-000000000030',
  'CREATED',
  '2030-01-15 15:30:00+07',
  '2030-01-15 16:30:00+07',
  '2030-01-15 17:00:00+07',
  100000,
  'IDR'
);

INSERT INTO booking_items (
  id,
  booking_id,
  pet_id,
  service_package_id,
  pet_snapshot_json,
  compatibility_snapshot_json,
  service_name_snapshot,
  package_name_snapshot,
  price_amount_snapshot,
  duration_minutes_snapshot,
  buffer_after_minutes_snapshot,
  minimum_notice_minutes_snapshot
) VALUES (
  '02400000-0000-0000-0000-000000000112',
  '02400000-0000-0000-0000-000000000102',
  '02400000-0000-0000-0000-000000000060',
  '02400000-0000-0000-0000-000000000040',
  '{"test": true}'::jsonb,
  '{"eligible": true}'::jsonb,
  'PDB024 Test Service',
  'PDB024 60 Minute Package',
  100000,
  60,
  30,
  0
);

INSERT INTO capacity_reservations (
  id,
  booking_id,
  vendor_service_id,
  service_package_id,
  status,
  capacity_units,
  starts_at,
  service_ends_at,
  occupied_ends_at,
  expires_at
) VALUES (
  '02400000-0000-0000-0000-000000000122',
  '02400000-0000-0000-0000-000000000102',
  '02400000-0000-0000-0000-000000000030',
  '02400000-0000-0000-0000-000000000040',
  'HELD',
  1,
  '2030-01-15 15:30:00+07',
  '2030-01-15 16:30:00+07',
  '2030-01-15 17:00:00+07',
  '2030-01-15 15:45:00+07'
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM capacity_reservations
    WHERE id = '02400000-0000-0000-0000-000000000122'
      AND status = 'HELD'
  ) THEN
    RAISE EXCEPTION
      'TEST FAILED: valid boundary reservation was not created';
  END IF;

  RAISE NOTICE
    'PASS TEST 2: occupied interval ending exactly at 17:00 was accepted';
END;
$$;

-- --------------------------------------------------------------------------
-- 3. ZERO-PRICE PACKAGE TEST
-- Expected: ck_service_package_price rejects price_amount = 0.
-- --------------------------------------------------------------------------

DO $$
BEGIN
  BEGIN
    INSERT INTO service_packages (
      id,
      vendor_service_id,
      name,
      duration_minutes,
      price_amount,
      currency,
      is_active
    ) VALUES (
      '02400000-0000-0000-0000-000000000041',
      '02400000-0000-0000-0000-000000000030',
      'INVALID FREE PACKAGE',
      60,
      0,
      'IDR',
      false
    );

    RAISE EXCEPTION
      'TEST FAILED: zero-price package was accepted';
  EXCEPTION
    WHEN check_violation THEN
      IF SQLERRM LIKE '%ck_service_package_price%' THEN
        RAISE NOTICE
          'PASS TEST 3: zero-price ServicePackage rejected';
      ELSE
        RAISE;
      END IF;
  END;
END;
$$;

-- --------------------------------------------------------------------------
-- 4. ZERO BOOKING-AMOUNT TEST
-- Expected: ck_booking_amount rejects total_amount = 0.
-- --------------------------------------------------------------------------

DO $$
BEGIN
  BEGIN
    INSERT INTO bookings (
      id,
      customer_account_id,
      vendor_id,
      vendor_service_id,
      status,
      scheduled_start_at,
      scheduled_end_at,
      occupied_end_at,
      total_amount,
      currency
    ) VALUES (
      '02400000-0000-0000-0000-000000000103',
      '02400000-0000-0000-0000-000000000002',
      '02400000-0000-0000-0000-000000000010',
      '02400000-0000-0000-0000-000000000030',
      'CREATED',
      '2030-01-16 10:00:00+07',
      '2030-01-16 11:00:00+07',
      '2030-01-16 11:30:00+07',
      0,
      'IDR'
    );

    RAISE EXCEPTION
      'TEST FAILED: zero-value Booking was accepted';
  EXCEPTION
    WHEN check_violation THEN
      IF SQLERRM LIKE '%ck_booking_amount%' THEN
        RAISE NOTICE
          'PASS TEST 4: zero-value Booking rejected';
      ELSE
        RAISE;
      END IF;
  END;
END;
$$;

-- --------------------------------------------------------------------------
-- 5. ZERO PAYMENT TEST
--
-- A positive Booking is created, then Payment.amount = 0 is attempted.
-- Either the explicit CHECK or the Booking/Payment amount guard must reject it.
-- --------------------------------------------------------------------------

INSERT INTO bookings (
  id,
  customer_account_id,
  vendor_id,
  vendor_service_id,
  status,
  scheduled_start_at,
  scheduled_end_at,
  occupied_end_at,
  total_amount,
  currency
) VALUES (
  '02400000-0000-0000-0000-000000000104',
  '02400000-0000-0000-0000-000000000002',
  '02400000-0000-0000-0000-000000000010',
  '02400000-0000-0000-0000-000000000030',
  'CREATED',
  '2030-01-16 12:00:00+07',
  '2030-01-16 13:00:00+07',
  '2030-01-16 13:30:00+07',
  100000,
  'IDR'
);

DO $$
BEGIN
  BEGIN
    INSERT INTO payments (
      id,
      booking_id,
      provider,
      amount,
      currency,
      status,
      expires_at
    ) VALUES (
      '02400000-0000-0000-0000-000000000130',
      '02400000-0000-0000-0000-000000000104',
      'MIDTRANS',
      0,
      'IDR',
      'PENDING',
      '2030-01-16 12:15:00+07'
    );

    RAISE EXCEPTION
      'TEST FAILED: zero-value Payment was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%ck_payment_amount%'
         OR SQLERRM LIKE '%Payment amount/currency must equal Booking%' THEN
        RAISE NOTICE
          'PASS TEST 5: zero-value Payment rejected';
      ELSE
        RAISE;
      END IF;
  END;
END;
$$;

-- --------------------------------------------------------------------------
-- 6. STRUCTURAL ASSERTION: all four amount constraints are now > 0.
-- --------------------------------------------------------------------------

SELECT
  c.conrelid::regclass AS table_name,
  c.conname AS constraint_name,
  pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.conname IN (
  'ck_service_package_price',
  'ck_booking_item_price',
  'ck_booking_amount',
  'ck_payment_amount'
)
ORDER BY c.conrelid::regclass::text;

-- Clean up every fixture created by this validation.
ROLLBACK;

-- Expected Messages:
--   PASS TEST 1 ...
--   PASS TEST 2 ...
--   PASS TEST 3 ...
--   PASS TEST 4 ...
--   PASS TEST 5 ...
--   ROLLBACK
-- ============================================================================
