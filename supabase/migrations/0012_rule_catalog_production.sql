-- ============================================================================
-- Migration 0012: production rule catalog (parameter registry, population
-- registry, execution-engine enrichments, alert/review governance, required
-- test library, operational metrics) + the 25-rule minimum release catalog.
--
-- Extends migration 0008 (rules.rule_definitions, rules.rule_versions,
-- rules.rule_runs, analytics.rule_hits, investigation.alerts,
-- investigation.alert_hits) WITHOUT dropping or destructively altering those
-- tables — a seeded finding already references this registry live. Every
-- change to an 0008 table below is `add column if not exists`. Genuinely new
-- tables use plain `create table`.
--
-- Parameter binding convention: logic_sql bodies use named bind parameters
-- of the form `:parameter_name`, substituted by the execution engine from
-- rules.rule_runs.parameter_values (merged over rules.rule_versions
-- .default_parameters and validated against parameter_schema /
-- rules.rule_parameter_definitions) before the statement is prepared and run
-- read-only, under a least-privilege role, always bound to :tenant_id and
-- :matter_id. No freeform user SQL is ever accepted by the production engine
-- (spec §15).
--
-- Canonical-table note: this schema (0006) has not yet built dedicated
-- canonical.purchase_orders / contracts / receiving_records / journal-entry /
-- expense-claim / bank-user-access / control tables (see README "Not in this
-- slice" and ADR-0001 "Deliberately deferred"). Where the spec's rule needs
-- one of those objects, canonical.transactions.transaction_type
-- ('journal'|'payroll'|'claim'|...) or canonical.invoices is used as the
-- nearest real substitute and the rule's logic_sql is prefixed with a STUB
-- comment naming the canonical object it is standing in for. These rules are
-- still catalogued (status = 'draft') so the governance workflow and UI have
-- a real row to work with; their SQL should be revisited once the Release 2
-- canonical extension lands.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. rules.rule_definitions — governance columns the spec has that 0008 lacks
-- ---------------------------------------------------------------------------
alter table rules.rule_definitions
  add column if not exists subdomain        text,
  add column if not exists scheme_category  text,
  add column if not exists methodology_note text,
  add column if not exists severity_model   text,   -- static|formula|percentile|composite
  add column if not exists effective_from   timestamptz,
  add column if not exists effective_to     timestamptz,
  add column if not exists retired_reason   text;

create index on rules.rule_definitions(domain, status);

-- NOTE (deliberate, not a gap): the spec's constraint is
-- UNIQUE(rule_code, effective_from). 0008 already enforces the stricter
-- UNIQUE(rule_code) on a live table with a seeded reference. Loosening a live
-- uniqueness constraint is a destructive-adjacent change this migration will
-- not make; UNIQUE(rule_code) is left in place. A rule that needs a second
-- effective-dated era under the same code should get a new rule_code instead
-- until a deliberate follow-up migration widens this.

-- ---------------------------------------------------------------------------
-- 2. rules.rule_versions — contract/execution columns the spec has that 0008
--    lacks, plus the "never edit approved SQL in place" guard (spec §3.2).
-- ---------------------------------------------------------------------------
alter table rules.rule_versions
  add column if not exists input_contract       jsonb,
  add column if not exists output_contract      jsonb,
  add column if not exists execution_profile    jsonb,   -- timeout, memory, partitioning, schedule
  add column if not exists test_suite_reference uuid;

create index on rules.rule_versions(rule_id);

create or replace function rules.tg_version_immutable()
returns trigger language plpgsql as $$
begin
  if old.approval_status = 'approved' then
    raise exception
      'rule_versions % is approved and frozen — create a new version instead of modifying it',
      old.id
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

create trigger tg_90_immutable before update on rules.rule_versions
  for each row execute function rules.tg_version_immutable();

-- ---------------------------------------------------------------------------
-- 3. rules.rule_parameter_definitions — configurable-parameter registry,
--    one row per parameter per rule_version (spec §3.3). Global registry,
--    same governance tier as rule_definitions/rule_versions themselves.
-- ---------------------------------------------------------------------------
create table rules.rule_parameter_definitions (
  id                    uuid primary key default gen_random_uuid(),
  rule_version_id       uuid not null references rules.rule_versions(id),
  parameter_name        text not null,          -- e.g. amount_tolerance_pct
  display_name          text,
  data_type             text not null,          -- integer|decimal|date|enum|boolean|array|string
  required              boolean not null default true,
  default_value         jsonb,
  minimum_value         numeric(20,4),
  maximum_value         numeric(20,4),
  allowed_values        jsonb,
  validation_regex      text,
  unit                  text,                   -- dollars, days, percentage, count
  sensitivity_level     text not null default 'standard',  -- standard|controlled|high_risk
  business_description  text,
  parameter_group       text,                   -- time_window, threshold, risk, filtering
  display_order         integer not null default 0,
  created_at            timestamptz not null default now(),
  created_by            uuid,
  unique (rule_version_id, parameter_name)
);
create index on rules.rule_parameter_definitions(rule_version_id);

-- ---------------------------------------------------------------------------
-- 4. rules.rule_parameter_sets — engagement/tenant-specific overrides of the
--    version defaults (spec §3.3). matter_id nullable: null = tenant-wide
--    default set; populated = matter-specific override.
-- ---------------------------------------------------------------------------
create table rules.rule_parameter_sets (
  id                uuid primary key default gen_random_uuid(),
  rule_version_id   uuid not null references rules.rule_versions(id),
  tenant_id         uuid not null,
  matter_id         uuid references core.matters(id),
  name              text not null,               -- "Q3 Treasury Review"
  status            text not null default 'draft',  -- draft|approved|retired
  parameter_values  jsonb not null default '{}'::jsonb,
  justification     text,
  requested_by      uuid,
  approved_by       uuid,
  approved_at       timestamptz,
  effective_from    timestamptz not null default now(),
  effective_to      timestamptz,
  created_at        timestamptz not null default now(),
  created_by        uuid,
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  row_version       integer not null default 1
);
create index on rules.rule_parameter_sets(rule_version_id);
create index on rules.rule_parameter_sets(matter_id);

create trigger tg_stamp before insert or update on rules.rule_parameter_sets
  for each row execute function app.tg_stamp_row();

-- ---------------------------------------------------------------------------
-- 5. rules.population_definitions — "exactly which records can be tested"
--    (spec §3.4). Global registry like rule_definitions.
-- ---------------------------------------------------------------------------
create table rules.population_definitions (
  id                     uuid primary key default gen_random_uuid(),
  population_code        text not null,          -- e.g. AP_POSTED_INVOICES_USD
  population_name        text not null,
  domain                 text,
  population_sql         text not null,
  input_dataset_contract jsonb,
  inclusion_logic        text,
  exclusion_logic        text,
  grain                  text,                   -- transaction, invoice, payment, employee, vendor, journal_line
  expected_key           text,
  active                 boolean not null default true,
  owner_user_id          uuid,
  created_at             timestamptz not null default now(),
  created_by             uuid,
  updated_at             timestamptz not null default now(),
  updated_by             uuid,
  row_version            integer not null default 1,
  unique (population_code)
);

create trigger tg_stamp before insert or update on rules.population_definitions
  for each row execute function app.tg_stamp_row();

-- ---------------------------------------------------------------------------
-- 6. rules.population_snapshots — frozen, matter-scoped population captured
--    by every rule run (spec §3.4: "no rule run should execute on
--    unapproved or unreconciled population data...").
-- ---------------------------------------------------------------------------
create table rules.population_snapshots (
  id                    uuid primary key default gen_random_uuid(),
  population_id         uuid not null references rules.population_definitions(id),
  tenant_id             uuid not null,
  matter_id             uuid not null references core.matters(id),
  dataset_version_ids   jsonb,
  snapshot_sql_checksum bytea,
  record_count          bigint,
  amount_total          numeric(20,4),
  start_date            date,
  end_date              date,
  quality_status        text,                    -- passed|warning|failed
  reconciliation_id     uuid,
  created_at            timestamptz not null default now(),
  created_by            uuid
);
create index on rules.population_snapshots(matter_id);
create index on rules.population_snapshots(population_id);

-- ---------------------------------------------------------------------------
-- 7. rules.rule_runs — execution-engine enrichments (spec §7): error
--    capture, requester, elevated-control approval, worker identity, and
--    the parameter-set / population-snapshot pointers now that both tables
--    above exist.
-- ---------------------------------------------------------------------------
alter table rules.rule_runs
  add column if not exists parameter_set_id       uuid references rules.rule_parameter_sets(id),
  add column if not exists population_snapshot_id uuid references rules.population_snapshots(id),
  add column if not exists requested_by           uuid,
  add column if not exists alerts_created         bigint,
  add column if not exists execution_environment  text not null default 'production',  -- production|staging|test
  add column if not exists error_code             text,
  add column if not exists error_message          text,
  add column if not exists run_manifest_uri        text,
  add column if not exists approval_required        boolean not null default false,
  add column if not exists approved_by              uuid,
  add column if not exists completed_by_service      text;

-- ---------------------------------------------------------------------------
-- 8. rules.rule_run_metrics — per-execution performance/quality telemetry
--    (spec §7). One row per run.
-- ---------------------------------------------------------------------------
create table rules.rule_run_metrics (
  id                          uuid primary key default gen_random_uuid(),
  rule_run_id                 uuid not null references rules.rule_runs(id),
  tenant_id                   uuid not null,
  matter_id                   uuid not null references core.matters(id),
  duration_ms                 bigint,
  records_per_second          numeric(12,2),
  scan_bytes                  bigint,
  join_cardinality_warning    boolean not null default false,
  temp_storage_bytes          bigint,
  query_plan_hash             bytea,
  result_skew_ratio           numeric(8,4),
  cost_estimate                numeric(12,4),
  timeout_warning               boolean not null default false,
  error_count                    integer not null default 0,
  duplicate_hit_rate              numeric(6,4),
  null_field_rate                  numeric(6,4),
  alert_conversion_rate              numeric(6,4),
  closed_false_positive_rate           numeric(6,4),
  created_at                            timestamptz not null default now(),
  created_by                             uuid,
  unique (rule_run_id)
);
create index on rules.rule_run_metrics(matter_id);

-- ---------------------------------------------------------------------------
-- 9. rules.rule_test_cases / rule_test_results — required test library per
--    rule (spec §11): positive, negative, boundary, tolerance, null,
--    reversal, duplicate-source, currency, timezone, data-version,
--    performance, explainability, security. Global registry (test cases are
--    attached to a rule_version, not a matter); results are logged per run.
-- ---------------------------------------------------------------------------
create table rules.rule_test_cases (
  id               uuid primary key default gen_random_uuid(),
  rule_version_id  uuid not null references rules.rule_versions(id),
  test_type        text not null,     -- positive|negative|boundary|tolerance|null|reversal|
                                       -- duplicate_source|currency|timezone|data_version|
                                       -- performance|explainability|security
  test_name        text not null,
  description      text,
  fixture_sql      text,              -- builds the synthetic/representative test population
  expected_result  jsonb,             -- expected hit count / rows / explanation tokens
  required         boolean not null default true,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  unique (rule_version_id, test_type, test_name)
);
create index on rules.rule_test_cases(rule_version_id);

create table rules.rule_test_results (
  id                 uuid primary key default gen_random_uuid(),
  rule_test_case_id  uuid not null references rules.rule_test_cases(id),
  rule_version_id    uuid not null references rules.rule_versions(id),
  rule_run_id        uuid references rules.rule_runs(id),
  executed_at        timestamptz not null default now(),
  passed             boolean not null,
  actual_result      jsonb,
  failure_detail     text,
  executed_by        uuid,
  created_at         timestamptz not null default now()
);
create index on rules.rule_test_results(rule_version_id);
create index on rules.rule_test_results(rule_test_case_id);

-- ---------------------------------------------------------------------------
-- 10. analytics.rule_hits — output-contract columns the spec has that 0008
--     lacks: the rule (not just rule_version) pointer, the grouping key used
--     to form alerts, and the per-hit integrity hash.
-- ---------------------------------------------------------------------------
alter table analytics.rule_hits
  add column if not exists rule_id       uuid references rules.rule_definitions(id),
  add column if not exists hit_group_key text,
  add column if not exists hit_hash      bytea;

create index on analytics.rule_hits(rule_id);
create index on analytics.rule_hits(matter_id, hit_group_key);

-- ---------------------------------------------------------------------------
-- 11. investigation.alerts — grouping/case-formation columns the spec has
--     that 0008 lacks (spec §8: "alert_group_key = matter + primary
--     entity/object + time_window + risk_domain").
-- ---------------------------------------------------------------------------
alter table investigation.alerts
  add column if not exists alert_group_key       text,
  add column if not exists first_detected_at     timestamptz,
  add column if not exists last_detected_at      timestamptz,
  add column if not exists linked_rule_hit_count integer not null default 0,
  add column if not exists linked_rules          jsonb,
  add column if not exists priority              text;   -- P1|P2|P3|P4

create index on investigation.alerts(matter_id, alert_group_key);

-- ---------------------------------------------------------------------------
-- 12. investigation.alert_review_events — the review/decision governance log
--     (spec §17: required close-out fields). This is the missing piece next
--     to 0008's investigation.alerts: alerts carry current review_status /
--     disposition, this table carries the immutable history of how it got
--     there. Append-only (mirrors the audit-plane philosophy in 0010).
-- ---------------------------------------------------------------------------
create table investigation.alert_review_events (
  id                           uuid primary key default gen_random_uuid(),
  tenant_id                    uuid not null,
  matter_id                    uuid not null references core.matters(id),
  alert_id                     uuid not null references investigation.alerts(id),
  from_review_status           text,
  to_review_status             text not null,
  disposition                  text,   -- false_positive|explained_legitimate|data_quality_issue|
                                        -- policy_exception|control_deficiency|requires_monitoring|
                                        -- referred_to_counsel|linked_to_investigation|linked_to_finding|
                                        -- linked_to_remediation|referred_for_recovery|
                                        -- referred_for_regulatory_review
  reviewer_id                  uuid,
  review_explanation           text,
  evidence_reviewed            jsonb,
  related_workpapers           jsonb,
  control_issue_identified     boolean,
  future_monitoring_required   boolean,
  rule_adjustment_recommended  boolean,
  occurred_at                  timestamptz not null default now(),
  created_at                   timestamptz not null default now(),
  created_by                   uuid
);
create index on investigation.alert_review_events(matter_id, alert_id);

create trigger tg_deny_mutation before update or delete on investigation.alert_review_events
  for each row execute function app.tg_deny_mutation();

-- ---------------------------------------------------------------------------
-- 13. analytics.rule_operational_metrics — required operational metrics,
--     tracked per rule/matter/tenant/period (spec §12).
-- ---------------------------------------------------------------------------
create table analytics.rule_operational_metrics (
  id                              uuid primary key default gen_random_uuid(),
  tenant_id                       uuid not null,
  matter_id                       uuid not null references core.matters(id),
  rule_id                         uuid not null references rules.rule_definitions(id),
  period_start                    date not null,
  period_end                      date not null,
  records_tested                  bigint,
  hits_produced                   bigint,
  alerts_produced                 bigint,
  alerts_reviewed                 bigint,
  alerts_closed                   bigint,
  alerts_escalated                bigint,
  alerts_linked_to_investigation  bigint,
  alerts_linked_to_findings       bigint,
  false_positive_count            bigint,
  false_positive_rate             numeric(6,4),
  true_positive_rate              numeric(6,4),
  avg_time_to_triage_minutes      numeric(12,2),
  avg_time_to_close_minutes       numeric(12,2),
  dollar_exposure_identified      numeric(20,4),
  dollar_recovery_identified      numeric(20,4),
  data_quality_failure_rate       numeric(6,4),
  execution_time_ms               bigint,
  query_cost_estimate              numeric(12,4),
  analyst_override_frequency        numeric(6,4),
  parameter_override_frequency       numeric(6,4),
  created_at                          timestamptz not null default now(),
  created_by                           uuid,
  unique (rule_id, matter_id, period_start, period_end)
);
create index on analytics.rule_operational_metrics(matter_id, rule_id);

-- ---------------------------------------------------------------------------
-- 14. RLS — matter-scoped new tables get the same forced-RLS +
--     app.has_matter_access pattern as 0008.
-- ---------------------------------------------------------------------------
do $$
declare t text; tables text[] := array[
  'rules.population_snapshots','rules.rule_run_metrics',
  'investigation.alert_review_events','analytics.rule_operational_metrics'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;

-- rule_parameter_sets: matter_id is nullable (tenant-wide default sets have
-- no matter). Tenant-wide rows are readable by any authenticated user (same
-- convention as 0010's matter-nullable audit rows); only matter-scoped rows
-- can be inserted/updated by ordinary users, gated by contribute/review.
alter table rules.rule_parameter_sets enable row level security;
alter table rules.rule_parameter_sets force row level security;
create policy sel on rules.rule_parameter_sets for select to authenticated
  using (matter_id is null or app.has_matter_access(matter_id, 'read'));
create policy ins on rules.rule_parameter_sets for insert to authenticated
  with check (matter_id is not null and app.has_matter_access(matter_id, 'contribute'));
create policy upd on rules.rule_parameter_sets for update to authenticated
  using (matter_id is not null and app.has_matter_access(matter_id, 'review'))
  with check (matter_id is not null and app.has_matter_access(matter_id, 'review'));
create policy all_sr on rules.rule_parameter_sets for all to service_role
  using (true) with check (true);

-- Global registry tables (not matter-scoped): read-only to any authenticated
-- user, full access to service_role — same tier as 0008's rule_definitions /
-- rule_versions.
alter table rules.rule_parameter_definitions enable row level security;
alter table rules.population_definitions     enable row level security;
alter table rules.rule_test_cases            enable row level security;
alter table rules.rule_test_results          enable row level security;

create policy sel on rules.rule_parameter_definitions for select to authenticated using (true);
create policy sel on rules.population_definitions     for select to authenticated using (true);
create policy sel on rules.rule_test_cases            for select to authenticated using (true);
create policy sel on rules.rule_test_results          for select to authenticated using (true);

create policy all_sr on rules.rule_parameter_definitions for all to service_role using (true) with check (true);
create policy all_sr on rules.population_definitions     for all to service_role using (true) with check (true);
create policy all_sr on rules.rule_test_cases            for all to service_role using (true) with check (true);
create policy all_sr on rules.rule_test_results          for all to service_role using (true) with check (true);

-- ============================================================================
-- 15. Minimum release rule catalog (spec §19) — 25 rules, seeded as
--     status = 'draft' / approval_status = 'draft' (no rule ships approved
--     without a real owner + QC sign-off; this only makes the catalog rows
--     exist so the governance workflow has something to move through Unit
--     Tested -> Peer Reviewed -> UAT -> Approved).
-- ============================================================================
do $$
declare
  v_rule_id    uuid;
  v_version_id uuid;
begin

  -- 1. AP_DUPLICATE_INVOICE_V1 ------------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_DUPLICATE_INVOICE_V1','Duplicate Invoice Detection','AP','invoice','fraud','billing_scheme',
    'Detects invoices that appear to have been entered more than once and may have resulted in duplicate payment.',
    'Duplicate entry of the same invoice is a common billing-scheme and control-failure pattern that produces direct overpayment exposure.',
    'Deterministic match on vendor, normalized invoice number, amount tolerance, and date window. Does not by itself prove intent — see false-positive guidance.',
    'deterministic','formula','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_DUPLICATE_INVOICE_V1 — exact/normalized duplicate invoice detection.
-- required params: :tenant_id, :matter_id, :lookback_days, :amount_tolerance_pct,
--                   :invoice_date_tolerance_days, :exclude_voided,
--                   :exclude_credit_memos, :minimum_amount,
--                   :match_invoice_number_normalized
select
  i1.id as invoice_id_a, i2.id as invoice_id_b,
  i1.vendor_id,
  i1.invoice_number_normalized,
  i1.invoice_date as invoice_date_a, i2.invoice_date as invoice_date_b,
  i1.amount_original as amount_a, i2.amount_original as amount_b,
  i1.currency_original,
  i1.invoice_status as status_a, i2.invoice_status as status_b,
  i1.source_evidence_id as evidence_id_a, i2.source_evidence_id as evidence_id_b,
  concat_ws('|', i1.vendor_id, i1.invoice_number_normalized) as duplicate_group_key
from canonical.invoices i1
join canonical.invoices i2
  on i2.matter_id = i1.matter_id
 and i2.vendor_id = i1.vendor_id
 and i2.id > i1.id
 and (not :match_invoice_number_normalized
      or i2.invoice_number_normalized = i1.invoice_number_normalized)
 and abs(i2.amount_original - i1.amount_original)
       <= i1.amount_original * (:amount_tolerance_pct / 100.0)
 and abs(i2.invoice_date - i1.invoice_date) <= :invoice_date_tolerance_days
where i1.tenant_id = :tenant_id
  and i1.matter_id = :matter_id
  and i1.record_status = 'active' and i2.record_status = 'active'
  and i1.invoice_date >= (current_date - (:lookback_days || ' days')::interval)
  and i1.amount_original >= :minimum_amount
  and (not :exclude_voided or (i1.invoice_status <> 'voided' and i2.invoice_status <> 'voided'))
  and (not :exclude_credit_memos or (i1.invoice_status <> 'credit_memo' and i2.invoice_status <> 'credit_memo'));
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"amount_tolerance_pct":{"type":"decimal","min":0,"max":5},"invoice_date_tolerance_days":{"type":"integer","min":0,"max":90},"exclude_voided":{"type":"boolean"},"exclude_credit_memos":{"type":"boolean"},"minimum_amount":{"type":"decimal","min":0},"match_invoice_number_normalized":{"type":"boolean"}}'::jsonb,
    '{"lookback_days":365,"amount_tolerance_pct":0.00,"invoice_date_tolerance_days":0,"exclude_voided":true,"exclude_credit_memos":true,"minimum_amount":1.00,"match_invoice_number_normalized":true}'::jsonb,
    '{"required_tables":["canonical.invoices"],"required_fields":["vendor_id","invoice_number_normalized","invoice_date","amount_original","currency_original","invoice_status","source_evidence_id"]}'::jsonb,
    '{"fields":["invoice_id_a","invoice_id_b","vendor_id","invoice_number_normalized","amount_a","amount_b","duplicate_group_key"]}'::jsonb,
    '{"timeout_seconds":300,"partitioning":"matter_id,invoice_date","schedule":"nightly"}'::jsonb,
    'Invoices {{invoice_id_a}} and {{invoice_id_b}} for vendor {{vendor_id}} share normalized invoice number {{invoice_number_normalized}} with amounts within {{amount_tolerance_pct}}% and dates within {{invoice_date_tolerance_days}} days.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 2. AP_NEAR_DUPLICATE_INVOICE_V1 -------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_NEAR_DUPLICATE_INVOICE_V1','Near-Duplicate Invoice Detection','AP','invoice','fraud','billing_scheme',
    'Detects invoices with a fuzzy-matching invoice number, same vendor, and similar amount/date that may be re-keyed duplicates.',
    'Practitioners often see the same invoice re-entered with a typo, suffix, or reformatted number rather than an exact match.',
    'Trigram similarity (pg_trgm) on the raw invoice number, bounded by an amount tolerance and date window; a similarity score is reported for reviewer judgment.',
    'fuzzy_match','formula','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_NEAR_DUPLICATE_INVOICE_V1 — fuzzy duplicate invoice detection.
-- required params: :tenant_id, :matter_id, :lookback_days, :fuzzy_threshold,
--                   :amount_tolerance_pct, :date_window_days
select
  i1.id as invoice_id_a, i2.id as invoice_id_b, i1.vendor_id,
  i1.invoice_number_raw as invoice_number_a, i2.invoice_number_raw as invoice_number_b,
  extensions.similarity(i1.invoice_number_raw, i2.invoice_number_raw) as similarity_score,
  i1.amount_original as amount_a, i2.amount_original as amount_b,
  i1.invoice_date as invoice_date_a, i2.invoice_date as invoice_date_b
from canonical.invoices i1
join canonical.invoices i2
  on i2.matter_id = i1.matter_id
 and i2.vendor_id = i1.vendor_id
 and i2.id > i1.id
 and extensions.similarity(i1.invoice_number_raw, i2.invoice_number_raw) >= :fuzzy_threshold
 and abs(i2.amount_original - i1.amount_original) <= i1.amount_original * (:amount_tolerance_pct / 100.0)
 and abs(i2.invoice_date - i1.invoice_date) <= :date_window_days
where i1.tenant_id = :tenant_id
  and i1.matter_id = :matter_id
  and i1.record_status = 'active' and i2.record_status = 'active'
  and i1.invoice_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"fuzzy_threshold":{"type":"decimal","min":0,"max":1},"amount_tolerance_pct":{"type":"decimal","min":0,"max":10},"date_window_days":{"type":"integer","min":0,"max":90}}'::jsonb,
    '{"lookback_days":365,"fuzzy_threshold":0.65,"amount_tolerance_pct":1.00,"date_window_days":10}'::jsonb,
    '{"required_tables":["canonical.invoices"],"required_fields":["vendor_id","invoice_number_raw","invoice_date","amount_original"],"required_extensions":["pg_trgm"]}'::jsonb,
    '{"fields":["invoice_id_a","invoice_id_b","vendor_id","similarity_score","amount_a","amount_b"]}'::jsonb,
    '{"timeout_seconds":600,"partitioning":"matter_id,invoice_date","schedule":"nightly"}'::jsonb,
    'Invoices {{invoice_number_a}} and {{invoice_number_b}} for vendor {{vendor_id}} are {{similarity_score}} similar with amounts and dates within tolerance.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 3. AP_DUPLICATE_PAYMENT_V1 -------------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_DUPLICATE_PAYMENT_V1','Duplicate Payment Detection','AP','payment','fraud','billing_scheme',
    'Detects an invoice that was paid more than once.',
    'Duplicate disbursement against the same invoice is a direct cash-loss exposure regardless of intent.',
    'Groups payments by shared invoice via payment_invoice_links; flags groups of 2+ payments within an amount/date tolerance.',
    'deterministic','formula','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_DUPLICATE_PAYMENT_V1 — same invoice paid more than once.
-- required params: :tenant_id, :matter_id, :lookback_days, :amount_tolerance_pct, :date_window_days
select
  pil1.invoice_id,
  p1.id as payment_id_a, p2.id as payment_id_b,
  p1.amount_original as amount_a, p2.amount_original as amount_b,
  p1.payment_date as payment_date_a, p2.payment_date as payment_date_b,
  p1.payment_reference as reference_a, p2.payment_reference as reference_b
from canonical.payment_invoice_links pil1
join canonical.payment_invoice_links pil2
  on pil2.invoice_id = pil1.invoice_id and pil2.payment_id > pil1.payment_id
join canonical.payments p1 on p1.id = pil1.payment_id
join canonical.payments p2 on p2.id = pil2.payment_id
where p1.tenant_id = :tenant_id
  and p1.matter_id = :matter_id
  and p1.record_status = 'active' and p2.record_status = 'active'
  and abs(p2.amount_original - p1.amount_original) <= p1.amount_original * (:amount_tolerance_pct / 100.0)
  and abs(p2.payment_date - p1.payment_date) <= :date_window_days
  and p1.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"amount_tolerance_pct":{"type":"decimal","min":0,"max":5},"date_window_days":{"type":"integer","min":0,"max":180}}'::jsonb,
    '{"lookback_days":365,"amount_tolerance_pct":0.00,"date_window_days":90}'::jsonb,
    '{"required_tables":["canonical.payments","canonical.payment_invoice_links"],"required_fields":["payment_reference","payment_date","amount_original"]}'::jsonb,
    '{"fields":["invoice_id","payment_id_a","payment_id_b","amount_a","amount_b"]}'::jsonb,
    '{"timeout_seconds":300,"partitioning":"matter_id,payment_date","schedule":"nightly"}'::jsonb,
    'Invoice {{invoice_id}} was paid by both {{reference_a}} and {{reference_b}} within {{date_window_days}} days.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 4. AP_VENDOR_BANK_CHANGE_PRE_PAYMENT_V1 ------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_VENDOR_BANK_CHANGE_PRE_PAYMENT_V1','Vendor Bank Change Before Payment','AP','vendor_master','fraud','vendor_master_manipulation',
    'Detects a payment released shortly after a vendor''s bank account details were changed.',
    'A classic vendor-impersonation / business-email-compromise indicator: divert funds by changing payment instructions just before a scheduled payment.',
    'Uses canonical.vendor_bank_accounts.change_event_at as the instruction-change signal, joined to the payment that used the changed beneficiary account.',
    'deterministic','formula','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_VENDOR_BANK_CHANGE_PRE_PAYMENT_V1 — bank details changed shortly before payment.
-- required params: :tenant_id, :matter_id, :lookback_days, :change_lookback_days, :amount_threshold
select
  p.id as payment_id, p.beneficiary_entity_id, vba.vendor_id,
  vba.change_event_at as bank_change_at, p.payment_date, p.amount_original,
  (p.payment_date - vba.change_event_at::date) as days_since_change
from canonical.payments p
join canonical.vendor_bank_accounts vba
  on vba.bank_account_id = p.beneficiary_account_id
 and vba.matter_id = p.matter_id
where p.tenant_id = :tenant_id
  and p.matter_id = :matter_id
  and p.record_status = 'active'
  and vba.change_event_at is not null
  and p.payment_date >= vba.change_event_at::date
  and (p.payment_date - vba.change_event_at::date) <= :change_lookback_days
  and p.amount_original >= :amount_threshold
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"change_lookback_days":{"type":"integer","min":1,"max":180},"amount_threshold":{"type":"decimal","min":0}}'::jsonb,
    '{"lookback_days":365,"change_lookback_days":14,"amount_threshold":10000.00}'::jsonb,
    '{"required_tables":["canonical.payments","canonical.vendor_bank_accounts"],"required_fields":["beneficiary_account_id","change_event_at","payment_date","amount_original"]}'::jsonb,
    '{"fields":["payment_id","vendor_id","bank_change_at","payment_date","days_since_change","amount_original"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id,payment_date","schedule":"near_real_time"}'::jsonb,
    'Payment {{payment_id}} of {{amount_original}} was released {{days_since_change}} day(s) after vendor {{vendor_id}}''s bank details changed.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 5. TREASURY_NEW_BENEFICIARY_HIGH_VALUE_PAYMENT_V1 --------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_NEW_BENEFICIARY_HIGH_VALUE_PAYMENT_V1','Payment to Newly Added Beneficiary','treasury','wire','fraud','bec',
    'Detects high-value payments made soon after a beneficiary account is added or modified.',
    'Business-email-compromise and payment-diversion schemes typically release a large payment within days of adding or changing the beneficiary.',
    'Reads analytics.v_payment_360 (0011), which already resolves beneficiary bank-change timing and the initiator/approver conflict flag.',
    'deterministic','composite','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_NEW_BENEFICIARY_HIGH_VALUE_PAYMENT_V1 — new/changed beneficiary + high value.
-- required params: :matter_id, :new_beneficiary_days, :high_value_amount
select
  v.payment_id, v.payment_reference, v.payment_date, v.amount_original, v.currency_original,
  v.beneficiary_name, v.beneficiary_bank_changed_at,
  (v.payment_date - v.beneficiary_bank_changed_at::date) as beneficiary_age_days,
  v.initiator_user_ref, v.approver_user_ref, v.releaser_user_ref,
  v.initiator_equals_approver, v.from_restricted_cash
from analytics.v_payment_360 v
where v.matter_id = :matter_id
  and v.beneficiary_bank_changed_at is not null
  and (v.payment_date - v.beneficiary_bank_changed_at::date) <= :new_beneficiary_days
  and v.amount_original >= :high_value_amount;
    $sql$,
    '{"new_beneficiary_days":{"type":"integer","min":1,"max":180},"high_value_amount":{"type":"decimal","min":0},"base_currency":{"type":"string"},"after_hours_bonus_points":{"type":"integer"},"weekend_bonus_points":{"type":"integer"},"approval_exception_bonus_points":{"type":"integer"}}'::jsonb,
    '{"new_beneficiary_days":14,"high_value_amount":50000.00,"base_currency":"USD","after_hours_bonus_points":10,"weekend_bonus_points":10,"approval_exception_bonus_points":20}'::jsonb,
    '{"required_views":["analytics.v_payment_360"],"required_fields":["payment_reference","payment_date","amount_original","beneficiary_bank_changed_at"]}'::jsonb,
    '{"fields":["payment_id","beneficiary_age_days","amount_original","initiator_equals_approver","from_restricted_cash"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"near_real_time"}'::jsonb,
    'A {{amount_original}} payment ({{payment_reference}}) was released {{beneficiary_age_days}} day(s) after beneficiary {{beneficiary_name}} was added or changed.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 6. TREASURY_INITIATOR_APPROVER_CONFLICT_V1 ---------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_INITIATOR_APPROVER_CONFLICT_V1','Same Initiator and Approver','treasury','payment_workflow','control_failure','sod_conflict',
    'Detects a payment where the same person is recorded as both initiator and approver.',
    'Segregation-of-duties breach: one person controlling both initiation and approval removes the independent check the workflow exists to provide.',
    'Direct equality test on canonical.payments.initiator_user_ref / approver_user_ref.',
    'deterministic','static','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_INITIATOR_APPROVER_CONFLICT_V1 — same person initiates and approves.
-- required params: :tenant_id, :matter_id, :lookback_days
select p.id as payment_id, p.payment_reference, p.payment_date, p.amount_original,
       p.initiator_user_ref, p.approver_user_ref
from canonical.payments p
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and p.initiator_user_ref is not null
  and p.initiator_user_ref = p.approver_user_ref
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.payments"],"required_fields":["initiator_user_ref","approver_user_ref"]}'::jsonb,
    '{"fields":["payment_id","initiator_user_ref","approver_user_ref"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"nightly"}'::jsonb,
    'Payment {{payment_id}} was both initiated and approved by {{initiator_user_ref}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 7. TREASURY_APPROVAL_LIMIT_EXCEEDED_V1 -------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_APPROVAL_LIMIT_EXCEEDED_V1','Payment Exceeds Approver Authority','treasury','payment_workflow','control_failure','authority_override',
    'Detects a payment that exceeds the approving user''s authorized limit.',
    'Authority-matrix breach exposes the organization to unauthorized disbursement outside its own control framework.',
    'STUB: canonical.payment_approvals / a per-role authority matrix is not yet modeled (Release 2). Approximated with a single flat matter-configured ceiling parameter until per-approver limits exist.',
    'deterministic','formula','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_APPROVAL_LIMIT_EXCEEDED_V1 — payment exceeds approver authority.
-- STUB: no canonical.payment_approvals / authority-matrix table exists yet;
-- approximates a single flat authority ceiling via parameter.
-- required params: :tenant_id, :matter_id, :approver_authority_limit, :tolerance_pct, :lookback_days
select p.id as payment_id, p.payment_reference, p.approver_user_ref, p.amount_original,
       :approver_authority_limit::numeric as permitted_limit,
       (p.amount_original - :approver_authority_limit::numeric) as variance
from canonical.payments p
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and p.amount_original > :approver_authority_limit::numeric * (1 + :tolerance_pct / 100.0)
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"approver_authority_limit":{"type":"decimal","min":0},"tolerance_pct":{"type":"decimal","min":0,"max":20},"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"approver_authority_limit":100000.00,"tolerance_pct":0.00,"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.payments"],"required_fields":["approver_user_ref","amount_original"],"deferred_objects":["canonical.payment_approvals","authority_matrix"]}'::jsonb,
    '{"fields":["payment_id","approver_user_ref","amount_original","permitted_limit","variance"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"nightly"}'::jsonb,
    'Payment {{payment_id}} of {{amount_original}} exceeds the {{permitted_limit}} authority ceiling by {{variance}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 8. TREASURY_MISSING_REQUIRED_APPROVAL_V1 -----------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_MISSING_REQUIRED_APPROVAL_V1','Missing Required Payment Approval','treasury','payment_workflow','control_failure','authority_override',
    'Detects a payment released with no recorded approver.',
    'A payment with no approval on record has bypassed the control the workflow is designed to enforce.',
    'Null test on canonical.payments.approver_user_ref.',
    'deterministic','static','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_MISSING_REQUIRED_APPROVAL_V1 — required approval absent.
-- required params: :tenant_id, :matter_id, :lookback_days
select p.id as payment_id, p.payment_reference, p.payment_date, p.amount_original,
       p.approver_user_ref
from canonical.payments p
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and p.approver_user_ref is null
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.payments"],"required_fields":["approver_user_ref"]}'::jsonb,
    '{"fields":["payment_id","payment_reference","amount_original"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"near_real_time"}'::jsonb,
    'Payment {{payment_id}} ({{payment_reference}}) has no recorded approver.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 9. TREASURY_AFTER_HOURS_PAYMENT_V1 -----------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_AFTER_HOURS_PAYMENT_V1','After-Hours Payment','treasury','payment_timing','operational_risk','after_hours_activity',
    'Detects a payment released outside the matter''s normal business hours.',
    'Fraudulent and rushed payments are disproportionately released outside normal hours to avoid scrutiny.',
    'Uses canonical.payments.created_at (the record-creation timestamp) converted to matter local time as a proxy for release time, since no dedicated payment-release timestamp exists yet.',
    'deterministic','static','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_AFTER_HOURS_PAYMENT_V1 — payment outside approved hours.
-- required params: :tenant_id, :matter_id, :matter_timezone, :start_hour_local, :cutoff_hour_local, :lookback_days
select p.id as payment_id, p.payment_reference,
       (p.created_at at time zone :matter_timezone) as payment_local_ts,
       extract(hour from (p.created_at at time zone :matter_timezone)) as payment_hour_local
from canonical.payments p
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and (extract(hour from (p.created_at at time zone :matter_timezone)) >= :cutoff_hour_local
       or extract(hour from (p.created_at at time zone :matter_timezone)) < :start_hour_local)
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"matter_timezone":{"type":"string"},"start_hour_local":{"type":"integer","min":0,"max":23},"cutoff_hour_local":{"type":"integer","min":0,"max":23},"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"matter_timezone":"UTC","start_hour_local":7,"cutoff_hour_local":19,"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.payments"],"required_fields":["created_at","payment_date"]}'::jsonb,
    '{"fields":["payment_id","payment_local_ts","payment_hour_local"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"near_real_time"}'::jsonb,
    'Payment {{payment_id}} was recorded at local hour {{payment_hour_local}}, outside the {{start_hour_local}}-{{cutoff_hour_local}} business window.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 10. TREASURY_WEEKEND_HOLIDAY_PAYMENT_V1 ------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_WEEKEND_HOLIDAY_PAYMENT_V1','Weekend or Holiday Payment','treasury','payment_timing','operational_risk','after_hours_activity',
    'Detects a payment posted on a weekend or a matter-configured holiday.',
    'Payments outside the normal business calendar are a recognized timing indicator for rushed or unauthorized disbursements.',
    'ISO day-of-week test plus a parameter-supplied holiday-date list (no shared holiday-calendar table exists yet).',
    'deterministic','static','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_WEEKEND_HOLIDAY_PAYMENT_V1 — payment on nonbusiness day.
-- required params: :tenant_id, :matter_id, :lookback_days, :holiday_dates (jsonb array of ISO dates)
select p.id as payment_id, p.payment_reference, p.payment_date,
       extract(isodow from p.payment_date) as iso_day_of_week
from canonical.payments p
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and (extract(isodow from p.payment_date) in (6,7)
       or p.payment_date::text in (select jsonb_array_elements_text(:holiday_dates::jsonb)))
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"holiday_dates":{"type":"array"}}'::jsonb,
    '{"lookback_days":365,"holiday_dates":[]}'::jsonb,
    '{"required_tables":["canonical.payments"],"required_fields":["payment_date"]}'::jsonb,
    '{"fields":["payment_id","payment_date","iso_day_of_week"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"nightly"}'::jsonb,
    'Payment {{payment_id}} posted on {{payment_date}}, a nonbusiness day.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 11. TREASURY_UNRECONCILED_ITEM_AGING_V1 ------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_UNRECONCILED_ITEM_AGING_V1','Aged Unreconciled Item','treasury','reconciliation','operational_risk','control_gap',
    'Detects a transaction that remains unreconciled beyond an aging threshold.',
    'Aged unreconciled items can mask misappropriation, error, or a broken control and grow harder to resolve the longer they sit.',
    'STUB: no dedicated bank-reconciliation-item table exists yet; approximated via canonical.transactions with no linked transaction_legs recorded.',
    'deterministic','static','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_UNRECONCILED_ITEM_AGING_V1 — aged reconciliation item.
-- STUB: no canonical.reconciliation_items table exists yet; approximates
-- aging via transactions with no reconciling leg recorded.
-- required params: :tenant_id, :matter_id, :aging_days, :materiality_amount
select t.id as transaction_id, t.reference_number, t.amount_original, t.transaction_date,
       (current_date - t.transaction_date) as age_days
from canonical.transactions t
where t.tenant_id = :tenant_id and t.matter_id = :matter_id
  and t.record_status = 'active'
  and not exists (select 1 from canonical.transaction_legs l where l.transaction_id = t.id)
  and (current_date - t.transaction_date) >= :aging_days
  and t.amount_original >= :materiality_amount;
    $sql$,
    '{"aging_days":{"type":"integer","min":1,"max":730},"materiality_amount":{"type":"decimal","min":0}}'::jsonb,
    '{"aging_days":30,"materiality_amount":1000.00}'::jsonb,
    '{"required_tables":["canonical.transactions","canonical.transaction_legs"],"deferred_objects":["canonical.reconciliation_items"]}'::jsonb,
    '{"fields":["transaction_id","reference_number","amount_original","age_days"]}'::jsonb,
    '{"timeout_seconds":300,"partitioning":"matter_id,transaction_date","schedule":"weekly"}'::jsonb,
    'Transaction {{transaction_id}} ({{reference_number}}) has been unreconciled for {{age_days}} days.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 12. TREASURY_RESTRICTED_CASH_MISUSE_V1 -------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'TREASURY_RESTRICTED_CASH_MISUSE_V1','Restricted Cash Misuse','treasury','restricted_funds','compliance','fund_misappropriation',
    'Detects a payment drawn from a restricted-cash account for a purpose outside its permitted use.',
    'Restricted, escrow, and trust funds carry fiduciary and often legal obligations; disbursing them outside their designated purpose is a compliance and fraud exposure.',
    'Filters canonical.bank_accounts.is_restricted and compares account_class against a matter-configured allow-list.',
    'deterministic','static','treasury_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- TREASURY_RESTRICTED_CASH_MISUSE_V1 — restricted fund used outside purpose.
-- required params: :tenant_id, :matter_id, :lookback_days, :allowed_account_classes (jsonb array)
select p.id as payment_id, p.payment_reference, p.amount_original, ba.id as account_id,
       ba.account_class, ba.is_restricted
from canonical.payments p
join canonical.bank_accounts ba on ba.id = p.from_account_id
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and ba.is_restricted = true
  and not (ba.account_class = any (
      select jsonb_array_elements_text(:allowed_account_classes::jsonb)))
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"allowed_account_classes":{"type":"array"}}'::jsonb,
    '{"lookback_days":365,"allowed_account_classes":["escrow","trust"]}'::jsonb,
    '{"required_tables":["canonical.payments","canonical.bank_accounts"],"required_fields":["is_restricted","account_class","from_account_id"]}'::jsonb,
    '{"fields":["payment_id","account_id","account_class","amount_original"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"near_real_time"}'::jsonb,
    'Payment {{payment_id}} of {{amount_original}} was drawn from restricted account {{account_id}} classified as {{account_class}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 13. AP_VENDOR_SHARED_BANK_ACCOUNT_V1 ---------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_VENDOR_SHARED_BANK_ACCOUNT_V1','Shared Vendor Bank Account','AP','vendor_master','fraud','shell_vendor',
    'Detects multiple vendor master records that pay to the same bank account.',
    'Unrelated vendors sharing a bank account is a classic shell-vendor / fictitious-vendor indicator.',
    'Groups canonical.vendor_bank_accounts by bank_account_id and flags groups with 2+ distinct vendors.',
    'deterministic','static','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_VENDOR_SHARED_BANK_ACCOUNT_V1 — multiple vendors share bank account.
-- required params: :tenant_id, :matter_id, :minimum_vendor_count
select vba.bank_account_id, ba.account_token,
       array_agg(distinct vba.vendor_id) as vendor_ids,
       count(distinct vba.vendor_id) as vendor_count
from canonical.vendor_bank_accounts vba
join canonical.bank_accounts ba on ba.id = vba.bank_account_id
where vba.tenant_id = :tenant_id and vba.matter_id = :matter_id
  and vba.record_status = 'active'
group by vba.bank_account_id, ba.account_token
having count(distinct vba.vendor_id) >= :minimum_vendor_count;
    $sql$,
    '{"minimum_vendor_count":{"type":"integer","min":2,"max":10}}'::jsonb,
    '{"minimum_vendor_count":2}'::jsonb,
    '{"required_tables":["canonical.vendor_bank_accounts","canonical.bank_accounts"],"required_fields":["vendor_id","bank_account_id","account_token"]}'::jsonb,
    '{"fields":["bank_account_id","account_token","vendor_ids","vendor_count"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id","schedule":"nightly"}'::jsonb,
    'Bank account {{account_token}} is shared by {{vendor_count}} distinct vendors: {{vendor_ids}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 14. AP_VENDOR_EMPLOYEE_ADDRESS_MATCH_V1 ------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_VENDOR_EMPLOYEE_ADDRESS_MATCH_V1','Vendor and Employee Address Match','AP','vendor_master','fraud','conflict_of_interest',
    'Detects a vendor entity sharing a normalized address with an employee entity.',
    'A vendor registered at an employee''s home address is a strong indicator of an undisclosed related-party or ghost-vendor scheme.',
    'Joins canonical.addresses on the normalized address_hash across vendor and employee entities.',
    'deterministic','static','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_VENDOR_EMPLOYEE_ADDRESS_MATCH_V1 — vendor shares address with employee.
-- required params: :tenant_id, :matter_id
select v.id as vendor_id, e.id as employee_id, a1.address_hash
from canonical.vendors v
join canonical.addresses a1 on a1.entity_id = v.entity_id
join canonical.addresses a2
  on a2.address_hash = a1.address_hash and a2.entity_id <> a1.entity_id
join canonical.employees e on e.entity_id = a2.entity_id
where v.tenant_id = :tenant_id and v.matter_id = :matter_id
  and v.record_status = 'active' and e.record_status = 'active'
  and a1.address_hash is not null;
    $sql$,
    '{}'::jsonb,
    '{}'::jsonb,
    '{"required_tables":["canonical.vendors","canonical.employees","canonical.addresses"],"required_fields":["entity_id","address_hash"]}'::jsonb,
    '{"fields":["vendor_id","employee_id","address_hash"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id","schedule":"nightly"}'::jsonb,
    'Vendor {{vendor_id}} shares a normalized address with employee {{employee_id}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 15. AP_VENDOR_EMPLOYEE_BANK_MATCH_V1 ---------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'AP_VENDOR_EMPLOYEE_BANK_MATCH_V1','Vendor and Employee Bank-Account Match','AP','vendor_master','fraud','ghost_vendor',
    'Detects a vendor bank account that is also used as an employee direct-deposit account.',
    'A shared bank account between a vendor and an employee is one of the strongest ghost-vendor / payroll-diversion indicators available.',
    'Joins canonical.vendor_bank_accounts and canonical.employee_bank_accounts on the same bank_account_id.',
    'deterministic','static','ap_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- AP_VENDOR_EMPLOYEE_BANK_MATCH_V1 — vendor account matches employee account.
-- required params: :tenant_id, :matter_id
select v.id as vendor_id, e.id as employee_id, ba.account_token
from canonical.vendor_bank_accounts vba
join canonical.vendors v on v.id = vba.vendor_id
join canonical.bank_accounts ba on ba.id = vba.bank_account_id
join canonical.employee_bank_accounts eba on eba.bank_account_id = ba.id
join canonical.employees e on e.id = eba.employee_id
where v.tenant_id = :tenant_id and v.matter_id = :matter_id
  and v.record_status = 'active' and e.record_status = 'active';
    $sql$,
    '{}'::jsonb,
    '{}'::jsonb,
    '{"required_tables":["canonical.vendor_bank_accounts","canonical.employee_bank_accounts","canonical.bank_accounts"],"required_fields":["bank_account_id","account_token"]}'::jsonb,
    '{"fields":["vendor_id","employee_id","account_token"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id","schedule":"nightly"}'::jsonb,
    'Vendor {{vendor_id}} and employee {{employee_id}} share bank account {{account_token}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 16. PROC_SPLIT_PURCHASE_THRESHOLD_AVOIDANCE_V1 -----------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'PROC_SPLIT_PURCHASE_THRESHOLD_AVOIDANCE_V1','Split-Purchase Threshold Avoidance','procurement','purchasing','control_failure','threshold_avoidance',
    'Identifies multiple purchases that individually fall below an approval/bidding threshold but collectively exceed it.',
    'Splitting spend into sub-threshold pieces is a common way to bypass required approval or competitive-bid controls.',
    'STUB: canonical.invoices has no requester/cost-center field yet, so grouping is approximated by vendor + calendar-day window rather than a true rolling window or requester dimension.',
    'deterministic','formula','procurement_officer','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- PROC_SPLIT_PURCHASE_THRESHOLD_AVOIDANCE_V1 — purchases split below threshold.
-- STUB: grouped by vendor + invoice-date day bucket (no requester/cost-center
-- field on canonical.invoices yet; true rolling aggregation_window_days
-- grouping should replace the day-bucket once that field exists).
-- required params: :tenant_id, :matter_id, :threshold_amount, :lower_band_pct, :minimum_transaction_count
select i.vendor_id,
       date_trunc('day', i.invoice_date) as window_anchor,
       array_agg(i.id) as invoice_ids,
       sum(i.amount_original) as aggregate_amount,
       count(*) as transaction_count
from canonical.invoices i
where i.tenant_id = :tenant_id and i.matter_id = :matter_id
  and i.record_status = 'active'
  and i.amount_original >= :threshold_amount * (:lower_band_pct / 100.0)
  and i.amount_original < :threshold_amount
group by i.vendor_id, date_trunc('day', i.invoice_date)
having count(*) >= :minimum_transaction_count
   and sum(i.amount_original) >= :threshold_amount;
    $sql$,
    '{"threshold_amount":{"type":"decimal","min":0},"aggregation_window_days":{"type":"integer","min":1,"max":90},"lower_band_pct":{"type":"decimal","min":0,"max":100},"upper_band_pct":{"type":"decimal","min":0,"max":100},"minimum_transaction_count":{"type":"integer","min":2}}'::jsonb,
    '{"threshold_amount":10000.00,"aggregation_window_days":7,"lower_band_pct":80,"upper_band_pct":100,"minimum_transaction_count":2}'::jsonb,
    '{"required_tables":["canonical.invoices"],"required_fields":["vendor_id","invoice_date","amount_original"],"deferred_objects":["canonical.purchase_orders","requester field"]}'::jsonb,
    '{"fields":["vendor_id","window_anchor","invoice_ids","aggregate_amount","transaction_count"]}'::jsonb,
    '{"timeout_seconds":300,"partitioning":"matter_id,invoice_date","schedule":"nightly"}'::jsonb,
    'Vendor {{vendor_id}} had {{transaction_count}} purchases near {{window_anchor}} totaling {{aggregate_amount}}, just under the {{threshold_amount}} threshold.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 17. PROC_INVOICE_EXCEEDS_CONTRACT_V1 ---------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'PROC_INVOICE_EXCEEDS_CONTRACT_V1','Invoice Exceeds Contract Ceiling','procurement','contract','control_failure','billing_scheme',
    'Detects cumulative vendor billing that exceeds the contracted ceiling.',
    'Billing beyond the contracted amount without an approved change order is unauthorized spend and a common overbilling vector.',
    'STUB: canonical.contracts does not exist in this schema yet (Release 2). Approximated with a parameter-supplied contract-ceiling map keyed by vendor_id.',
    'deterministic','static','procurement_officer','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- PROC_INVOICE_EXCEEDS_CONTRACT_V1 — billing exceeds contract value.
-- STUB: canonical.contracts does not exist yet; approximates using a
-- parameter-supplied contract-ceiling map keyed by vendor_id.
-- required params: :tenant_id, :matter_id, :contract_ceilings (jsonb: {"<vendor_id>": <ceiling>}), :tolerance_pct
select i.vendor_id,
       sum(i.amount_original) as billed_total,
       (:contract_ceilings::jsonb ->> i.vendor_id::text)::numeric as contract_amount
from canonical.invoices i
where i.tenant_id = :tenant_id and i.matter_id = :matter_id
  and i.record_status = 'active'
  and (:contract_ceilings::jsonb ? i.vendor_id::text)
group by i.vendor_id
having sum(i.amount_original) >
       (:contract_ceilings::jsonb ->> i.vendor_id::text)::numeric * (1 + :tolerance_pct / 100.0);
    $sql$,
    '{"contract_ceilings":{"type":"object"},"tolerance_pct":{"type":"decimal","min":0,"max":20}}'::jsonb,
    '{"contract_ceilings":{},"tolerance_pct":0.00}'::jsonb,
    '{"required_tables":["canonical.invoices"],"required_fields":["vendor_id","amount_original"],"deferred_objects":["canonical.contracts"]}'::jsonb,
    '{"fields":["vendor_id","billed_total","contract_amount"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id","schedule":"weekly"}'::jsonb,
    'Vendor {{vendor_id}} has billed {{billed_total}} against a contract ceiling of {{contract_amount}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 18. PROC_PO_CREATED_AFTER_INVOICE_V1 ---------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'PROC_PO_CREATED_AFTER_INVOICE_V1','Purchase Order Created After Invoice','procurement','purchase_order','control_failure','process_bypass',
    'Flags invoices carrying a PO reference for date-sequence review against the purchase order.',
    'A purchase order created after the invoice it supposedly authorizes indicates the PO process was bypassed and retrofitted.',
    'STUB: canonical.purchase_orders does not exist yet; invoices carry only a po_number reference with no PO creation date, so this lists PO-referenced invoices for manual date-variance review.',
    'deterministic','static','procurement_officer','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- PROC_PO_CREATED_AFTER_INVOICE_V1 — purchase order created after invoice.
-- STUB: canonical.purchase_orders does not exist yet; invoices carry only a
-- po_number text reference with no PO creation date. Lists PO-referenced
-- invoices for manual date-variance review pending the procurement model.
-- required params: :tenant_id, :matter_id, :lookback_days
select i.id as invoice_id, i.po_number, i.invoice_date, i.vendor_id
from canonical.invoices i
where i.tenant_id = :tenant_id and i.matter_id = :matter_id
  and i.record_status = 'active'
  and i.po_number is not null
  and i.invoice_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"grace_days":{"type":"integer","min":0,"max":30},"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"grace_days":0,"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.invoices"],"required_fields":["po_number","invoice_date","vendor_id"],"deferred_objects":["canonical.purchase_orders"]}'::jsonb,
    '{"fields":["invoice_id","po_number","invoice_date","vendor_id"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id,invoice_date","schedule":"weekly"}'::jsonb,
    'Invoice {{invoice_id}} references PO {{po_number}}; PO creation date could not be verified against the invoice date pending the procurement data model.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 19. PAYROLL_DUPLICATE_DIRECT_DEPOSIT_V1 ------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'PAYROLL_DUPLICATE_DIRECT_DEPOSIT_V1','Duplicate Direct-Deposit Account','payroll','direct_deposit','fraud','ghost_employee',
    'Detects two or more employees sharing the same direct-deposit bank account.',
    'Multiple employees paid into one account is a leading ghost-employee / payroll-diversion indicator.',
    'Groups canonical.employee_bank_accounts by bank_account_id and flags groups with 2+ distinct employees.',
    'deterministic','static','payroll_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- PAYROLL_DUPLICATE_DIRECT_DEPOSIT_V1 — multiple employees share bank account.
-- required params: :tenant_id, :matter_id, :minimum_employee_count
select ba.id as bank_account_id, ba.account_token,
       array_agg(distinct eba.employee_id) as employee_ids,
       count(distinct eba.employee_id) as employee_count
from canonical.employee_bank_accounts eba
join canonical.bank_accounts ba on ba.id = eba.bank_account_id
where eba.tenant_id = :tenant_id and eba.matter_id = :matter_id
  and eba.record_status = 'active'
group by ba.id, ba.account_token
having count(distinct eba.employee_id) >= :minimum_employee_count;
    $sql$,
    '{"minimum_employee_count":{"type":"integer","min":2,"max":10}}'::jsonb,
    '{"minimum_employee_count":2}'::jsonb,
    '{"required_tables":["canonical.employee_bank_accounts","canonical.bank_accounts"],"required_fields":["employee_id","bank_account_id","account_token"]}'::jsonb,
    '{"fields":["bank_account_id","account_token","employee_ids","employee_count"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id","schedule":"nightly"}'::jsonb,
    'Bank account {{account_token}} receives direct deposit for {{employee_count}} distinct employees: {{employee_ids}}.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 20. PAYROLL_PAYMENT_TO_TERMINATED_EMPLOYEE_V1 ------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'PAYROLL_PAYMENT_TO_TERMINATED_EMPLOYEE_V1','Payment to Terminated Employee','payroll','disbursement','fraud','ghost_employee',
    'Detects a payroll disbursement dated after an employee''s recorded termination date.',
    'Continued payroll after termination is either a control failure (offboarding not synced to payroll) or active ghost-employee fraud.',
    'Uses canonical.transactions where transaction_type = ''payroll'', joined to canonical.employees via the counterparty entity.',
    'deterministic','formula','payroll_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- PAYROLL_PAYMENT_TO_TERMINATED_EMPLOYEE_V1 — payroll after termination.
-- required params: :tenant_id, :matter_id, :grace_days, :lookback_days
select t.id as transaction_id, t.transaction_date, t.amount_original,
       e.id as employee_id, e.termination_date,
       (t.transaction_date - e.termination_date) as days_after_termination
from canonical.transactions t
join canonical.entities emp_entity on emp_entity.id = t.counterparty_entity_id
join canonical.employees e on e.entity_id = emp_entity.id
where t.tenant_id = :tenant_id and t.matter_id = :matter_id
  and t.record_status = 'active'
  and t.transaction_type = 'payroll'
  and e.termination_date is not null
  and t.transaction_date > e.termination_date + (:grace_days || ' days')::interval
  and t.transaction_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"grace_days":{"type":"integer","min":0,"max":60},"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"grace_days":0,"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.transactions","canonical.employees","canonical.entities"],"required_fields":["transaction_type","termination_date","counterparty_entity_id"]}'::jsonb,
    '{"fields":["transaction_id","employee_id","termination_date","days_after_termination","amount_original"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id,transaction_date","schedule":"nightly"}'::jsonb,
    'Payroll transaction {{transaction_id}} of {{amount_original}} was paid {{days_after_termination}} day(s) after employee {{employee_id}} terminated.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 21. EXPENSE_DUPLICATE_RECEIPT_V1 -------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'EXPENSE_DUPLICATE_RECEIPT_V1','Duplicate Expense Receipt','expense','expense_claim','fraud','expense_fraud',
    'Detects the same receipt or claim submitted more than once by the same claimant.',
    'Resubmission of the same receipt across periods or systems is a common expense-reimbursement fraud pattern.',
    'STUB: canonical.expense_claims does not exist yet; approximated using canonical.transactions where transaction_type = ''claim'', matched on normalized description, amount, and claimant.',
    'deterministic','formula','payroll_controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- EXPENSE_DUPLICATE_RECEIPT_V1 — same receipt submitted multiple times.
-- STUB: canonical.expense_claims does not exist yet; approximated using
-- canonical.transactions where transaction_type = 'claim' as a receipt-
-- duplication proxy (normalized description + amount + claimant match).
-- required params: :tenant_id, :matter_id, :lookback_days, :amount_tolerance_pct
select t1.id as claim_id_a, t2.id as claim_id_b, t1.counterparty_entity_id,
       t1.amount_original as amount_a, t2.amount_original as amount_b,
       t1.transaction_date as date_a, t2.transaction_date as date_b
from canonical.transactions t1
join canonical.transactions t2
  on t2.matter_id = t1.matter_id
 and t2.counterparty_entity_id = t1.counterparty_entity_id
 and t2.id > t1.id
 and t2.description_normalized = t1.description_normalized
 and abs(t2.amount_original - t1.amount_original) <= t1.amount_original * (:amount_tolerance_pct / 100.0)
where t1.tenant_id = :tenant_id and t1.matter_id = :matter_id
  and t1.transaction_type = 'claim' and t2.transaction_type = 'claim'
  and t1.record_status = 'active' and t2.record_status = 'active'
  and t1.description_normalized is not null
  and t1.transaction_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650},"amount_tolerance_pct":{"type":"decimal","min":0,"max":5}}'::jsonb,
    '{"lookback_days":365,"amount_tolerance_pct":0.00}'::jsonb,
    '{"required_tables":["canonical.transactions"],"required_fields":["transaction_type","description_normalized","amount_original","counterparty_entity_id"],"deferred_objects":["canonical.expense_claims"]}'::jsonb,
    '{"fields":["claim_id_a","claim_id_b","counterparty_entity_id","amount_a","amount_b"]}'::jsonb,
    '{"timeout_seconds":300,"partitioning":"matter_id,transaction_date","schedule":"nightly"}'::jsonb,
    'Claims {{claim_id_a}} and {{claim_id_b}} by {{counterparty_entity_id}} match on description and amount within tolerance.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 22. GL_MANUAL_PERIOD_END_ENTRY_V1 ------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'GL_MANUAL_PERIOD_END_ENTRY_V1','Manual Period-End Journal Entry','GL','journal_entry','control_failure','earnings_management',
    'Detects a manual journal entry posted within a defined window of a period-end close date.',
    'Manual entries clustered around period close are a recognized earnings-management and financial-statement-fraud risk indicator.',
    'Uses canonical.transactions where transaction_type = ''journal'', compared against a matter-supplied list of period-end dates.',
    'deterministic','static','controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- GL_MANUAL_PERIOD_END_ENTRY_V1 — manual entry near period close.
-- required params: :tenant_id, :matter_id, :period_end_days, :period_end_dates (jsonb array of ISO dates)
select t.id as journal_transaction_id, t.transaction_date, t.posting_date, t.amount_original,
       t.description_raw
from canonical.transactions t
where t.tenant_id = :tenant_id and t.matter_id = :matter_id
  and t.record_status = 'active'
  and t.transaction_type = 'journal'
  and exists (
    select 1 from jsonb_array_elements_text(:period_end_dates::jsonb) pe(d)
    where abs(t.posting_date - pe.d::date) <= :period_end_days
  );
    $sql$,
    '{"period_end_days":{"type":"integer","min":0,"max":15},"period_end_dates":{"type":"array"}}'::jsonb,
    '{"period_end_days":2,"period_end_dates":[]}'::jsonb,
    '{"required_tables":["canonical.transactions"],"required_fields":["transaction_type","posting_date","amount_original"]}'::jsonb,
    '{"fields":["journal_transaction_id","transaction_date","posting_date","amount_original"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id,posting_date","schedule":"nightly"}'::jsonb,
    'Manual journal entry {{journal_transaction_id}} was posted {{posting_date}}, within {{period_end_days}} day(s) of period close.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 23. GL_RAPID_REVERSAL_ENTRY_V1 ----------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'GL_RAPID_REVERSAL_ENTRY_V1','Rapid Journal Reversal','GL','journal_entry','control_failure','earnings_management',
    'Detects a journal entry reversed within an unusually short window of posting.',
    'Post-then-quickly-reverse patterns can mask temporary balance-sheet or income-statement manipulation around reporting dates.',
    'Uses canonical.transactions.reversal_of_transaction_id, filtered to transaction_type = ''journal''.',
    'deterministic','static','controller','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- GL_RAPID_REVERSAL_ENTRY_V1 — entry reverses quickly.
-- required params: :tenant_id, :matter_id, :reversal_days, :lookback_days
select t.id as original_transaction_id, r.id as reversal_transaction_id,
       t.transaction_date as original_date, r.transaction_date as reversal_date,
       (r.transaction_date - t.transaction_date) as days_to_reversal, t.amount_original
from canonical.transactions t
join canonical.transactions r on r.reversal_of_transaction_id = t.id
where t.tenant_id = :tenant_id and t.matter_id = :matter_id
  and t.record_status = 'active' and r.record_status = 'active'
  and t.transaction_type = 'journal'
  and (r.transaction_date - t.transaction_date) <= :reversal_days
  and t.transaction_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"reversal_days":{"type":"integer","min":0,"max":30},"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"reversal_days":3,"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.transactions"],"required_fields":["reversal_of_transaction_id","transaction_type","transaction_date"]}'::jsonb,
    '{"fields":["original_transaction_id","reversal_transaction_id","days_to_reversal","amount_original"]}'::jsonb,
    '{"timeout_seconds":180,"partitioning":"matter_id,transaction_date","schedule":"nightly"}'::jsonb,
    'Journal entry {{original_transaction_id}} of {{amount_original}} was reversed {{days_to_reversal}} day(s) after posting.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 24. GRC_PAYMENT_SOD_CONFLICT_V1 ---------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'GRC_PAYMENT_SOD_CONFLICT_V1','Payment Segregation-of-Duties Conflict','GRC','access_control','control_failure','sod_conflict',
    'Detects a payment where any two of initiator, approver, and releaser are the same person.',
    'Overlap across any two of the three payment-release duties defeats the independent-check purpose of the workflow.',
    'Pairwise equality test across canonical.payments.initiator_user_ref / approver_user_ref / releaser_user_ref.',
    'deterministic','static','compliance_officer','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- GRC_PAYMENT_SOD_CONFLICT_V1 — incompatible payment duties held by one person.
-- required params: :tenant_id, :matter_id, :lookback_days
select p.id as payment_id, p.payment_reference,
       p.initiator_user_ref, p.approver_user_ref, p.releaser_user_ref
from canonical.payments p
where p.tenant_id = :tenant_id and p.matter_id = :matter_id
  and p.record_status = 'active'
  and (p.initiator_user_ref = p.approver_user_ref
       or p.initiator_user_ref = p.releaser_user_ref
       or p.approver_user_ref = p.releaser_user_ref)
  and p.payment_date >= (current_date - (:lookback_days || ' days')::interval);
    $sql$,
    '{"lookback_days":{"type":"integer","min":30,"max":3650}}'::jsonb,
    '{"lookback_days":365}'::jsonb,
    '{"required_tables":["canonical.payments"],"required_fields":["initiator_user_ref","approver_user_ref","releaser_user_ref"]}'::jsonb,
    '{"fields":["payment_id","initiator_user_ref","approver_user_ref","releaser_user_ref"]}'::jsonb,
    '{"timeout_seconds":120,"partitioning":"matter_id,payment_date","schedule":"nightly"}'::jsonb,
    'Payment {{payment_id}} has overlapping duty assignment among initiator, approver, and releaser.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

  -- 25. GRC_REMEDIATION_OVERDUE_V1 -----------------------------------------------
  insert into rules.rule_definitions (
    rule_code, rule_name, domain, subdomain, risk_category, scheme_category,
    description, business_rationale, methodology_note, rule_type, severity_model,
    reviewer_role, status
  ) values (
    'GRC_REMEDIATION_OVERDUE_V1','Overdue Remediation Action','GRC','remediation','compliance','control_gap',
    'Detects an open remediation recommendation whose target date has passed.',
    'Overdue remediation leaves a known control gap or finding unaddressed, extending exposure and regulatory/monitor risk.',
    'Reads investigation.recommendations directly (target_date, status) — this is a real canonical object already in the schema.',
    'deterministic','static','compliance_officer','draft'
  ) returning id into v_rule_id;

  insert into rules.rule_versions (
    rule_id, version_number, logic_sql, parameter_schema, default_parameters,
    input_contract, output_contract, execution_profile, explainability_template, approval_status
  ) values (
    v_rule_id, '1.0.0',
    $sql$
-- GRC_REMEDIATION_OVERDUE_V1 — corrective action overdue.
-- required params: :tenant_id, :matter_id, :days_overdue
select r.id as recommendation_id, r.recommendation, r.owner_user_id, r.target_date, r.status,
       (current_date - r.target_date) as days_overdue
from investigation.recommendations r
where r.tenant_id = :tenant_id and r.matter_id = :matter_id
  and r.record_status = 'active'
  and r.status <> 'closed'
  and r.target_date is not null
  and (current_date - r.target_date) >= :days_overdue;
    $sql$,
    '{"days_overdue":{"type":"integer","min":0,"max":365}}'::jsonb,
    '{"days_overdue":0}'::jsonb,
    '{"required_tables":["investigation.recommendations"],"required_fields":["target_date","status","owner_user_id"]}'::jsonb,
    '{"fields":["recommendation_id","owner_user_id","target_date","status","days_overdue"]}'::jsonb,
    '{"timeout_seconds":60,"partitioning":"matter_id","schedule":"weekly"}'::jsonb,
    'Remediation {{recommendation_id}} owned by {{owner_user_id}} is {{days_overdue}} day(s) overdue.',
    'draft'
  ) returning id into v_version_id;

  update rules.rule_definitions set current_version_id = v_version_id where id = v_rule_id;

end $$;

-- ============================================================================
-- End of migration 0012.
--
-- Deliberately left out of this slice (see report to the requester):
--   * Physical date/matter partitioning of hot tables (spec §16) — a live-
--     data physical layout change, not something to bolt on via ALTER on a
--     database already carrying rows; needs its own reviewed migration.
--   * Loosening rules.rule_definitions' UNIQUE(rule_code) to the spec's
--     UNIQUE(rule_code, effective_from) — would weaken a live constraint.
--   * Seed rows for rule_parameter_definitions, rule_parameter_sets,
--     population_definitions, population_snapshots, rule_test_cases,
--     rule_test_results, alert_review_events, rule_operational_metrics — the
--     task scoped seeding to rule_definitions + rule_versions; these tables
--     ship empty, ready for the execution engine / QA workflow to populate.
--   * Rules requiring canonical objects this schema hasn't built yet
--     (purchase orders, contracts, receiving records, a payment-approval
--     event log, a bank-reconciliation-item ledger, GRC control/attestation/
--     access-recertification tables) are catalogued with STUB-labeled
--     logic_sql approximated against the closest real table (see header).
--     The remaining ~35 rules in the full A-F catalog (spec §13) beyond the
--     25-rule minimum release set were not seeded at all.
-- ============================================================================
