-- ============================================================================
-- Migration 0016: fix "Function Search Path Mutable" lint findings
--
-- Every function below was created without an explicit `set search_path`, so
-- Postgres resolves its unqualified references using whatever search_path the
-- calling session/role happens to have — role- and session-dependent, and
-- flagged by Supabase's database linter (function_search_path_mutable) on
-- every one of them, not just investigation.tg_finding_guard.
--
-- Fix applied: pin each function to `pg_catalog, pg_temp, <its own schema>`.
-- pg_catalog is always implicitly searched regardless, but listing it (plus
-- pg_temp) makes the path fixed rather than inherited, which is what the
-- linter actually checks for. The function's own schema is included because
-- every one of these already schema-qualifies cross-schema references (e.g.
-- extensions.digest(...), evidence.chain_of_custody_events) — the only thing
-- that relied on an ambient search_path was same-schema access, if any.
-- None of these are SECURITY DEFINER (those already set search_path — see
-- app.has_matter_access, audit.write, security.*, app.enqueue).
-- ============================================================================

alter function app.current_user_id() set search_path = pg_catalog, pg_temp, app;
alter function app.tg_stamp_row() set search_path = pg_catalog, pg_temp, app;
alter function app.tg_deny_mutation() set search_path = pg_catalog, pg_temp, app;
alter function app.tg_hash_chain() set search_path = pg_catalog, pg_temp, app;

alter function evidence.tg_coc_payload() set search_path = pg_catalog, pg_temp, evidence;
alter function evidence.compute_custody_root(p_from bigint, p_to bigint) set search_path = pg_catalog, pg_temp, evidence;

alter function investigation.tg_finding_guard() set search_path = pg_catalog, pg_temp, investigation;
alter function investigation.tg_alert_notify() set search_path = pg_catalog, pg_temp, investigation;

alter function rules.tg_version_checksum() set search_path = pg_catalog, pg_temp, rules;
alter function rules.tg_version_immutable() set search_path = pg_catalog, pg_temp, rules;

alter function audit.tg_audit_payload() set search_path = pg_catalog, pg_temp, audit;
alter function audit.compute_root(p_tenant uuid, p_from bigint, p_to bigint) set search_path = pg_catalog, pg_temp, audit;
alter function audit.verify_chain(p_tenant uuid) set search_path = pg_catalog, pg_temp, audit;

alter function calculations.tg_model_version_checksum() set search_path = pg_catalog, pg_temp, calculations;
alter function calculations.tg_model_version_lock() set search_path = pg_catalog, pg_temp, calculations;
alter function calculations.tg_scenario_guard() set search_path = pg_catalog, pg_temp, calculations;
alter function calculations.tg_run_guard() set search_path = pg_catalog, pg_temp, calculations;
alter function calculations.tg_assumption_guard() set search_path = pg_catalog, pg_temp, calculations;

alter function mapping.tg_enforce_version_lifecycle() set search_path = pg_catalog, pg_temp, mapping;
alter function staging.tg_protect_raw_payload() set search_path = pg_catalog, pg_temp, staging;

alter function analytics.detect_vendor_employee_address_matches(p_matter_id uuid, p_excluded_address_hashes text[])
  set search_path = pg_catalog, pg_temp, analytics, canonical, identity;
alter function analytics.detect_vendor_employee_bank_matches(p_matter_id uuid)
  set search_path = pg_catalog, pg_temp, analytics, canonical, identity;
alter function analytics.detect_duplicate_invoices(p_matter_id uuid, p_date_tolerance_days integer)
  set search_path = pg_catalog, pg_temp, analytics, canonical, identity;
