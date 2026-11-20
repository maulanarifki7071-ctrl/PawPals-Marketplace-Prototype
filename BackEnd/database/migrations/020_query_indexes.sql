-- PawPals PDB-10: query-path indexes. Unique constraints already supply their own indexes.
BEGIN;

CREATE INDEX idx_accounts_status ON accounts(status);
CREATE INDEX idx_otp_account_purpose_status ON otp_challenges(account_id, purpose, status);
CREATE INDEX idx_otp_expires_at ON otp_challenges(expires_at);
CREATE INDEX idx_otp_delivery_challenge_created ON otp_delivery_attempts(otp_challenge_id, created_at);
CREATE INDEX idx_otp_delivery_status ON otp_delivery_attempts(status);
CREATE INDEX idx_auth_session_account_status ON auth_sessions(account_id, status);
CREATE INDEX idx_auth_session_expires ON auth_sessions(expires_at);
CREATE INDEX idx_account_role_status ON account_role_assignments(account_id, status);

CREATE INDEX idx_vendor_application_vendor_status ON vendor_applications(vendor_id, status);
CREATE INDEX idx_vendor_application_history ON vendor_application_status_history(vendor_application_id, created_at);
CREATE INDEX idx_vendor_docs_application_type ON vendor_verification_documents(vendor_application_id, document_type);
CREATE INDEX idx_vendor_docs_application_status ON vendor_verification_documents(vendor_application_id, status);

CREATE INDEX idx_customer_addresses_account ON customer_addresses(account_id);
CREATE INDEX idx_vendor_locations_vendor ON vendor_locations(vendor_id);
CREATE INDEX idx_vendor_locations_type ON vendor_locations(location_type);
CREATE INDEX idx_pets_owner ON pets(owner_account_id);

CREATE INDEX idx_vendor_services_vendor ON vendor_services(vendor_id);
CREATE INDEX idx_vendor_services_status ON vendor_services(status);
CREATE INDEX idx_vendor_services_delivery_mode ON vendor_services(delivery_mode);
CREATE INDEX idx_service_packages_service ON service_packages(vendor_service_id);
CREATE INDEX idx_service_availability_service_time ON service_availability_windows(vendor_service_id, starts_at, ends_at);
CREATE INDEX idx_service_override_service_time ON service_capacity_overrides(vendor_service_id, starts_at, ends_at);

CREATE INDEX idx_bookings_customer ON bookings(customer_account_id);
CREATE INDEX idx_bookings_vendor ON bookings(vendor_id);
CREATE INDEX idx_bookings_vendor_service ON bookings(vendor_service_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_schedule ON bookings(scheduled_start_at);
CREATE INDEX idx_bookings_vendor_status_start ON bookings(vendor_id, status, scheduled_start_at);
CREATE INDEX idx_booking_status_history ON booking_status_history(booking_id, created_at);

CREATE INDEX idx_capacity_service_status ON capacity_reservations(vendor_service_id, status);
CREATE INDEX idx_capacity_service_time ON capacity_reservations(vendor_service_id, starts_at, occupied_ends_at);
CREATE INDEX idx_capacity_expires ON capacity_reservations(expires_at);
CREATE INDEX idx_capacity_booking ON capacity_reservations(booking_id);

CREATE INDEX idx_refunds_payment_status ON refunds(payment_id, status);
CREATE INDEX idx_cancellation_attribution_history ON cancellation_attribution_events(booking_cancellation_id, created_at);
CREATE INDEX idx_reschedules_booking ON reschedules(booking_id);
CREATE INDEX idx_reschedules_booking_mode_status ON reschedules(booking_id, mode, status);

CREATE INDEX idx_ledger_vendor ON ledger_entries(vendor_id);
CREATE INDEX idx_ledger_booking ON ledger_entries(booking_id);
CREATE INDEX idx_settlement_vendor_status ON settlement_items(vendor_id, status);
CREATE INDEX idx_settlement_available ON settlement_items(vendor_id, available_at) WHERE status = 'AVAILABLE';
CREATE INDEX idx_settlement_history ON settlement_status_history(settlement_item_id, created_at);
CREATE INDEX idx_payout_account_vendor ON vendor_payout_accounts(vendor_id);
CREATE INDEX idx_payout_vendor_status ON payouts(vendor_id, status);
CREATE INDEX idx_payout_item_payout ON payout_items(payout_id);
CREATE INDEX idx_payout_item_settlement ON payout_items(settlement_item_id);
CREATE INDEX idx_payout_history ON payout_status_history(payout_id, created_at);

CREATE INDEX idx_chat_booking_created ON booking_chat_messages(booking_id, created_at);
CREATE INDEX idx_milestone_booking_occurred ON booking_milestones(booking_id, occurred_at);

CREATE INDEX idx_case_booking ON support_cases(booking_id);
CREATE INDEX idx_case_status ON support_cases(status);
CREATE INDEX idx_case_type ON support_cases(case_type);
CREATE INDEX idx_case_assigned_admin ON support_cases(assigned_admin_account_id);
CREATE INDEX idx_case_evidence_case ON case_evidence(case_id);
CREATE INDEX idx_case_history ON case_status_history(case_id, created_at);
CREATE INDEX idx_audit_actor ON audit_logs(actor_account_id);
CREATE INDEX idx_audit_target ON audit_logs(target_type, target_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at);
CREATE INDEX idx_sensitive_access_actor ON sensitive_access_logs(actor_account_id);
CREATE INDEX idx_sensitive_access_class ON sensitive_access_logs(data_class);
CREATE INDEX idx_sensitive_access_target ON sensitive_access_logs(target_type, target_id);
CREATE INDEX idx_sensitive_access_created ON sensitive_access_logs(created_at);

CREATE INDEX idx_outbox_pending ON outbox_events(available_at) WHERE status = 'PENDING';
CREATE INDEX idx_outbox_aggregate ON outbox_events(aggregate_type, aggregate_id);

COMMIT;
