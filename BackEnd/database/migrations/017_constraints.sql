-- PawPals PDB-03: cross-domain FK / ownership constraints that require all tables to exist.
BEGIN;

-- Composite uniqueness used by ownership-preserving FKs.
ALTER TABLE vendor_locations ADD CONSTRAINT uq_vendor_locations_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE vendor_services ADD CONSTRAINT uq_vendor_services_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE service_packages ADD CONSTRAINT uq_service_packages_id_service UNIQUE (id, vendor_service_id);
ALTER TABLE bookings ADD CONSTRAINT uq_bookings_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE bookings ADD CONSTRAINT uq_bookings_id_service UNIQUE (id, vendor_service_id);
ALTER TABLE booking_items ADD CONSTRAINT uq_booking_items_booking_package UNIQUE (booking_id, service_package_id);
ALTER TABLE booking_items ADD CONSTRAINT uq_booking_items_booking_pet UNIQUE (booking_id, pet_id);
ALTER TABLE capacity_reservations ADD CONSTRAINT uq_capacity_id_booking UNIQUE (id, booking_id);
ALTER TABLE reschedules ADD CONSTRAINT uq_reschedules_id_booking UNIQUE (id, booking_id);
ALTER TABLE vendor_payout_accounts ADD CONSTRAINT uq_payout_accounts_id_vendor UNIQUE (id, vendor_id);
ALTER TABLE booking_chat_messages ADD CONSTRAINT uq_chat_message_id_booking UNIQUE (id, booking_id);

-- Ownership consistency.
ALTER TABLE vendor_services
  ADD CONSTRAINT fk_vendor_service_origin_same_vendor
  FOREIGN KEY (origin_vendor_location_id, vendor_id)
  REFERENCES vendor_locations(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE bookings
  ADD CONSTRAINT fk_booking_service_same_vendor
  FOREIGN KEY (vendor_service_id, vendor_id)
  REFERENCES vendor_services(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE capacity_reservations
  ADD CONSTRAINT fk_capacity_booking_service
  FOREIGN KEY (booking_id, vendor_service_id)
  REFERENCES bookings(id, vendor_service_id) ON DELETE RESTRICT;

ALTER TABLE capacity_reservations
  ADD CONSTRAINT fk_capacity_package_service
  FOREIGN KEY (service_package_id, vendor_service_id)
  REFERENCES service_packages(id, vendor_service_id) ON DELETE RESTRICT;

ALTER TABLE capacity_reservations
  ADD CONSTRAINT fk_capacity_booking_package
  FOREIGN KEY (booking_id, service_package_id)
  REFERENCES booking_items(booking_id, service_package_id) ON DELETE RESTRICT;

ALTER TABLE reschedules
  ADD CONSTRAINT fk_reschedule_old_capacity_booking
  FOREIGN KEY (old_capacity_reservation_id, booking_id)
  REFERENCES capacity_reservations(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE reschedules
  ADD CONSTRAINT fk_reschedule_new_capacity_booking
  FOREIGN KEY (new_capacity_reservation_id, booking_id)
  REFERENCES capacity_reservations(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE booking_schedule_history
  ADD CONSTRAINT fk_schedule_history_reschedule_booking
  FOREIGN KEY (reschedule_id, booking_id)
  REFERENCES reschedules(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE ledger_entries
  ADD CONSTRAINT fk_ledger_booking_vendor
  FOREIGN KEY (booking_id, vendor_id)
  REFERENCES bookings(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE settlement_items
  ADD CONSTRAINT fk_settlement_booking_vendor
  FOREIGN KEY (booking_id, vendor_id)
  REFERENCES bookings(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE payouts
  ADD CONSTRAINT fk_payout_account_same_vendor
  FOREIGN KEY (payout_account_id, vendor_id)
  REFERENCES vendor_payout_accounts(id, vendor_id) ON DELETE RESTRICT;

ALTER TABLE booking_chat_read_states
  ADD CONSTRAINT fk_chat_read_message_same_booking
  FOREIGN KEY (last_read_message_id, booking_id)
  REFERENCES booking_chat_messages(id, booking_id) ON DELETE RESTRICT;

ALTER TABLE support_cases
  ADD CONSTRAINT fk_support_case_pet_same_booking
  FOREIGN KEY (booking_id, pet_id)
  REFERENCES booking_items(booking_id, pet_id) ON DELETE RESTRICT;

-- MediaObject cross-domain links.
ALTER TABLE vendor_verification_documents
  ADD CONSTRAINT fk_vendor_verification_media
  FOREIGN KEY (media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE pets
  ADD CONSTRAINT fk_pet_photo_media
  FOREIGN KEY (photo_media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE booking_chat_messages
  ADD CONSTRAINT fk_chat_attachment_media
  FOREIGN KEY (attachment_media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE booking_milestones
  ADD CONSTRAINT fk_milestone_media
  FOREIGN KEY (media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

ALTER TABLE case_evidence
  ADD CONSTRAINT fk_case_evidence_media
  FOREIGN KEY (media_object_id) REFERENCES media_objects(id) ON DELETE RESTRICT;

COMMIT;
