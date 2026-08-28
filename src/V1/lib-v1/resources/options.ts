// Shared enum option lists pulled from the DB CHECK/enum definitions in
// supabase/migrations. Most of these are convention (free text), not
// DB-enforced — see the migration comments for which ones are hard enums.

export const CONFIDENTIALITY = [
  "public",
  "internal",
  "client_confidential",
  "attorney_client_privileged",
  "attorney_work_product",
  "highly_restricted",
  "court_sealed",
  "regulatory_restricted",
  "law_enforcement_restricted",
  "phi",
  "pii",
  "pci",
  "trade_secret",
].map((v) => ({ label: v, value: v }));

export const MATTER_TYPE = [
  "fraud_exam",
  "litigation",
  "treasury",
  "monitorship",
  "receivership",
].map((v) => ({ label: v, value: v }));

export const ACCESS_LEVEL = ["read", "contribute", "review", "approve", "matter_admin"].map(
  (v) => ({ label: v, value: v }),
);

export const EVIDENCE_TYPE = ["document", "email", "image", "device", "bank_record", "dataset"].map(
  (v) => ({ label: v, value: v }),
);

export const CUSTODY_EVENT_TYPE = [
  "collected",
  "received",
  "imaged",
  "hashed",
  "moved",
  "viewed",
  "exported",
  "produced",
  "returned",
  "destroyed",
].map((v) => ({ label: v, value: v }));

export const TRANSACTION_TYPE = [
  "wire",
  "ach",
  "check",
  "card",
  "cash",
  "transfer",
  "journal",
  "payroll",
  "claim",
  "fee",
].map((v) => ({ label: v, value: v }));

export const ENTITY_TYPE = ["person", "organization", "account", "device", "asset", "address"].map(
  (v) => ({ label: v, value: v }),
);

export const ALLEGATION_STATUS = [
  "reported",
  "triaged",
  "under_review",
  "evidence_developing",
  "substantiated",
  "partially_substantiated",
  "unsubstantiated",
  "unable_to_determine",
  "closed",
].map((v) => ({ label: v, value: v }));

export const LEAD_TYPE = ["hypothesis", "lead", "anomaly"].map((v) => ({ label: v, value: v }));

export const FACT_TYPE = ["observed", "documented", "calculated", "witness", "inferred"].map(
  (v) => ({ label: v, value: v }),
);

export const FACT_CONFIDENCE = ["high", "medium", "low"].map((v) => ({ label: v, value: v }));

export const FINDING_CONCLUSION_STATUS = [
  "draft",
  "under_review",
  "supported",
  "partially_supported",
  "not_supported",
  "inconclusive",
  "superseded",
  "withdrawn",
  "final",
].map((v) => ({ label: v, value: v }));

export const ALERT_REVIEW_STATUS = [
  "new",
  "triaged",
  "assigned",
  "under_review",
  "escalated",
  "closed",
].map((v) => ({ label: v, value: v }));

export const ALERT_DISPOSITION = [
  "false_positive",
  "explained",
  "control_gap",
  "linked_to_finding",
  "referred",
].map((v) => ({ label: v, value: v }));

export const REPORT_TYPE = [
  "fraud_examination",
  "litigation_support",
  "treasury_review",
  "monitor",
  "expert",
].map((v) => ({ label: v, value: v }));
