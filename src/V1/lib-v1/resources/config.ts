import {
  ALERT_DISPOSITION,
  ALERT_REVIEW_STATUS,
  ALLEGATION_STATUS,
  CONFIDENTIALITY,
  CUSTODY_EVENT_TYPE,
  ENTITY_TYPE,
  EVIDENCE_TYPE,
  FACT_CONFIDENCE,
  FACT_TYPE,
  FINDING_CONCLUSION_STATUS,
  LEAD_TYPE,
  MATTER_TYPE,
  REPORT_TYPE,
  TRANSACTION_TYPE,
} from "./options";
import type { ResourceConfig } from "./types";

export interface NavGroup {
  label: string;
  resources: ResourceConfig[];
}

const matters: ResourceConfig = {
  schema: "core",
  table: "matters",
  slug: "matters",
  label: "Matter",
  pluralLabel: "Matters",
  description:
    "The case/engagement workspace. Everything else hangs off a matter. Matter number is assigned automatically.",
  listColumns: [
    { key: "matter_number", label: "Number" },
    { key: "matter_name", label: "Name" },
    { key: "matter_type", label: "Type" },
    { key: "status", label: "Status" },
    { key: "confidentiality", label: "Confidentiality" },
  ],
  orderBy: { column: "matter_number" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_name", label: "Matter name", type: "text", required: true },
    {
      key: "matter_type",
      label: "Matter type",
      type: "select",
      required: true,
      options: MATTER_TYPE,
    },
    {
      key: "confidentiality",
      label: "Confidentiality",
      type: "select",
      options: CONFIDENTIALITY,
      defaultValue: "client_confidential",
    },
  ],
};

const evidenceItems: ResourceConfig = {
  schema: "evidence",
  table: "evidence_items",
  slug: "evidence-items",
  label: "Evidence item",
  pluralLabel: "Evidence",
  description: "Every artifact treated as evidence: documents, files, devices, datasets.",
  listColumns: [
    { key: "human_evidence_no", label: "Evidence no." },
    { key: "title", label: "Title" },
    { key: "evidence_type", label: "Type" },
    { key: "status", label: "Status" },
    { key: "legal_hold_status", label: "Legal hold" },
  ],
  orderBy: { column: "human_evidence_no" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "evidence_type",
      label: "Evidence type",
      type: "select",
      required: true,
      options: EVIDENCE_TYPE,
    },
    { key: "title", label: "Title", type: "text" },
    {
      key: "confidentiality",
      label: "Confidentiality",
      type: "select",
      options: CONFIDENTIALITY,
      defaultValue: "client_confidential",
    },
  ],
};

const custodyEvents: ResourceConfig = {
  schema: "evidence",
  table: "chain_of_custody_events",
  slug: "custody-events",
  label: "Custody event",
  pluralLabel: "Custody",
  description:
    "Append-only, hash-chained. Only new events can be added — nothing here can be edited.",
  listColumns: [
    { key: "seq", label: "#" },
    { key: "evidence_id", label: "Evidence item" },
    { key: "event_type", label: "Event" },
    { key: "created_at", label: "Recorded" },
  ],
  orderBy: { column: "seq" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "evidence_id",
      label: "Evidence item",
      type: "relation",
      required: true,
      relation: {
        schema: "evidence",
        table: "evidence_items",
        labelKey: "human_evidence_no",
        valueKey: "id",
        matterScoped: true,
      },
    },
    {
      key: "event_type",
      label: "Event type",
      type: "select",
      required: true,
      options: CUSTODY_EVENT_TYPE,
    },
  ],
};

const transactions: ResourceConfig = {
  schema: "canonical",
  table: "transactions",
  slug: "transactions",
  label: "Transaction",
  pluralLabel: "Financial activity",
  description: "Core money-movement record.",
  listColumns: [
    { key: "transaction_type", label: "Type" },
    { key: "amount_original", label: "Amount" },
    { key: "currency_original", label: "Currency" },
    { key: "created_at", label: "Recorded" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "transaction_type",
      label: "Transaction type",
      type: "select",
      options: TRANSACTION_TYPE,
    },
    { key: "amount_original", label: "Amount", type: "number", required: true },
    {
      key: "currency_original",
      label: "Currency (3-letter code)",
      type: "text",
      required: true,
      defaultValue: "USD",
    },
  ],
};

const entities: ResourceConfig = {
  schema: "canonical",
  table: "entities",
  slug: "entities",
  label: "Entity",
  pluralLabel: "People & entities",
  description: "Master node for every person, org, account, device, or asset in the matter.",
  listColumns: [
    { key: "entity_type", label: "Type" },
    { key: "name_normalized", label: "Name" },
    { key: "created_at", label: "Added" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "entity_type",
      label: "Entity type",
      type: "select",
      required: true,
      options: ENTITY_TYPE,
    },
    { key: "name_normalized", label: "Name", type: "text" },
  ],
};

const allegations: ResourceConfig = {
  schema: "investigation",
  table: "allegations",
  slug: "allegations",
  label: "Allegation",
  pluralLabel: "Allegations",
  description: "Top of the hierarchy: allegation -> lead -> fact -> finding.",
  listColumns: [
    { key: "allegation_no", label: "No." },
    { key: "status", label: "Status" },
    { key: "created_at", label: "Opened" },
  ],
  orderBy: { column: "allegation_no" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "status",
      label: "Status",
      type: "select",
      options: ALLEGATION_STATUS,
      defaultValue: "reported",
    },
  ],
  updateFields: [{ key: "status", label: "Status", type: "select", options: ALLEGATION_STATUS }],
};

const leads: ResourceConfig = {
  schema: "investigation",
  table: "leads",
  slug: "leads",
  label: "Lead",
  pluralLabel: "Leads & alerts",
  description: "Investigative hypothesis or anomaly, optionally under an allegation.",
  listColumns: [
    { key: "lead_type", label: "Type" },
    { key: "status", label: "Status" },
    { key: "created_at", label: "Opened" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "allegation_id",
      label: "Allegation (optional)",
      type: "relation",
      relation: {
        schema: "investigation",
        table: "allegations",
        labelKey: "allegation_no",
        valueKey: "id",
        matterScoped: true,
      },
    },
    { key: "lead_type", label: "Lead type", type: "select", options: LEAD_TYPE },
  ],
};

const facts: ResourceConfig = {
  schema: "investigation",
  table: "facts",
  slug: "facts",
  label: "Fact",
  pluralLabel: "Verified facts",
  description: "A discrete, sourced fact. Cite it on a finding via finding_sources.",
  listColumns: [
    { key: "statement", label: "Statement" },
    { key: "fact_type", label: "Type" },
    { key: "confidence", label: "Confidence" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "statement", label: "Statement", type: "textarea", required: true },
    { key: "fact_type", label: "Fact type", type: "select", options: FACT_TYPE },
    { key: "confidence", label: "Confidence", type: "select", options: FACT_CONFIDENCE },
  ],
};

const findings: ResourceConfig = {
  schema: "investigation",
  table: "findings",
  slug: "findings",
  label: "Finding",
  pluralLabel: "Findings",
  description:
    'The formal conclusion object. Moving to "supported"/"final" requires a reviewer and a linked fact — set those first or the write is rejected.',
  listColumns: [
    { key: "title", label: "Title" },
    { key: "conclusion_status", label: "Status" },
    { key: "created_at", label: "Opened" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "title", label: "Title", type: "text", required: true },
    {
      key: "confidentiality",
      label: "Confidentiality",
      type: "select",
      options: CONFIDENTIALITY,
      defaultValue: "attorney_work_product",
    },
  ],
  updateFields: [
    {
      key: "conclusion_status",
      label: "Conclusion status",
      type: "select",
      options: FINDING_CONCLUSION_STATUS,
    },
    {
      key: "classification",
      label: "Classification",
      type: "text",
      help: "substantiated, control_deficiency, policy_violation, referral_recommended...",
    },
    { key: "methodology", label: "Methodology", type: "textarea" },
    { key: "financial_impact", label: "Financial impact", type: "number" },
    { key: "currency", label: "Currency (3-letter code)", type: "text" },
    { key: "reviewed_by", label: "Reviewer", type: "text", auto: "current_user_id" },
    { key: "reviewed_at", label: "Reviewed at", type: "date", auto: "now" },
  ],
};

const ruleDefinitions: ResourceConfig = {
  schema: "rules",
  table: "rule_definitions",
  slug: "rule-catalog",
  label: "Rule",
  pluralLabel: "Analytics library",
  description: "Global detection-rule registry, seeded with 25 production rules. Read-only here.",
  readOnly: true,
  listColumns: [
    { key: "rule_code", label: "Code" },
    { key: "rule_name", label: "Name" },
    { key: "status", label: "Status" },
    { key: "subdomain", label: "Domain" },
  ],
  orderBy: { column: "rule_code", ascending: true },
  fields: [],
};

const alerts: ResourceConfig = {
  schema: "investigation",
  table: "alerts",
  slug: "alerts",
  label: "Alert",
  pluralLabel: "Alerts",
  description: "Grouped, reviewable case object generated from rule hits.",
  listColumns: [
    { key: "alert_title", label: "Title" },
    { key: "review_status", label: "Status" },
    { key: "aggregate_severity", label: "Severity" },
    { key: "created_at", label: "Raised" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
  ],
  updateFields: [
    { key: "review_status", label: "Status", type: "select", options: ALERT_REVIEW_STATUS },
    { key: "disposition", label: "Disposition", type: "select", options: ALERT_DISPOSITION },
  ],
};

const reports: ResourceConfig = {
  schema: "reporting",
  table: "reports",
  slug: "reports",
  label: "Report",
  pluralLabel: "Reports",
  description: "Court-ready report, traceable claim-by-claim back to evidence and findings.",
  listColumns: [
    { key: "title", label: "Title" },
    { key: "report_type", label: "Type" },
    { key: "status", label: "Status" },
    { key: "version", label: "Version" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "title", label: "Title", type: "text", required: true },
    {
      key: "report_type",
      label: "Report type",
      type: "select",
      required: true,
      options: REPORT_TYPE,
    },
    {
      key: "confidentiality",
      label: "Confidentiality",
      type: "select",
      options: CONFIDENTIALITY,
      defaultValue: "attorney_work_product",
    },
  ],
};

const auditEvents: ResourceConfig = {
  schema: "audit",
  table: "audit_events",
  slug: "audit-log",
  label: "Audit event",
  pluralLabel: "Audit log",
  description:
    "Append-only, hash-chained. Written only via audit.write() — never inserted directly.",
  readOnly: true,
  listColumns: [
    { key: "action", label: "Action" },
    { key: "entity_table", label: "Table" },
    { key: "created_at", label: "When" },
  ],
  orderBy: { column: "created_at" },
  fields: [],
};

const entityMatchCandidates: ResourceConfig = {
  schema: "identity",
  table: "entity_match_candidates",
  slug: "entity-matches",
  label: "Match candidate",
  pluralLabel: "Match review",
  description: "Fuzzy/shared-attribute matches between entities, pending review.",
  readOnly: true,
  listColumns: [
    { key: "candidate_type", label: "Type" },
    { key: "match_score", label: "Score" },
    { key: "review_status", label: "Status" },
  ],
  orderBy: { column: "match_score" },
  fields: [],
};

const validationResults: ResourceConfig = {
  schema: "quality",
  table: "validation_results",
  slug: "validation-results",
  label: "Validation result",
  pluralLabel: "Data readiness",
  description: "Row/table/dataset validation outcomes from the ingestion pipeline.",
  readOnly: true,
  listColumns: [
    { key: "result", label: "Result" },
    { key: "created_at", label: "Checked" },
  ],
  orderBy: { column: "created_at" },
  fields: [],
};

const mappingVersions: ResourceConfig = {
  schema: "mapping",
  table: "mapping_versions",
  slug: "mappings",
  label: "Mapping package",
  pluralLabel: "Data mapping library",
  description: "Source-system field-mapping packages (draft -> tested -> approved -> active).",
  readOnly: true,
  listColumns: [
    { key: "package_name", label: "Package" },
    { key: "target_table", label: "Target table" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "package_name", ascending: true },
  fields: [],
};

const calculationRuns: ResourceConfig = {
  schema: "calculations",
  table: "calculation_runs",
  slug: "calculation-runs",
  label: "Calculation run",
  pluralLabel: "Calculation history",
  description: "Damages/loss model executions against the seeded model catalog.",
  listColumns: [
    { key: "run_type", label: "Type" },
    { key: "status", label: "Status" },
    { key: "reporting_currency", label: "Currency" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "model_version_id",
      label: "Model version ID",
      type: "text",
      required: true,
      help: "UUID from the model catalog",
    },
  ],
};

const whistleblowerReports: ResourceConfig = {
  schema: "investigation",
  table: "whistleblower_reports",
  slug: "whistleblower-reports",
  label: "Report",
  pluralLabel: "Whistleblower reports",
  description: "Report body only — reporter identity is structurally separate and vault-encrypted.",
  listColumns: [
    { key: "report_code", label: "Code" },
    { key: "created_at", label: "Received" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
  ],
};

const appointments: ResourceConfig = {
  schema: "court",
  table: "appointments",
  slug: "appointments",
  label: "Appointment",
  pluralLabel: "Court authority",
  description: "Appointment orders, authority limits, and clause-level obligations.",
  listColumns: [
    { key: "appointment_type", label: "Type" },
    { key: "appointing_authority", label: "Authority" },
    { key: "order_date", label: "Order date" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "order_date" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "appointment_type", label: "Appointment type", type: "text", required: true },
    { key: "appointing_authority", label: "Appointing authority", type: "text" },
    { key: "order_date", label: "Order date", type: "date" },
    { key: "effective_date", label: "Effective date", type: "date" },
    { key: "order_text", label: "Order text", type: "textarea", required: true },
    { key: "authority_limits", label: "Authority limits", type: "textarea" },
    { key: "reporting_cadence", label: "Reporting cadence", type: "text" },
  ],
  updateFields: [
    { key: "order_text", label: "Order text", type: "textarea" },
    { key: "authority_limits", label: "Authority limits", type: "textarea" },
    { key: "reporting_cadence", label: "Reporting cadence", type: "text" },
    { key: "status", label: "Status", type: "text" },
  ],
};

const appointmentObligations: ResourceConfig = {
  schema: "court",
  table: "appointment_obligations",
  slug: "appointment-obligations",
  label: "Order obligation",
  pluralLabel: "Court obligations",
  description:
    "Parsed or practitioner-entered duties, limitations, deadlines, and completion evidence.",
  listColumns: [
    { key: "clause_number", label: "Clause" },
    { key: "clause_category", label: "Category" },
    { key: "clause_text", label: "Requirement" },
    { key: "due_date", label: "Due" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "due_date" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "appointment_id",
      label: "Appointment",
      type: "relation",
      required: true,
      relation: {
        schema: "court",
        table: "appointments",
        labelKey: "appointment_type",
        valueKey: "id",
        matterScoped: true,
      },
    },
    { key: "clause_number", label: "Clause", type: "text" },
    { key: "clause_category", label: "Category", type: "text", required: true },
    { key: "clause_text", label: "Requirement", type: "textarea", required: true },
    { key: "due_date", label: "Due date", type: "date" },
  ],
  updateFields: [
    { key: "due_date", label: "Due date", type: "date" },
    { key: "responsible_user_id", label: "Responsible user ID", type: "text" },
    { key: "status", label: "Status", type: "text" },
  ],
};

const claims: ResourceConfig = {
  schema: "claims",
  table: "claims",
  slug: "claims",
  label: "Claim",
  pluralLabel: "Claims administration",
  description:
    "Claim intake, deficiency review, eligibility, determination, appeal, and distribution lifecycle.",
  listColumns: [
    { key: "claim_number", label: "Claim" },
    { key: "claimant_name", label: "Claimant" },
    { key: "amount_claimed", label: "Amount" },
    { key: "eligibility_status", label: "Eligibility" },
    { key: "review_status", label: "Review" },
  ],
  orderBy: { column: "claim_number" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "claim_number", label: "Claim number", type: "text", required: true },
    { key: "claimant_name", label: "Claimant", type: "text", required: true },
    { key: "claim_type", label: "Claim type", type: "text" },
    { key: "amount_claimed", label: "Amount claimed", type: "number" },
    { key: "currency", label: "Currency", type: "text", defaultValue: "USD" },
  ],
  updateFields: [
    { key: "eligibility_status", label: "Eligibility", type: "text" },
    { key: "review_status", label: "Review status", type: "text" },
    { key: "deficiency_note", label: "Deficiency note", type: "textarea" },
  ],
};

const claimDeterminations: ResourceConfig = {
  schema: "claims",
  table: "claim_determinations",
  slug: "claim-determinations",
  label: "Claim determination",
  pluralLabel: "Claim decisions",
  description: "Reasoned allowance or denial with appeal deadline.",
  listColumns: [
    { key: "determination", label: "Determination" },
    { key: "allowed_amount", label: "Allowed" },
    { key: "status", label: "Status" },
    { key: "appeal_deadline", label: "Appeal deadline" },
  ],
  orderBy: { column: "created_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "claim_id",
      label: "Claim",
      type: "relation",
      required: true,
      relation: {
        schema: "claims",
        table: "claims",
        labelKey: "claim_number",
        valueKey: "id",
        matterScoped: true,
      },
    },
    { key: "determination", label: "Determination", type: "text", required: true },
    { key: "allowed_amount", label: "Allowed amount", type: "number" },
    { key: "currency", label: "Currency", type: "text", defaultValue: "USD" },
    { key: "rationale", label: "Rationale", type: "textarea" },
    { key: "appeal_deadline", label: "Appeal deadline", type: "date" },
  ],
  updateFields: [
    { key: "determination", label: "Determination", type: "text" },
    { key: "allowed_amount", label: "Allowed amount", type: "number" },
    { key: "rationale", label: "Rationale", type: "textarea" },
    { key: "status", label: "Status", type: "text" },
  ],
};

const claimDistributions: ResourceConfig = {
  schema: "claims",
  table: "distributions",
  slug: "claim-distributions",
  label: "Distribution",
  pluralLabel: "Distributions",
  description: "Scheduled and paid distributions tied to claims and determinations.",
  listColumns: [
    { key: "amount", label: "Amount" },
    { key: "scheduled_date", label: "Scheduled" },
    { key: "paid_date", label: "Paid" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "scheduled_date" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    {
      key: "claim_id",
      label: "Claim",
      type: "relation",
      required: true,
      relation: {
        schema: "claims",
        table: "claims",
        labelKey: "claim_number",
        valueKey: "id",
        matterScoped: true,
      },
    },
    { key: "amount", label: "Amount", type: "number", required: true },
    { key: "currency", label: "Currency", type: "text", defaultValue: "USD" },
    { key: "scheduled_date", label: "Scheduled date", type: "date" },
  ],
  updateFields: [
    { key: "paid_date", label: "Paid date", type: "date" },
    { key: "payment_reference", label: "Payment reference", type: "text" },
    { key: "status", label: "Status", type: "text" },
  ],
};

const interviews: ResourceConfig = {
  schema: "investigation",
  table: "interviews",
  slug: "interviews",
  label: "Interview",
  pluralLabel: "Interviews",
  description: "Plan interviews and preserve reviewed interview memoranda.",
  listColumns: [
    { key: "interviewee_name", label: "Interviewee" },
    { key: "interviewee_role", label: "Role" },
    { key: "interview_date", label: "Date" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "interview_date", ascending: false },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "interviewee_name", label: "Interviewee", type: "text", required: true },
    { key: "interviewee_role", label: "Role", type: "text" },
    { key: "interview_date", label: "Date and time", type: "text" },
    { key: "purpose", label: "Purpose", type: "textarea" },
    { key: "memorandum", label: "Interview memorandum", type: "textarea" },
  ],
  updateFields: [
    { key: "status", label: "Status", type: "text" },
    { key: "memorandum", label: "Interview memorandum", type: "textarea" },
  ],
};
const workpapers: ResourceConfig = {
  schema: "investigation",
  table: "workpapers",
  slug: "workpapers",
  label: "Workpaper",
  pluralLabel: "Workpapers",
  description:
    "Document objectives, procedures, analysis, linked support, conclusions, and review.",
  listColumns: [
    { key: "workpaper_number", label: "Number" },
    { key: "title", label: "Title" },
    { key: "status", label: "Status" },
    { key: "reviewed_at", label: "Reviewed" },
  ],
  orderBy: { column: "created_at", ascending: false },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "workpaper_number", label: "Workpaper number", type: "text", required: true },
    { key: "title", label: "Title", type: "text", required: true },
    { key: "objective", label: "Objective", type: "textarea" },
    { key: "procedure_text", label: "Procedures", type: "textarea" },
    { key: "analysis", label: "Analysis", type: "textarea" },
    { key: "conclusion", label: "Conclusion", type: "textarea" },
  ],
  updateFields: [
    { key: "status", label: "Status", type: "text" },
    { key: "analysis", label: "Analysis", type: "textarea" },
    { key: "conclusion", label: "Conclusion", type: "textarea" },
  ],
};
const timelineEvents: ResourceConfig = {
  schema: "investigation",
  table: "timeline_events",
  slug: "timeline",
  label: "Timeline event",
  pluralLabel: "Investigation timeline",
  description: "A sourced chronology of events, transactions, communications, and decisions.",
  listColumns: [
    { key: "occurred_at", label: "Occurred" },
    { key: "event_type", label: "Type" },
    { key: "title", label: "Event" },
    { key: "confidence", label: "Confidence" },
  ],
  orderBy: { column: "occurred_at", ascending: false },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "occurred_at", label: "Occurred at", type: "text", required: true },
    { key: "event_type", label: "Event type", type: "text", required: true },
    { key: "title", label: "Title", type: "text", required: true },
    { key: "description", label: "Description", type: "textarea" },
  ],
};
const exhibits: ResourceConfig = {
  schema: "reporting",
  table: "exhibits",
  slug: "exhibits",
  label: "Exhibit",
  pluralLabel: "Exhibits",
  description:
    "Prepare and approve evidentiary and calculation exhibits for reports or production.",
  listColumns: [
    { key: "exhibit_number", label: "Exhibit" },
    { key: "title", label: "Title" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "exhibit_number" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "exhibit_number", label: "Exhibit number", type: "text", required: true },
    { key: "title", label: "Title", type: "text", required: true },
    { key: "description", label: "Description", type: "textarea" },
  ],
  updateFields: [
    { key: "status", label: "Status", type: "text" },
    { key: "description", label: "Description", type: "textarea" },
  ],
};
const tasks: ResourceConfig = {
  schema: "workflow",
  table: "tasks",
  slug: "tasks",
  label: "Task",
  pluralLabel: "Tasks & deadlines",
  description: "Assignments, deadlines, approvals, and follow-up work for this matter.",
  listColumns: [
    { key: "title", label: "Task" },
    { key: "priority", label: "Priority" },
    { key: "due_at", label: "Due" },
    { key: "status", label: "Status" },
  ],
  orderBy: { column: "due_at" },
  fields: [
    { key: "tenant_id", label: "Tenant", type: "text", auto: "tenant_id" },
    { key: "matter_id", label: "Matter", type: "text", auto: "matter_id" },
    { key: "title", label: "Task", type: "text", required: true },
    { key: "description", label: "Description", type: "textarea" },
    {
      key: "priority",
      label: "Priority",
      type: "select",
      options: ["low", "medium", "high", "critical"].map((value) => ({ value, label: value })),
    },
    { key: "due_at", label: "Due at", type: "text" },
  ],
  updateFields: [
    { key: "status", label: "Status", type: "text" },
    { key: "priority", label: "Priority", type: "text" },
    { key: "due_at", label: "Due at", type: "text" },
  ],
};

export const primaryNav: NavGroup[] = [
  { label: "Matters", resources: [matters] },
  { label: "Evidence", resources: [evidenceItems, custodyEvents] },
  { label: "Financial", resources: [transactions, entities] },
  { label: "Investigation", resources: [allegations, leads, facts, findings] },
  { label: "Rules & Alerts", resources: [ruleDefinitions, alerts] },
  { label: "Reporting", resources: [reports] },
  {
    label: "Court & Claims",
    resources: [
      appointments,
      appointmentObligations,
      claims,
      claimDeterminations,
      claimDistributions,
    ],
  },
  { label: "Audit", resources: [auditEvents] },
  { label: "Casework", resources: [interviews, workpapers, timelineEvents, exhibits, tasks] },
];

export const adminNav: NavGroup[] = [
  {
    label: "Admin",
    resources: [
      entityMatchCandidates,
      validationResults,
      mappingVersions,
      calculationRuns,
      whistleblowerReports,
    ],
  },
];

export const allResources: ResourceConfig[] = [...primaryNav, ...adminNav].flatMap(
  (g) => g.resources,
);

export function findResourceBySlug(slug: string): ResourceConfig | undefined {
  return allResources.find((r) => r.slug === slug);
}
