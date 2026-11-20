-- PawPals PDB-11: minimal RBAC seed aligned to agreed Admin bundles.
-- Permission codes are deliberately limited to current MVP domains.
BEGIN;

INSERT INTO roles (code, name, description) VALUES
  ('SUPER_ADMIN','Super Admin','Critical administration and complete permission bundle.'),
  ('OPERATIONS_ADMIN','Operations Admin','Vendor verification and operational booking administration.'),
  ('FINANCE_ADMIN','Finance Admin','Payment, refund, ledger, settlement and payout operations.'),
  ('TRUST_SAFETY_ADMIN','Trust & Safety Admin','Incident, dispute, report and restricted evidence handling.')
ON CONFLICT (code) DO NOTHING;

INSERT INTO permissions (code,module,name,description) VALUES
  ('admin.rbac.manage','admin','Manage RBAC','Manage admin role and permission assignments.'),
  ('audit.view','admin','View Audit','View system/admin audit records.'),
  ('operations.vendor_application.review','operations','Review Vendor Application','Review vendor onboarding applications and verification documents.'),
  ('operations.vendor.suspend','operations','Suspend Vendor','Apply operational vendor suspension.'),
  ('operations.booking.view','operations','View Booking','View booking data required for operations.'),
  ('finance.payment.view','finance','View Payments','View payment and provider event data.'),
  ('finance.refund.manage','finance','Manage Refunds','Create/process/reconcile refunds.'),
  ('finance.ledger.view','finance','View Ledger','View append-only ledger and settlements.'),
  ('finance.payout.manage','finance','Manage Payouts','Queue/process/reconcile vendor payouts.'),
  ('trust_safety.case.manage','trust_safety','Manage Cases','Triage, investigate, resolve and close support cases.'),
  ('trust_safety.sensitive_access','trust_safety','Access Restricted Evidence','Access case-authorized sensitive/restricted evidence.')
ON CONFLICT (code) DO NOTHING;

-- SUPER_ADMIN receives all current permissions.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.code='SUPER_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
  'operations.vendor_application.review','operations.vendor.suspend','operations.booking.view','audit.view'
) WHERE r.code='OPERATIONS_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
  'finance.payment.view','finance.refund.manage','finance.ledger.view','finance.payout.manage','audit.view'
) WHERE r.code='FINANCE_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
  'trust_safety.case.manage','trust_safety.sensitive_access','audit.view'
) WHERE r.code='TRUST_SAFETY_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

COMMIT;
