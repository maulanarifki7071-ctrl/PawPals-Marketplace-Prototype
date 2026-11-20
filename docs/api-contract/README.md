# API contract — OpenAPI 1.2.0
Base URL development: `http://localhost:3000/api/v1`; frontend Vite menggunakan `/api/v1` via proxy. **151 operasi pada 125 path**, ditambah 1 route khusus dev di luar kontrak. Kontrak machine-readable tetap di [`BackEnd/openapi/openapi.yaml`](../../BackEnd/openapi/openapi.yaml), tidak diduplikasi. Daftar di bawah dihasilkan dari YAML aktual; payload, schema, status code dan authorization rinci lihat YAML dan router.

- Session server-managed melalui HttpOnly cookie; request browser menyertakan credentials. CSRF origin guard memeriksa authenticated writes.
- Success: `{ "data": ..., "request_id": "..." }`. Error: `{ "error": { "code": "...", "message": "..." }, "request_id": "..." }`. HTTP 204 tanpa body.
- Pagination: page, limit (default 20, max 100; pada source nilai di luar rentang fallback 20), items/total/total_pages. Money integer IDR.
- Private resource mengikuti ownership; admin tanpa permission ditolak. Jangan gunakan UUID sebagai bukti otorisasi.
- 409 SLOT_UNAVAILABLE/CONCURRENT_UPDATE, 422 PET_NOT_COMPATIBLE, 403 CSRF_ORIGIN_FORBIDDEN: perbaiki input/izin dan refresh slot; jangan bypass guard.

## Inventaris operasi

### AC-01 Auth & Account (11)

| Method | Path relatif | Summary / operation |
|---|---|---|
| POST | `/auth/register` | Register a PawPals account |
| POST | `/auth/otp/verify` | Verify purpose-aware OTP |
| POST | `/auth/otp/resend` | Resend or replace OTP challenge |
| POST | `/auth/login` | Login with phone and password |
| POST | `/auth/logout` | Revoke current session |
| GET | `/accounts/me` | Get current account |
| POST | `/auth/password/forgot` | Request password reset |
| POST | `/auth/password/reset` | Reset password using short-lived authorization |
| POST | `/auth/reauth` | Create recent reauthentication grant |
| POST | `/auth/sensitive-otp/request` | Request OTP for sensitive action |
| POST | `/auth/sensitive-otp/verify` | Verify purpose-bound sensitive OTP |

### AC-02 Vendor Registration & Verification (16)

| Method | Path relatif | Summary / operation |
|---|---|---|
| POST | `/vendor-applications` | Start vendor application |
| GET | `/vendors/me` | Get current vendor profile |
| GET | `/vendor-applications/me` | Get current vendor application |
| GET | `/vendor-applications/{id}` | Get own vendor application |
| PATCH | `/vendor-applications/{id}` | Update own vendor application |
| POST | `/vendor-applications/{id}/terms/accept` | Accept vendor terms |
| POST | `/vendor-applications/{id}/documents/upload-intent` | Create verification-document upload intent |
| POST | `/vendor-applications/{id}/documents` | Attach verification document |
| GET | `/vendor-applications/{id}/documents` | List own verification documents |
| POST | `/vendor-applications/{id}/submit` | Submit vendor application |
| GET | `/admin/vendor-applications` | List vendor applications for review |
| POST | `/admin/vendor-applications/{id}/review/start` | Start vendor application review |
| POST | `/admin/vendor-applications/{applicationId}/documents/{documentId}/review` | Review a verification document |
| POST | `/admin/vendor-applications/{id}/request-revision` | Request vendor application revision |
| POST | `/admin/vendor-applications/{id}/approve` | Approve vendor application |
| POST | `/admin/vendor-applications/{id}/reject` | Reject vendor application |

### AC-03 Location (11)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/customer-addresses` | List own customer addresses |
| POST | `/customer-addresses` | Create customer address |
| GET | `/customer-addresses/{id}` | Get own customer address |
| PATCH | `/customer-addresses/{id}` | Update own customer address |
| DELETE | `/customer-addresses/{id}` | Delete own customer address |
| PUT | `/customer-addresses/{id}/default` | Atomically set default customer address |
| GET | `/vendors/me/locations` | List own vendor locations |
| POST | `/vendors/me/locations` | Create vendor location |
| GET | `/vendors/me/locations/{id}` | Get vendor location detail |
| PATCH | `/vendors/me/locations/{id}` | Update vendor location |
| DELETE | `/vendors/me/locations/{id}` | Delete vendor location if not in use |

### AC-04 Pet Profile & Safety (10)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/pets` | List own pets |
| POST | `/pets` | Create pet |
| GET | `/pets/{id}` | Get own pet detail |
| PATCH | `/pets/{id}` | Update own pet profile |
| GET | `/pets/{id}/safety-profile` | Get pet safety profile |
| PUT | `/pets/{id}/safety-profile` | Create or replace pet safety profile |
| PATCH | `/pets/{id}/safety-profile` | Partially update pet safety profile |
| POST | `/pets/{id}/photo/upload-intent` | Create pet-photo upload intent |
| PUT | `/pets/{id}/photo` | Attach uploaded pet photo |
| DELETE | `/pets/{id}/photo` | Detach pet photo |

### Tambahan API (di luar tag AC pada YAML) (10)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/pets/{id}/photo` | Signed GET URL for current owner pet photo |
| GET | `/admin/accounts` | Minimal account directory; admin.rbac.manage required |
| GET | `/admin/vendors` | Vendor directory; operations.vendor.suspend required |
| GET | `/services/{id}/booking-options` | Advisory booking slots with pet compatibility, 30-minute start increments. |
| GET | `/bookings/{id}/media/{mediaId}` | Signed GET for media linked to booking; participant only. |
| GET | `/chat/conversations` | Current account conversations and unread counts. |
| GET | `/admin/vendor-applications/{id}/documents` | Review permission required. |
| GET | `/admin/vendor-applications/{id}/documents/{documentId}/media` | Review permission required; private signed GET. |
| GET | `/bookings/{id}/reschedule-options` | Advisory availability, excludes current reservation. |
| GET | `/bookings/{id}/reschedule-proposals` | Participant-visible vendor proposals. |

### AC-05 Service / Package / Availability / Capacity (22)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/vendors/me/services` | List own vendor services |
| POST | `/vendors/me/services` | Create vendor service |
| PATCH | `/vendors/me/services/{serviceId}` | Update vendor service |
| POST | `/vendors/me/services/{serviceId}/activate` | Activate vendor service |
| POST | `/vendors/me/services/{serviceId}/deactivate` | Deactivate vendor service |
| GET | `/vendors/me/services/{serviceId}/packages` | List service packages |
| POST | `/vendors/me/services/{serviceId}/packages` | Create service package |
| PATCH | `/vendors/me/services/{serviceId}/packages/{packageId}` | Update service package |
| POST | `/vendors/me/services/{serviceId}/packages/{packageId}/activate` | Activate service package |
| POST | `/vendors/me/services/{serviceId}/packages/{packageId}/deactivate` | Deactivate service package |
| GET | `/vendors/me/services/{serviceId}/pet-rules` | Get service pet rules |
| PUT | `/vendors/me/services/{serviceId}/pet-rules` | Create or replace service pet rules |
| GET | `/vendors/me/services/{serviceId}/availability` | List availability windows |
| POST | `/vendors/me/services/{serviceId}/availability` | Create availability window |
| PATCH | `/vendors/me/services/{serviceId}/availability/{windowId}` | Update availability window |
| DELETE | `/vendors/me/services/{serviceId}/availability/{windowId}` | Delete availability window |
| GET | `/vendors/me/services/{serviceId}/capacity-overrides` | List capacity overrides |
| POST | `/vendors/me/services/{serviceId}/capacity-overrides` | Create capacity override |
| PATCH | `/vendors/me/services/{serviceId}/capacity-overrides/{overrideId}` | Update capacity override |
| DELETE | `/vendors/me/services/{serviceId}/capacity-overrides/{overrideId}` | Delete capacity override |
| GET | `/services` | Public service discovery |
| GET | `/services/{serviceId}` | Get public service detail |

### AC-06 Booking & Capacity (7)

| Method | Path relatif | Summary / operation |
|---|---|---|
| POST | `/bookings` | Continue to payment: create booking, pending payment, and held capacity |
| GET | `/bookings` | List customer bookings |
| GET | `/bookings/{id}` | Get customer booking detail |
| GET | `/vendors/me/bookings` | List vendor bookings |
| GET | `/vendors/me/bookings/{id}` | Get vendor booking detail |
| POST | `/vendors/me/bookings/{id}/start` | Start service execution |
| POST | `/vendors/me/bookings/{id}/complete` | Complete service execution |

### AC-07 Payment & Refund (10)

| Method | Path relatif | Summary / operation |
|---|---|---|
| POST | `/payments/{id}/checkout-session` | Create provider checkout session |
| GET | `/payments/{id}` | Get payment status |
| POST | `/webhooks/midtrans/payments` | Receive verified Midtrans payment webhook |
| GET | `/bookings/{id}/refunds` | List refunds for own booking |
| GET | `/admin/payments` | List payments |
| GET | `/admin/payments/{id}` | Get payment detail |
| GET | `/admin/refunds` | List refunds |
| GET | `/admin/refunds/{id}` | Get refund detail |
| POST | `/admin/payments/{id}/refunds` | Create corrective refund obligation |
| POST | `/admin/refunds/{id}/retry` | Controlled reconciled retry of the same refund obligation |

### AC-08 Cancellation & Reschedule (8)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/bookings/{id}/cancellation-preview` | Preview cancellation refund and retained amount |
| POST | `/bookings/{id}/cancel` | Execute customer cancellation |
| POST | `/vendors/me/bookings/{id}/cancel` | Execute controlled vendor cancellation |
| POST | `/vendors/me/cancellation-claims/{claimId}/respond` | Respond to vendor-cancellation claim |
| POST | `/bookings/{id}/reschedules` | Customer self-reschedule |
| POST | `/vendors/me/bookings/{id}/reschedule-proposals` | Create vendor reschedule proposal |
| POST | `/bookings/{bookingId}/reschedules/{rescheduleId}/accept` | Accept vendor reschedule proposal and atomically swap capacity |
| POST | `/bookings/{bookingId}/reschedules/{rescheduleId}/decline` | Decline vendor reschedule proposal |

### AC-09 Finance / Ledger / Settlement / Payout (11)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/vendors/me/finance/summary` | Get vendor finance summary |
| GET | `/vendors/me/settlements` | List vendor settlements |
| GET | `/vendors/me/payouts` | List vendor payouts |
| GET | `/vendors/me/payouts/{id}` | Get vendor payout detail |
| GET | `/vendors/me/payout-accounts` | List own masked payout accounts |
| POST | `/vendors/me/payout-accounts` | Create or replace payout account |
| GET | `/admin/ledger` | List ledger entries |
| GET | `/admin/settlements` | List settlement items |
| GET | `/admin/payouts` | List payouts |
| GET | `/admin/payouts/{id}` | Get payout detail |
| POST | `/admin/payouts/{id}/reconcile` | Reconcile payout provider state |

### AC-10 Interaction / Milestone / Review (10)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/bookings/{id}/chat/messages` | List booking chat messages |
| POST | `/bookings/{id}/chat/messages` | Append booking chat message |
| POST | `/bookings/{id}/chat/attachments/upload-intent` | Create booking-private chat attachment upload intent |
| PUT | `/bookings/{id}/chat/read-state` | Update chat read marker |
| GET | `/bookings/{id}/milestones` | List booking milestones |
| POST | `/vendors/me/bookings/{id}/milestones` | Create vendor milestone during IN_PROGRESS |
| POST | `/vendors/me/bookings/{id}/milestones/upload-intent` | Create milestone-media upload intent |
| POST | `/bookings/{id}/review` | Create one-shot customer review after completion |
| GET | `/vendors/{id}/reviews` | List visible public vendor reviews |
| GET | `/services/{id}/reviews` | List visible public service reviews |

### AC-11 Trust & Safety (14)

| Method | Path relatif | Summary / operation |
|---|---|---|
| POST | `/bookings/{id}/cases` | Create booking-bound case |
| GET | `/cases` | List cases reported by current account |
| GET | `/cases/{id}` | Get reporter-visible case detail |
| GET | `/cases/{id}/evidence` | List reporter-visible case evidence |
| POST | `/cases/{id}/evidence` | Attach evidence to active case |
| POST | `/cases/{id}/evidence/upload-intent` | Create restricted-evidence upload intent |
| POST | `/admin/cases/{id}/assign` | Assign case |
| POST | `/admin/cases/{id}/triage` | Triage case |
| POST | `/admin/cases/{id}/investigation/start` | Start case investigation |
| POST | `/admin/cases/{id}/resolve` | Resolve case |
| POST | `/admin/cases/{id}/close` | Close case |
| GET | `/admin/cases` | List trust and safety cases |
| GET | `/admin/cases/{id}` | Get trust and safety case detail |
| POST | `/admin/cases/{id}/evidence/{evidenceId}/access` | Create audited short-lived access to restricted evidence |

### AC-12 Admin / RBAC / Audit (11)

| Method | Path relatif | Summary / operation |
|---|---|---|
| GET | `/admin/me` | Get active admin capabilities |
| GET | `/admin/roles` | List canonical roles |
| GET | `/admin/permissions` | List canonical permissions |
| GET | `/admin/accounts/{id}/roles` | List account admin roles |
| POST | `/admin/accounts/{id}/roles` | Assign canonical admin role |
| POST | `/admin/accounts/{id}/roles/{roleCode}/revoke` | Revoke canonical admin role |
| GET | `/admin/audit-logs` | List sanitized audit logs |
| GET | `/admin/bookings` | List bookings for operations |
| GET | `/admin/bookings/{id}` | Get booking for operations |
| POST | `/admin/vendors/{id}/suspend` | Suspend vendor |
| POST | `/admin/vendors/{id}/unsuspend` | Unsuspend vendor |

## Route di luar kontrak produksi
`POST /dev/payments/{id}/simulate`: loopback, opt-in MOCK, non-production, customer owner. Outcome `PAID`, `FAILED`, `EXPIRED`. Bukan endpoint pembayaran nyata.

Route coverage terakhir dalam ZIP: 151 OpenAPI / 152 implementasi termasuk 1 dev-only, PASS. Cakupan route tidak membuktikan semua schema dan transaksi benar pada runtime.
