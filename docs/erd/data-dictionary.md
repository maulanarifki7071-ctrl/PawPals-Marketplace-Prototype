# PawPals — Data dictionary (baseline Premium UI/UX)

- 58 tabel; 109 deklarasi FK berdasarkan inventaris SQL dari paket 12 November.
- Seluruh 27 file migration dibandingkan byte-for-byte antara ZIP Premium dan ZIP sumber ERD sebelumnya; identik. ERD dan metadata kolom dipertahankan tanpa perubahan struktural. Ini bukan introspeksi database pengguna.
- Sumber: BackEnd/database/migrations/001–026; 027 di ZIP hanya query pengecekan hotfix. Lihat panduan database.

Relasi FK child -> parent berasal dari SQL migration.

## 01 Identitas dan akses
### accounts
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| phone_e164 | varchar(20) |  | NO |
| email | varchar(255) |  | YES |
| display_name | varchar(150) |  | NO |
| status | account_status |  | NO |
| phone_verified_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
### account_credentials
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| password_hash | text |  | NO |
| password_algorithm | varchar(50) |  | YES |
| password_updated_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `account_id` -> `accounts(id)`
### otp_challenges
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| purpose | otp_purpose |  | NO |
| status | otp_status |  | NO |
| attempt_count | integer |  | NO |
| max_attempts | integer |  | NO |
| expires_at | timestamptz |  | NO |
| verified_at | timestamptz |  | YES |
| consumed_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `account_id` -> `accounts(id)`
### otp_delivery_attempts
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| otp_challenge_id | uuid | FK | NO |
| channel | otp_channel |  | NO |
| provider | varchar(50) |  | YES |
| provider_reference | varchar(255) |  | YES |
| status | otp_delivery_status |  | NO |
| sent_at | timestamptz |  | YES |
| delivered_at | timestamptz |  | YES |
| failed_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `otp_challenge_id` -> `otp_challenges(id)`
### auth_sessions
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| session_token_hash | text |  | NO |
| status | session_status |  | NO |
| ip_address | varchar(64) |  | YES |
| user_agent | text |  | YES |
| last_seen_at | timestamptz |  | YES |
| expires_at | timestamptz |  | NO |
| revoked_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `account_id` -> `accounts(id)`
### roles
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| code | varchar(80) |  | NO |
| name | varchar(120) |  | NO |
| description | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
### permissions
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| code | varchar(120) |  | NO |
| module | varchar(80) |  | NO |
| name | varchar(150) |  | NO |
| description | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
### role_permissions
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| role_id | uuid | FK | NO |
| permission_id | uuid | FK | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `role_id` -> `roles(id)`
- `permission_id` -> `permissions(id)`
### account_role_assignments
Source: `003_auth.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| role_id | uuid | FK | NO |
| assigned_by_account_id | uuid | FK | YES |
| status | role_assignment_status |  | NO |
| assigned_at | timestamptz |  | NO |
| revoked_at | timestamptz |  | YES |

Foreign keys:
- `account_id` -> `accounts(id)`
- `role_id` -> `roles(id)`
- `assigned_by_account_id` -> `accounts(id)`

## 02 Vendor dan verifikasi
### vendors
Source: `004_vendor.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| vendor_type | vendor_type |  | NO |
| public_display_name | varchar(180) |  | NO |
| business_name | varchar(180) |  | YES |
| status | vendor_status |  | NO |
| approved_at | timestamptz |  | YES |
| suspended_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `account_id` -> `accounts(id)`
### vendor_applications
Source: `004_vendor.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | NO |
| status | vendor_application_status |  | NO |
| declared_identity_name | varchar(180) |  | YES |
| business_name | varchar(180) |  | YES |
| representative_name | varchar(180) |  | YES |
| reviewed_by_account_id | uuid | FK | YES |
| submitted_at | timestamptz |  | YES |
| review_started_at | timestamptz |  | YES |
| decided_at | timestamptz |  | YES |
| decision_reason | text |  | YES |
| terms_version | varchar(80) |  | YES |
| terms_accepted_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`
- `reviewed_by_account_id` -> `accounts(id)`
### vendor_application_status_history
Source: `004_vendor.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_application_id | uuid | FK | NO |
| from_status | vendor_application_status |  | YES |
| to_status | vendor_application_status |  | NO |
| changed_by_account_id | uuid | FK | YES |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `vendor_application_id` -> `vendor_applications(id)`
- `changed_by_account_id` -> `accounts(id)`
### vendor_verification_documents
Source: `004_vendor.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_application_id | uuid | FK | NO |
| document_type | verification_document_type |  | NO |
| status | verification_document_status |  | NO |
| media_object_id | uuid | FK | NO |
| reviewed_by_account_id | uuid | FK | YES |
| review_reason | text |  | YES |
| verified_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_application_id` -> `vendor_applications(id)`
- `reviewed_by_account_id` -> `accounts(id)`
- `media_object_id` -> `media_objects(id)`
### vendor_locations
Source: `005_location.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | NO |
| location_type | vendor_location_type |  | NO |
| address_line1 | text |  | YES |
| city | varchar(120) |  | YES |
| province | varchar(120) |  | YES |
| latitude | numeric(9,6) |  | NO |
| longitude | numeric(9,6) |  | NO |
| location | geography(Point,4326) |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`

## 03 Customer, hewan, layanan
### customer_profiles
Source: `005_location.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `account_id` -> `accounts(id)`
### customer_addresses
Source: `005_location.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| account_id | uuid | FK | NO |
| label | varchar(80) |  | YES |
| address_line1 | text |  | NO |
| address_line2 | text |  | YES |
| city | varchar(120) |  | YES |
| province | varchar(120) |  | YES |
| postal_code | varchar(20) |  | YES |
| latitude | numeric(9,6) |  | NO |
| longitude | numeric(9,6) |  | NO |
| location | geography(Point,4326) |  | YES |
| geocoding_provider | varchar(50) |  | YES |
| provider_reference | varchar(255) |  | YES |
| is_default | boolean |  | NO |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `account_id` -> `accounts(id)`
### pets
Source: `006_pet.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| owner_account_id | uuid | FK | NO |
| name | varchar(120) |  | NO |
| species_code | varchar(50) |  | NO |
| breed | varchar(120) |  | YES |
| birth_date | date |  | YES |
| sex | varchar(30) |  | YES |
| weight_kg | numeric(6,2) |  | YES |
| size_code | varchar(50) |  | YES |
| photo_media_object_id | uuid | FK | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `owner_account_id` -> `accounts(id)`
- `photo_media_object_id` -> `media_objects(id)`
### pet_safety_profiles
Source: `006_pet.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| pet_id | uuid | FK | NO |
| is_reactive | boolean |  | YES |
| aggression_history | boolean |  | YES |
| escape_risk | boolean |  | YES |
| leash_behavior_notes | text |  | YES |
| handling_sensitivity_notes | text |  | YES |
| allergy_notes | text |  | YES |
| known_health_history | text |  | YES |
| medication_notes | text |  | YES |
| routine_notes | text |  | YES |
| emergency_contact_name | varchar(150) |  | YES |
| emergency_contact_phone | varchar(30) |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `pet_id` -> `pets(id)`
### vendor_services
Source: `007_service.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | NO |
| origin_vendor_location_id | uuid | FK | YES |
| category_code | varchar(80) |  | NO |
| name | varchar(180) |  | NO |
| description | text |  | YES |
| delivery_mode | service_delivery_mode |  | NO |
| service_radius_meters | integer |  | YES |
| minimum_notice_minutes | integer |  | NO |
| buffer_after_minutes | integer |  | NO |
| base_capacity | integer |  | NO |
| status | service_status |  | NO |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`
- `origin_vendor_location_id,vendor_id` -> `vendor_locations(id,vendor_id)`
### service_packages
Source: `007_service.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_service_id | uuid | FK | NO |
| name | varchar(150) |  | NO |
| description | text |  | YES |
| duration_minutes | integer |  | NO |
| price_amount | bigint |  | NO |
| currency | char(3) |  | NO |
| is_active | boolean |  | NO |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_service_id` -> `vendor_services(id)`
### vendor_service_pet_rules
Source: `007_service.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_service_id | uuid | FK | NO |
| accepted_species_json | jsonb |  | NO |
| accepted_size_codes_json | jsonb |  | YES |
| accepts_reactive | boolean |  | NO |
| accepts_aggressive_history | boolean |  | NO |
| deterministic_restrictions_json | jsonb |  | YES |
| context_notes | text |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_service_id` -> `vendor_services(id)`
### service_availability_windows
Source: `007_service.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_service_id | uuid | FK | NO |
| starts_at | timestamptz |  | NO |
| ends_at | timestamptz |  | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `vendor_service_id` -> `vendor_services(id)`
### service_capacity_overrides
Source: `007_service.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_service_id | uuid | FK | NO |
| starts_at | timestamptz |  | NO |
| ends_at | timestamptz |  | NO |
| capacity | integer |  | NO |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `vendor_service_id` -> `vendor_services(id)`

## 04 Booking, cancel, reschedule
### bookings
Source: `008_booking.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| customer_account_id | uuid | FK | NO |
| vendor_id | uuid | FK | NO |
| vendor_service_id | uuid | FK | NO |
| status | booking_status |  | NO |
| scheduled_start_at | timestamptz |  | NO |
| scheduled_end_at | timestamptz |  | NO |
| occupied_end_at | timestamptz |  | NO |
| total_amount | bigint |  | NO |
| currency | char(3) |  | NO |
| confirmed_at | timestamptz |  | YES |
| service_started_at | timestamptz |  | YES |
| completed_at | timestamptz |  | YES |
| cancelled_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `customer_account_id` -> `accounts(id)`
- `vendor_id` -> `vendors(id)`
- `vendor_service_id` -> `vendor_services(id)`
- `vendor_service_id,vendor_id` -> `vendor_services(id,vendor_id)`
### booking_items
Source: `008_booking.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| pet_id | uuid | FK | NO |
| service_package_id | uuid | FK | NO |
| pet_snapshot_json | jsonb |  | NO |
| compatibility_snapshot_json | jsonb |  | NO |
| service_name_snapshot | varchar(180) |  | YES |
| package_name_snapshot | varchar(150) |  | YES |
| price_amount_snapshot | bigint |  | NO |
| duration_minutes_snapshot | integer |  | NO |
| buffer_after_minutes_snapshot | integer |  | NO |
| minimum_notice_minutes_snapshot | integer |  | NO |
| booking_specific_notes | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `pet_id` -> `pets(id)`
- `service_package_id` -> `service_packages(id)`
### booking_location_snapshots
Source: `008_booking.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| delivery_mode_snapshot | booking_delivery_mode_snapshot |  | NO |
| address_snapshot | text |  | NO |
| latitude | numeric(9,6) |  | NO |
| longitude | numeric(9,6) |  | NO |
| service_radius_meters_snapshot | integer |  | YES |
| distance_meters_snapshot | integer |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
### booking_policy_snapshots
Source: `008_booking.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| policy_version | varchar(80) |  | NO |
| commission_rate_bps | integer |  | NO |
| cancellation_tiers_snapshot_json | jsonb |  | NO |
| payment_hold_minutes | integer |  | NO |
| settlement_hold_minutes | integer |  | NO |
| cancellation_claim_window_minutes | integer |  | NO |
| customer_self_reschedule_min_notice_minutes | integer |  | NO |
| customer_self_reschedule_max_applied_count | integer |  | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
### booking_status_history
Source: `008_booking.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| from_status | booking_status |  | YES |
| to_status | booking_status |  | NO |
| actor_type | booking_transition_actor_type |  | NO |
| actor_account_id | uuid | FK | YES |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `actor_account_id` -> `accounts(id)`
### capacity_reservations
Source: `009_capacity.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| vendor_service_id | uuid | FK | NO |
| service_package_id | uuid | FK | NO |
| status | capacity_reservation_status |  | NO |
| capacity_units | integer |  | NO |
| starts_at | timestamptz |  | NO |
| service_ends_at | timestamptz |  | NO |
| occupied_ends_at | timestamptz |  | NO |
| expires_at | timestamptz |  | YES |
| committed_at | timestamptz |  | YES |
| released_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `vendor_service_id` -> `vendor_services(id)`
- `service_package_id` -> `service_packages(id)`
- `booking_id,vendor_service_id` -> `bookings(id,vendor_service_id)`
- `service_package_id,vendor_service_id` -> `service_packages(id,vendor_service_id)`
- `booking_id,service_package_id` -> `booking_items(booking_id,service_package_id)`
### booking_cancellations
Source: `011_cancellation_reschedule.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| cancelled_by | cancellation_actor |  | NO |
| fault_party | cancellation_fault_party |  | NO |
| reason_code | varchar(100) |  | YES |
| reason_text | text |  | YES |
| calculated_refund_amount | bigint |  | NO |
| retained_settlement_base_amount | bigint |  | NO |
| policy_evaluation_snapshot_json | jsonb |  | NO |
| fault_finalized_at | timestamptz |  | YES |
| claim_window_ends_at | timestamptz |  | NO |
| cancelled_at | timestamptz |  | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
### cancellation_attribution_events
Source: `011_cancellation_reschedule.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_cancellation_id | uuid | FK | NO |
| from_fault_party | cancellation_fault_party |  | YES |
| to_fault_party | cancellation_fault_party |  | NO |
| changed_by_account_id | uuid | FK | YES |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_cancellation_id` -> `booking_cancellations(id)`
- `changed_by_account_id` -> `accounts(id)`
### vendor_cancellation_claims
Source: `011_cancellation_reschedule.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_cancellation_id | uuid | FK | NO |
| status | vendor_cancellation_claim_status |  | NO |
| customer_claim_text | text |  | YES |
| vendor_response_text | text |  | YES |
| vendor_response_by_account_id | uuid | FK | YES |
| opened_at | timestamptz |  | NO |
| vendor_responded_at | timestamptz |  | YES |
| resolved_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_cancellation_id` -> `booking_cancellations(id)`
- `vendor_response_by_account_id` -> `accounts(id)`
### reschedules
Source: `011_cancellation_reschedule.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| mode | reschedule_mode |  | NO |
| status | reschedule_status |  | NO |
| initiated_by_account_id | uuid | FK | NO |
| decided_by_account_id | uuid | FK | YES |
| old_start_at | timestamptz |  | NO |
| old_end_at | timestamptz |  | NO |
| old_occupied_end_at | timestamptz |  | NO |
| proposed_start_at | timestamptz |  | NO |
| proposed_end_at | timestamptz |  | NO |
| proposed_occupied_end_at | timestamptz |  | NO |
| old_capacity_reservation_id | uuid | FK | YES |
| new_capacity_reservation_id | uuid | FK | YES |
| requested_at | timestamptz |  | NO |
| decided_at | timestamptz |  | YES |
| applied_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `initiated_by_account_id` -> `accounts(id)`
- `decided_by_account_id` -> `accounts(id)`
- `old_capacity_reservation_id,booking_id` -> `capacity_reservations(id,booking_id)`
- `new_capacity_reservation_id,booking_id` -> `capacity_reservations(id,booking_id)`
### booking_schedule_history
Source: `011_cancellation_reschedule.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| reschedule_id | uuid | FK | YES |
| revision_no | integer |  | NO |
| scheduled_start_at | timestamptz |  | NO |
| scheduled_end_at | timestamptz |  | NO |
| occupied_end_at | timestamptz |  | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `reschedule_id,booking_id` -> `reschedules(id,booking_id)`

## 05 Payment, refund, finance
### payments
Source: `010_payment_refund.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| provider | varchar(50) |  | NO |
| provider_transaction_id | varchar(255) |  | YES |
| provider_order_reference | varchar(255) |  | YES |
| amount | bigint |  | NO |
| currency | char(3) |  | NO |
| status | payment_status |  | NO |
| expires_at | timestamptz |  | YES |
| paid_at | timestamptz |  | YES |
| failed_at | timestamptz |  | YES |
| failure_code | varchar(100) |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
### payment_events
Source: `010_payment_refund.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| payment_id | uuid | FK | NO |
| provider | varchar(50) |  | NO |
| provider_event_id | varchar(255) |  | NO |
| event_type | varchar(100) |  | YES |
| provider_status | varchar(100) |  | YES |
| received_at | timestamptz |  | NO |
| processed_at | timestamptz |  | YES |

Foreign keys:
- `payment_id` -> `payments(id)`
### refunds
Source: `010_payment_refund.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| payment_id | uuid | FK | NO |
| status | refund_status |  | NO |
| amount | bigint |  | NO |
| currency | char(3) |  | NO |
| reason_code | varchar(100) |  | YES |
| reason_text | text |  | YES |
| initiator_type | refund_initiator_type |  | NO |
| initiated_by_account_id | uuid | FK | YES |
| provider_ref | varchar(255) |  | YES |
| requested_at | timestamptz |  | NO |
| processing_at | timestamptz |  | YES |
| succeeded_at | timestamptz |  | YES |
| failed_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `payment_id` -> `payments(id)`
- `initiated_by_account_id` -> `accounts(id)`
### refund_attempts
Source: `010_payment_refund.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| refund_id | uuid | FK | NO |
| attempt_no | integer |  | NO |
| provider_request_ref | varchar(255) |  | YES |
| is_ambiguous | boolean |  | NO |
| requested_at | timestamptz |  | NO |
| completed_at | timestamptz |  | YES |

Foreign keys:
- `refund_id` -> `refunds(id)`
### ledger_entries
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | YES |
| booking_id | uuid | FK | YES |
| payment_id | uuid | FK | YES |
| refund_id | uuid | FK | YES |
| posting_type | ledger_posting_type |  | NO |
| canonical_event_type | varchar(80) |  | NO |
| canonical_event_id | varchar(150) |  | NO |
| amount_signed | bigint |  | NO |
| currency | char(3) |  | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`
- `booking_id` -> `bookings(id)`
- `payment_id` -> `payments(id)`
- `refund_id` -> `refunds(id)`
- `booking_id,vendor_id` -> `bookings(id,vendor_id)`
### settlement_items
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | NO |
| booking_id | uuid | FK | NO |
| origin_ledger_entry_id | uuid | FK | NO |
| source_type | settlement_source_type |  | NO |
| status | settlement_status |  | NO |
| amount_signed | bigint |  | NO |
| currency | char(3) |  | NO |
| hold_until | timestamptz |  | YES |
| available_at | timestamptz |  | YES |
| settled_at | timestamptz |  | YES |
| reversed_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`
- `booking_id` -> `bookings(id)`
- `origin_ledger_entry_id` -> `ledger_entries(id)`
- `booking_id,vendor_id` -> `bookings(id,vendor_id)`
### settlement_status_history
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| settlement_item_id | uuid | FK | NO |
| from_status | settlement_status |  | YES |
| to_status | settlement_status |  | NO |
| actor_account_id | uuid | FK | YES |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `settlement_item_id` -> `settlement_items(id)`
- `actor_account_id` -> `accounts(id)`
### vendor_payout_accounts
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | NO |
| bank_code | varchar(50) |  | NO |
| account_holder_name | varchar(180) |  | NO |
| account_number_encrypted | text |  | NO |
| account_number_last4 | varchar(4) |  | NO |
| provider_recipient_ref | varchar(255) |  | YES |
| is_active | boolean |  | NO |
| security_hold_until | timestamptz |  | YES |
| verified_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`
### payouts
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| vendor_id | uuid | FK | NO |
| payout_account_id | uuid | FK | NO |
| status | payout_status |  | NO |
| total_amount | bigint |  | NO |
| currency | char(3) |  | NO |
| provider | varchar(50) |  | YES |
| provider_payout_ref | varchar(255) |  | YES |
| scheduled_for | timestamptz |  | YES |
| submitted_at | timestamptz |  | YES |
| paid_at | timestamptz |  | YES |
| failed_at | timestamptz |  | YES |
| failure_reason | text |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `vendor_id` -> `vendors(id)`
- `payout_account_id` -> `vendor_payout_accounts(id)`
- `payout_account_id,vendor_id` -> `vendor_payout_accounts(id,vendor_id)`
### payout_items
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| payout_id | uuid | FK | NO |
| settlement_item_id | uuid | FK | NO |
| amount_signed | bigint |  | NO |
| allocated_at | timestamptz |  | NO |
| released_at | timestamptz |  | YES |

Foreign keys:
- `payout_id` -> `payouts(id)`
- `settlement_item_id` -> `settlement_items(id)`
### payout_events
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| payout_id | uuid | FK | NO |
| provider | varchar(50) |  | NO |
| provider_event_id | varchar(255) |  | NO |
| provider_status | varchar(100) |  | YES |
| received_at | timestamptz |  | NO |
| processed_at | timestamptz |  | YES |

Foreign keys:
- `payout_id` -> `payouts(id)`
### payout_status_history
Source: `012_finance.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| payout_id | uuid | FK | NO |
| from_status | payout_status |  | YES |
| to_status | payout_status |  | NO |
| actor_account_id | uuid | FK | YES |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `payout_id` -> `payouts(id)`
- `actor_account_id` -> `accounts(id)`

## 06 Interaksi, trust dan audit
### booking_chat_messages
Source: `013_interaction.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| sender_account_id | uuid | FK | YES |
| message_type | chat_message_type |  | NO |
| body_text | text |  | YES |
| attachment_media_object_id | uuid | FK | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `sender_account_id` -> `accounts(id)`
- `attachment_media_object_id` -> `media_objects(id)`
### booking_chat_read_states
Source: `013_interaction.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| account_id | uuid | FK | NO |
| last_read_message_id | uuid | FK | YES |
| last_read_at | timestamptz |  | YES |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `account_id` -> `accounts(id)`
- `last_read_message_id` -> `booking_chat_messages(id)`
- `last_read_message_id,booking_id` -> `booking_chat_messages(id,booking_id)`
### booking_milestones
Source: `013_interaction.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| created_by_account_id | uuid | FK | NO |
| milestone_type | varchar(80) |  | NO |
| description | text |  | YES |
| media_object_id | uuid | FK | YES |
| occurred_at | timestamptz |  | NO |
| created_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `created_by_account_id` -> `accounts(id)`
- `media_object_id` -> `media_objects(id)`
### reviews
Source: `013_interaction.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| booking_id | uuid | FK | NO |
| reviewer_account_id | uuid | FK | NO |
| rating | smallint |  | NO |
| comment | text |  | YES |
| is_visible | boolean |  | NO |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `reviewer_account_id` -> `accounts(id)`
### support_cases
Source: `014_trust_safety.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| case_type | case_type |  | NO |
| status | case_status |  | NO |
| booking_id | uuid | FK | NO |
| pet_id | uuid | FK | YES |
| opened_by_type | case_actor_type |  | NO |
| reporter_account_id | uuid | FK | YES |
| assigned_admin_account_id | uuid | FK | YES |
| category | varchar(100) |  | NO |
| severity | varchar(50) |  | YES |
| description | text |  | NO |
| resolution_code | varchar(100) |  | YES |
| resolution_notes | text |  | YES |
| opened_at | timestamptz |  | NO |
| triaged_at | timestamptz |  | YES |
| investigation_started_at | timestamptz |  | YES |
| resolved_at | timestamptz |  | YES |
| closed_at | timestamptz |  | YES |
| created_at | timestamptz |  | NO |
| updated_at | timestamptz |  | NO |

Foreign keys:
- `booking_id` -> `bookings(id)`
- `pet_id` -> `pets(id)`
- `reporter_account_id` -> `accounts(id)`
- `assigned_admin_account_id` -> `accounts(id)`
- `booking_id,pet_id` -> `booking_items(booking_id,pet_id)`
### case_evidence
Source: `014_trust_safety.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| case_id | uuid | FK | NO |
| uploaded_by_account_id | uuid | FK | NO |
| media_object_id | uuid | FK | NO |
| description | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `case_id` -> `support_cases(id)`
- `uploaded_by_account_id` -> `accounts(id)`
- `media_object_id` -> `media_objects(id)`
### case_status_history
Source: `014_trust_safety.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| case_id | uuid | FK | NO |
| from_status | case_status |  | YES |
| to_status | case_status |  | NO |
| changed_by_type | case_actor_type |  | NO |
| changed_by_account_id | uuid | FK | YES |
| reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `case_id` -> `support_cases(id)`
- `changed_by_account_id` -> `accounts(id)`
### audit_logs
Source: `014_trust_safety.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| actor_type | audit_actor_type |  | NO |
| actor_account_id | uuid | FK | YES |
| action | varchar(150) |  | NO |
| target_type | varchar(100) |  | NO |
| target_id | varchar(150) |  | NO |
| reason | text |  | YES |
| metadata_sanitized_json | jsonb |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `actor_account_id` -> `accounts(id)`
### sensitive_access_logs
Source: `014_trust_safety.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| actor_account_id | uuid | FK | NO |
| data_class | data_classification |  | NO |
| target_type | varchar(100) |  | NO |
| target_id | varchar(150) |  | NO |
| access_reason | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
- `actor_account_id` -> `accounts(id)`
### media_objects
Source: `015_media.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| uploaded_by_account_id | uuid | FK | YES |
| data_class | data_classification |  | NO |
| storage_provider | varchar(50) |  | YES |
| object_key | text |  | NO |
| mime_type | varchar(150) |  | YES |
| size_bytes | bigint |  | YES |
| created_at | timestamptz |  | NO |
| deleted_at | timestamptz |  | YES |

Foreign keys:
- `uploaded_by_account_id` -> `accounts(id)`

## 07 Outbox dan consumer
### outbox_events
Source: `016_outbox.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| id | uuid | PK  | NO |
| event_key | varchar(180) |  | NO |
| aggregate_type | varchar(100) |  | NO |
| aggregate_id | uuid |  | NO |
| event_type | varchar(150) |  | NO |
| payload_json | jsonb |  | NO |
| status | outbox_event_status |  | NO |
| attempt_count | integer |  | NO |
| available_at | timestamptz |  | NO |
| published_at | timestamptz |  | YES |
| last_error | text |  | YES |
| created_at | timestamptz |  | NO |

Foreign keys:
### outbox_consumptions
Source: `026_outbox_consumptions.sql`

| Column | Type | Key | Nullable |
|---|---|---|---|
| event_key | varchar(180) | PK FK | NO |
| processed_at | timestamptz |  | NO |
| delivery_target | varchar(80) |  | NO |
| delivery_reference | varchar(255) |  | YES |

Foreign keys:
- `event_key` -> `outbox_events(event_key)`
