# Forens_iQ product-flow coverage

Updated: 2026-08-18

This is the engineering acceptance map for the product flow. Status is based on executable database objects and reachable application surfaces, not planned capability.

Legend: `[UI/UX]` practitioner surface; `[BACK END]` governed system-of-record logic; `[BOTH]` user-triggered controlled workflow; `[SYSTEM]` automated processing; `[HUMAN APPROVAL]` preserved reviewer decision.

## End-to-end control spine

| Stage | Status | Implemented control and surface |
| --- | --- | --- |
| Matter and engagement intake `[BOTH]` | Operational | Four-step `/app/matters/new` wizard calls `core.provision_matter_intake`; creates engagement, modules, parties, authority, deadlines, retention posture, conflict attestation, access grant, and audit stamps atomically. |
| Authority extraction `[SYSTEM]` | Operational, deterministic parser v1 | `core.parse_authority_instrument` proposes categorized scope clauses, reporting obligations, and authority deadlines while preserving source text and parser metadata. It does not replace legal judgment. |
| Scope activation `[HUMAN APPROVAL]` | Operational | `/app/matters/{id}/authority` records immutable approve/reject/revision decisions. Approval freezes authority and scope snapshots with SHA-256 and activates the matter/modules. |
| Evidence intake/preservation `[BOTH]` | Operational | Upload, immutable original, SHA-256, custody event, file validation, extraction/OCR, entity extraction, working-copy editor, document preview, legal hold, forced RLS. |
| Data mapping/quality `[BOTH]` | Operational | Guided data-readiness workspace, dataset versions, mappings, normalization registry, validation results, reconciliation records, blocking exception enforcement, immutable approval attestations, and approved-for-analytics state. |
| Rule execution and alerts `[BOTH]` | Operational | Checksummed rule versions, governed execution RPC, parameters, manifests/hits, alert creation, review/disposition UI, audit trail. Production rule content still requires professional rule approval before reliance. |
| Practitioner casework `[BOTH]` | Operational | Interviews and memoranda, linked workpapers with approval gates, sourced investigation timeline, exhibits, and matter tasks/deadlines are first-class matter-scoped records. |
| Entity resolution `[BOTH]` | Operational | Weighted name/identifier/address/contact scoring, candidate review UI, accept/reject decisions, preserved feature snapshot. |
| Funds tracing and reconciliation `[BOTH]` | Operational | Transaction-leg graph, LIBR/FIFO/LIFO/netting schedules, invoice-to-payment reconciliation and exception storage, user-triggered analysis workspace. |
| Calculation models `[BOTH]` | Operational | Known loss, disgorgement, prejudgment interest and lost profits; frozen inputs, assumptions, schedules, sensitivity output, hashes, version/status controls, calculation workspace. Final model assumptions require expert approval. |
| Treasury governance `[BOTH]` | Operational | Source-backed command center, authority limits, access reviews, restricted funds, beneficiary changes, payment-control review, exception exposure, and bank-to-ledger reconciliation. |
| GRC and audit `[BOTH]` | Operational | Risk register, control matrix, audit programs, control tests, exception/monetary rates, residual-risk scoring, remediation generation, aging, evidence and review states. |
| Findings and reports `[BOTH]` | Operational | Template-led workspace, approved-source assembly, report sections, claim-to-source links, comments, approval gates, authenticated signatures, editions, immutable distribution ledger, DOCX/PDF/XLSX rendering and hashes. |
| Court/receiver/claims `[BOTH]` | Operational | Appointment extraction, obligation tracker, claims/determinations/distributions, contact registry, neutrality log, asset inventory, fee/expense review, deadlines and court-ready records. |
| Portfolio and module command centers `[UI/UX]` | Operational | The global Forens_iQ portfolio shows cross-matter metrics, continue-matter choices, and work-module selection. Fraud, Treasury, GRC, and Special Services each have a dedicated matter-scoped dashboard and consolidated secondary navigation. `analytics.v_matter_readiness`, `analytics.v_treasury_dashboard`, `analytics.v_grc_dashboard`, and governed module tables provide the metrics. |
| Job orchestration `[SYSTEM]` | Operational control plane | Durable job records, pgmq queues, priorities, leases, retries, exponential backoff, dead-letter state and administrative monitor. Native upload/OCR remains immediately executable as well as queue-addressable. |

## Non-negotiable control rules

- Tenant and matter isolation use forced row-level security on practitioner data.
- Originals, completed calculations, approval records, custody events and audit events are append-only or mutation-guarded.
- System extraction and scoring create proposals; professional conclusions require explicit human approval.
- Analytics readiness is represented by stored approval states, not inferred from file presence.
- Report assembly may use only governed records and must preserve source links and output hashes.
- Corrections create a new version/run/event; completed records are not silently overwritten.

## External dependencies

Bank feeds, ERP APIs, court e-filing, external timestamp authorities, malware engines, electronic-signature providers, email/SMS delivery, and production object-lock hardware require customer-selected endpoints and credentials. The platform provides governed connector/job/distribution records and fails closed when such a destination is not configured; it does not simulate a successful external action.

## Metric provenance

The Matter Command Center reads `analytics.v_matter_readiness`. Each metric is a direct count or existence check over matter-scoped system-of-record tables. Empty states mean no governed records were found; they are not converted to favorable status. The view runs with invoker security so underlying RLS remains authoritative.
