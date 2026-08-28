# ADR-0001 — Forens_iQ Release 1 Foundation

Status: Accepted (foundation slice)
Date: 2026-08-16
Context: Turning the "Dream Litigation / Fraud / Treasury Investigations" concept
into a buildable Supabase (PostgreSQL) schema, with the five defects from the
concept review fixed at the schema level rather than left as prose.

---

## The five decisions

### A. Tamper-evidence is enforced, not asserted
**Decision.** Chain-of-custody (`evidence.chain_of_custody_events`) and the audit
plane (`audit.audit_events`) are append-only (UPDATE/DELETE rejected by trigger)
and hash-chained: `chain_hash = sha256(payload_hash || prev_hash)`, one chain per
evidence item and one per tenant. Chain heads are periodically folded into a
`merkle_root` and lodged with an **external timestamp authority** (RFC-3161 TSA /
OpenTimestamps / Sigstore) recorded in `*.anchor_runs`.
**Why.** A hash chain living only inside the same database a DBA controls can be
rewritten row-and-proof together. External anchoring makes back-dating provably
impossible. `audit.verify_chain(tenant)` lets a regulator recompute the chain and
locate any break.
**Prod note.** Swap the linear fold for a true binary Merkle tree; run the
anchoring job (TSA POST) from an isolated worker, not from the DB.

### B. Tenant/matter isolation is membership-driven (pooler-safe)
**Decision.** RLS reads access from `core.matter_access` joined to `auth.uid()`
via `app.has_matter_access(matter, level)`. No `SET LOCAL app.matter_id` GUCs.
**Why.** Supabase's transaction-mode pooler does not preserve session GUCs, and a
settable variable is forgeable. Membership tied to the signed JWT subject is the
source of truth. Every matter-scoped table is `ENABLE` **and** `FORCE ROW LEVEL
SECURITY`, so even the table owner is subject to policy. `service_role`
(BYPASSRLS) is reserved for trusted ETL only; `anon` gets nothing.

### C. The platform operator is a threat, too
**Decision.** `FORCE ROW LEVEL SECURITY` everywhere; sensitive writes and audit
appends go through `SECURITY DEFINER` functions (`audit.write`, `security.*`) that
fix tenant/actor from context so a caller cannot forge scope; audit is immutable.
Whistleblower unsealing requires `approve` on the matter and always writes an
access-log row.
**Why.** The concept only defended the client's org against insiders; this defends
the record against a Forens_iQ admin.

### D. Erasure vs. immutability — crypto-shredding + residency
**Decision.** Raw bank numbers, tax IDs, and whistleblower identity are never
stored in business tables. They go to **Supabase Vault**; the table keeps only the
Vault key id + a deterministic **HMAC token** for matching. Legal destruction /
DSAR erasure = `security.shred(key_id, authority)` deletes the Vault secret; the
row, its hash, and the audit trail survive but the plaintext is unrecoverable.
`core.tenants.data_region` carries the residency anchor.
**Why.** Reconciles GDPR/CCPA/PHI erasure with an append-only, hash-anchored
evidence record. You can prove a value existed and was destroyed under stated
authority, without keeping the value.

### E. Whistleblower identity is structurally separated
**Decision.** Report body lives in `investigation.whistleblower_reports`
(matter-readable). Identity lives in `security.whistleblower_identities`
(Vault-encrypted), reachable only through `security.wb_reveal_identity(...)`,
which checks authority and logs every access in
`security.whistleblower_access_log`.
**Why.** Removes the retaliation-leak path created by pervasive audit + broad QC
access.

### Naming fix
Module prefix for Fraud eXamination artifacts is **`fe_`**. **`fx_` is reserved
for foreign-exchange columns only** (`fx_rate`, `fx_rate_source`). Kills the FX
collision.

### Idempotent ingestion
Canonical rows are unique by `(matter_id, source_dataset_version_id,
source_record_id)`; dataset versions unique by `(matter, source, raw_file_sha256)`.
Replaying an import cannot double-book a transaction, invoice, or payment.

---

## What this slice contains (migrations 0001–0011)
core tenancy + authority + access · security vault/tokenization/WB-vault ·
evidence vault + hash-chained custody + anchoring · canonical financial/entity
core · investigation object hierarchy (allegation→finding) + finding guard ·
rule registry + explainable hits + grouped alerts · reporting + claim
traceability · immutable audit plane + `verify_chain` · golden-thread views.

## Deliberately deferred (Release 2+)
Full graph/tracing engine (edge tables present; algorithms later) · calculation
engine tables (referenced by `report_claim_links.calculation_run_ref`) ·
sampling/MUS statistics · sanctions-list versioning · deployment/DR runbook ·
ABAC attribute catalog. These were called out in the review and are scheduled,
not forgotten.

## How to verify (once applied to a Supabase project)
1. Two users on different matters cannot see each other's rows (RLS).
2. `update`/`delete` on `audit.audit_events` or `chain_of_custody_events` raises.
3. `audit.verify_chain(tenant)` returns NULL (intact); tamper a row via a
   superuser and it returns the breaking seq.
4. `security.shred(key_id, 'court order #123')` makes `security.vault_get` return
   NULL while the row/hash remain.
