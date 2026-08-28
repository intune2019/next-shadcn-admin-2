-- ============================================================================
-- Migration 0013: Calculation Engine
--
-- Resolves the deliberately-deferred placeholder called out in
-- docs/ADR-0001-foundation.md ("calculation engine tables, referenced by
-- report_claim_links.calculation_run_ref") and in migration 0009's comment
-- `calculation_run_ref uuid, -- FK to calculations.* in a later migration`.
--
-- Schema name: the source specification ("Forens_iQ Calculation Model
-- Specifications", section 3 "Core Database Schema") names every table with
-- the literal prefix `calculations.` (calculations.model_definitions,
-- calculations.model_versions, calculations.calculation_runs, ...). That
-- name is followed here rather than the shorter `calc` working name, so the
-- schema and its tables match the spec exactly.
--
-- Governing principles carried over from the spec (section 1):
--   - No floating point for currency -> numeric(20,4) everywhere money is
--     stored, matching migration 0006's canonical financial columns.
--   - Preserve original/base currency + fx lineage on anything cross-currency
--     (kept at the input/output-row level; calculation_runs itself carries
--     currency_basis/reporting_currency, matching the canonical `fx_` rule
--     from migration 0001/0006 -- `fx_` stays reserved for FX-rate columns).
--   - Never overwrite a completed calculation run -> guarded by
--     calculations.tg_run_guard() below.
--   - Never allow a formula to change without a new model version -> guarded
--     by calculations.tg_model_version_lock() below.
--   - Independent reperformance must be possible -> calculations.
--     calculation_reperformances.
--   - Scenario assumptions must never silently mix -> one immutable-once-
--     approved scenario row per calculations.scenarios.
--
-- Purely additive: no existing 0001-0011 table is altered except a single
-- `ADD CONSTRAINT` wiring reporting.report_claim_links.calculation_run_ref
-- (already `uuid`, already nullable -- no type change needed) to the new
-- calculation_runs table.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Schema + grants (mirrors the migration 0001 pattern for a brand-new schema:
-- usage to authenticated/service_role, default privileges so every table
-- created below is selectable/writable without a per-table GRANT, RLS still
-- governs row visibility; anon gets nothing).
-- ---------------------------------------------------------------------------
create schema if not exists calculations;

grant usage on schema calculations to authenticated, service_role;

alter default privileges in schema calculations
  grant select, insert, update, delete on tables to authenticated, service_role;

comment on schema calculations is
  'Governed calculation engine: versioned model registry, scenarios, frozen calculation runs, assumption log, outputs/schedules, independent reperformance. Report-ready outputs only cite an approved run (see reporting.report_claim_links.calculation_run_ref).';

-- ============================================================================
-- 1. Calculation model registry (global library, not matter-scoped -- same
--    shape as rules.rule_definitions / rules.rule_versions in migration
--    0008: readable by any authenticated user, writable only by service_role
--    / a trusted admin path, so the catalog itself is a controlled asset).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- calculations.model_definitions  (spec 3.1)
-- ---------------------------------------------------------------------------
create table calculations.model_definitions (
  id                    uuid primary key default gen_random_uuid(),
  model_code            text not null unique,      -- e.g. FX_LOSS_KNOWN_UNAUTHORIZED_DISBURSEMENTS_V1
  model_name            text not null,
  domain                text,                       -- fraud, litigation, treasury, grc, receivership, regulatory
  category              text,                       -- loss, damages, recovery, tracing, interest, sampling...
  description           text,                       -- practitioner-facing description
  business_purpose      text,                       -- why the model exists
  methodology_type      text,                       -- transactional, statistical, accounting, economic, tracing
  unit_of_measure       text,                       -- currency, count, percent, days, units
  owner_user_id         uuid,
  required_reviewer_role text,
  approval_status       text not null default 'draft'
                         check (approval_status in ('draft','testing','approved','retired')),
  effective_from        timestamptz,
  effective_to          timestamptz,
  current_version_id    uuid,                       -- FK added below, after model_versions exists
  created_at            timestamptz not null default now(),
  created_by            uuid,
  approved_at           timestamptz,
  approved_by           uuid
);
create index on calculations.model_definitions(domain, category);

-- ---------------------------------------------------------------------------
-- calculations.model_versions  (spec 3.2)
-- Immutable once approved: formula_definition/contracts cannot change on an
-- approved version (calculations.tg_model_version_lock below) -- correcting a
-- formula means creating a new version_number, never editing history.
-- ---------------------------------------------------------------------------
create table calculations.model_versions (
  id                  uuid primary key default gen_random_uuid(),
  model_id            uuid not null references calculations.model_definitions(id),
  version_number      text not null,                -- semver, e.g. 1.0.0
  formula_language    text not null default 'calculation_dsl'
                       check (formula_language in ('sql','calculation_dsl','python','spreadsheet_import')),
  formula_definition  text not null,                 -- approved formula / executable definition
  formula_checksum    bytea,                          -- sha256(formula_definition), auto-computed
  input_contract      jsonb,                           -- required inputs and types
  output_contract     jsonb,                           -- required outputs and schedules
  assumption_schema   jsonb,                           -- permitted assumptions
  validation_rules    jsonb,                           -- formula and data controls
  scenario_schema     jsonb,                           -- allowed scenario structure
  methodology_note    text,
  citation_note       text,
  calculation_frequency text not null default 'ad_hoc'
                       check (calculation_frequency in ('ad_hoc','daily','monthly','quarterly')),
  approval_status     text not null default 'draft'
                       check (approval_status in ('draft','peer_reviewed','approved','retired')),
  created_at          timestamptz not null default now(),
  created_by          uuid,
  approved_at         timestamptz,
  approved_by         uuid,
  unique (model_id, version_number)
);
create index on calculations.model_versions(model_id);

alter table calculations.model_definitions
  add constraint model_current_version_fk
  foreign key (current_version_id) references calculations.model_versions(id);

-- auto-checksum the frozen formula text, same pattern as rules.tg_version_checksum
create or replace function calculations.tg_model_version_checksum()
returns trigger language plpgsql as $$
begin
  new.formula_checksum := extensions.digest(new.formula_definition, 'sha256');
  return new;
end $$;
create trigger tg_checksum before insert or update on calculations.model_versions
  for each row execute function calculations.tg_model_version_checksum();

-- "Never allow formulas to change without creating a new model version."
create or replace function calculations.tg_model_version_lock()
returns trigger language plpgsql as $$
begin
  if old.approval_status = 'approved' then
    if new.formula_definition is distinct from old.formula_definition
       or new.formula_language   is distinct from old.formula_language
       or new.input_contract     is distinct from old.input_contract
       or new.output_contract    is distinct from old.output_contract
       or new.assumption_schema  is distinct from old.assumption_schema
       or new.validation_rules   is distinct from old.validation_rules
       or new.scenario_schema    is distinct from old.scenario_schema
    then
      raise exception
        'Model version % (%) is approved -- formula/contract is immutable. Create a new model_version instead.',
        old.id, old.version_number
        using errcode = 'integrity_constraint_violation';
    end if;
  end if;
  return new;
end $$;
create trigger tg_formula_lock before update on calculations.model_versions
  for each row execute function calculations.tg_model_version_lock();

-- catalog is a controlled shared library: readable by any authenticated user,
-- mutated only by service_role (same shape as rules.rule_definitions/versions).
alter table calculations.model_definitions enable row level security;
alter table calculations.model_versions    enable row level security;
create policy sel on calculations.model_definitions for select to authenticated using (true);
create policy sel on calculations.model_versions    for select to authenticated using (true);
create policy all_sr on calculations.model_definitions for all to service_role using (true) with check (true);
create policy all_sr on calculations.model_versions    for all to service_role using (true) with check (true);

-- ============================================================================
-- 2. Scenario engine (spec section 15). A scenario is a named, immutable-
--    once-approved set of controlled assumptions applied to one model
--    version. Scoped to a matter (a case's own conservative/base/high
--    scenarios), unlike the shared model registry above.
-- ============================================================================
create table calculations.scenarios (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  matter_id        uuid not null references core.matters(id),
  model_version_id uuid not null references calculations.model_versions(id),
  scenario_name    text not null,          -- conservative, base, high, claimant, respondent...
  description      text,
  assumption_values jsonb not null default '{}'::jsonb,
  status           text not null default 'draft'
                   check (status in ('draft','approved','retired')),
  effective_date   date,
  approved_by      uuid,
  approved_at      timestamptz,
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid,
  row_version      integer not null default 1,
  unique (matter_id, model_version_id, scenario_name)
);
create index on calculations.scenarios(matter_id, model_version_id);

-- "No scenario may silently inherit assumptions from another scenario
-- without displaying them" -> once approved, the assumption set is frozen;
-- amending assumptions means retiring the scenario and creating a new one.
create or replace function calculations.tg_scenario_guard()
returns trigger language plpgsql as $$
begin
  if old.status = 'approved' then
    if new.assumption_values is distinct from old.assumption_values
       or new.scenario_name    is distinct from old.scenario_name
       or new.model_version_id is distinct from old.model_version_id
    then
      raise exception
        'Scenario % (%) is approved -- assumptions are immutable. Retire it and create a new scenario instead.',
        old.id, old.scenario_name
        using errcode = 'integrity_constraint_violation';
    end if;
  end if;
  return new;
end $$;
create trigger tg_scenario_guard before update on calculations.scenarios
  for each row execute function calculations.tg_scenario_guard();

-- ============================================================================
-- 3. Calculation runs (spec 3.3). The frozen record of one execution of one
--    model version against one input snapshot, one parameter set, and (if
--    applicable) one scenario. "Never overwrite a completed calculation run"
--    is enforced by calculations.tg_run_guard: once a run reaches
--    completed/reviewed/approved, its frozen inputs/outputs cannot change --
--    only forward status progression (review, approval) is permitted.
-- ============================================================================
create table calculations.calculation_runs (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null,
  matter_id                uuid not null references core.matters(id),
  model_version_id         uuid not null references calculations.model_versions(id),
  -- exact formula checksum at run time, frozen even if the model_version row
  -- is later retired/superseded -- belt-and-braces beside the version FK.
  formula_checksum_at_run  bytea,
  run_name                 text,
  run_type                 text not null default 'draft'
                            check (run_type in ('draft','scenario','final','reperformance','backfill')),
  input_snapshot_id        uuid not null default gen_random_uuid(),  -- correlates this run's calculation_inputs rows
  parameter_values         jsonb not null default '{}'::jsonb,        -- applied common-parameters-library values
  scenario_id              uuid references calculations.scenarios(id),
  currency_basis           text not null default 'reporting'
                            check (currency_basis in ('original','functional','reporting')),
  reporting_currency       char(3) not null default 'USD',
  as_of_date               date,
  start_date               date,
  end_date                 date,
  status                   text not null default 'draft'
                            check (status in ('draft','queued','running','completed','failed',
                                               'reviewed','approved','superseded','withdrawn')),
  output_total             numeric(20,4),             -- primary output
  output_currency          char(3),
  warning_count            integer not null default 0,
  exception_count          integer not null default 0,
  run_hash                 bytea,                     -- hash of inputs + formula + output
  narrative                text,                       -- report-ready plain-language description
  record_status            core.record_status not null default 'active',
  created_at               timestamptz not null default now(),
  created_by                uuid,
  completed_at              timestamptz,
  reviewed_by                uuid,
  reviewed_at                timestamptz,
  approved_by                uuid,
  approved_at                timestamptz,
  updated_at                 timestamptz not null default now(),
  updated_by                 uuid,
  row_version                 integer not null default 1
);
create index on calculations.calculation_runs(matter_id, status);
create index on calculations.calculation_runs(model_version_id);
create index on calculations.calculation_runs(scenario_id);

comment on table calculations.calculation_runs is
  'Frozen execution record. Never overwrite a completed run -- once status reaches completed/reviewed/approved, inputs/outputs/parameters are immutable (calculations.tg_run_guard); corrections are a new run.';

create or replace function calculations.tg_run_guard()
returns trigger language plpgsql as $$
begin
  if old.status in ('completed','reviewed','approved') then
    if new.model_version_id        is distinct from old.model_version_id
       or new.formula_checksum_at_run is distinct from old.formula_checksum_at_run
       or new.matter_id             is distinct from old.matter_id
       or new.input_snapshot_id     is distinct from old.input_snapshot_id
       or new.parameter_values      is distinct from old.parameter_values
       or new.scenario_id           is distinct from old.scenario_id
       or new.currency_basis        is distinct from old.currency_basis
       or new.reporting_currency    is distinct from old.reporting_currency
       or new.as_of_date            is distinct from old.as_of_date
       or new.start_date            is distinct from old.start_date
       or new.end_date              is distinct from old.end_date
       or new.output_total          is distinct from old.output_total
       or new.output_currency       is distinct from old.output_currency
       or new.run_hash              is distinct from old.run_hash
       or new.narrative             is distinct from old.narrative
    then
      raise exception
        'Calculation run % is % -- frozen inputs/outputs cannot be modified. Create a new run instead.',
        old.id, old.status
        using errcode = 'integrity_constraint_violation';
    end if;
  end if;

  if new.status in ('reviewed','approved') and new.reviewed_by is null then
    raise exception 'Calculation run % cannot be % without an independent reviewer', new.id, new.status
      using errcode = 'check_violation';
  end if;
  if new.status = 'approved' and new.approved_by is null then
    raise exception 'Calculation run % cannot be approved without an approver', new.id
      using errcode = 'check_violation';
  end if;

  return new;
end $$;
-- name sorts before tg_stamp so the freeze check runs against the caller's
-- NEW values, not values already rewritten by the stamp trigger
create trigger tg_run_guard before update on calculations.calculation_runs
  for each row execute function calculations.tg_run_guard();

-- ============================================================================
-- 4. Calculation inputs + assumption log (spec 3.4). Inputs are the frozen
--    dataset/filter/value actually used -- append-only, corrections are new
--    rows (never edit history of what a run actually consumed). Assumptions
--    are the explicit, reviewable, controlled-parameter log the spec
--    requires for "every damages model" -- editable up to approval, then
--    locked (calculations.tg_assumption_guard).
-- ============================================================================
create table calculations.calculation_inputs (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null,
  matter_id                 uuid not null references core.matters(id),
  calculation_run_id        uuid not null references calculations.calculation_runs(id),
  input_name                text not null,
  input_type                text,             -- dataset, transaction_list, rate, date, filter, manual_entry
  source_type                text,             -- canonical_table, evidence, external_source, approved_manual_input
  source_reference            text,             -- dataset version or evidence pointer
  query_or_filter_definition  text,             -- exact filter used
  original_value               jsonb,            -- value as received
  normalized_value              jsonb,            -- value used in formula
  unit                          text,             -- currency, percent, count, date
  source_evidence_id             uuid references evidence.evidence_items(id),
  entered_by                      uuid,
  validated_by                     uuid,
  validation_status                 text not null default 'passed'
                                     check (validation_status in ('passed','warning','failed')),
  created_at                         timestamptz not null default now(),
  created_by                          uuid
);
create index on calculations.calculation_inputs(calculation_run_id);

create table calculations.calculation_assumptions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  calculation_run_id  uuid not null references calculations.calculation_runs(id),
  assumption_code     text not null,             -- controlled assumption type
  assumption_name     text,
  value               jsonb not null,
  unit                text,                       -- currency, percentage, days, category
  basis               text,                       -- why selected
  authority_source    text,                       -- contract, policy, expert instruction, court order, market data
  source_evidence_id  uuid references evidence.evidence_items(id),
  sensitivity_level   text check (sensitivity_level in ('low','medium','high','critical')),
  applies_to          text,                       -- entire model or output component
  approved_by         uuid,
  approved_at         timestamptz,
  created_at          timestamptz not null default now(),
  created_by          uuid
);
create index on calculations.calculation_assumptions(calculation_run_id);

comment on table calculations.calculation_assumptions is
  'Assumption log required for every damages/loss model (interest rates, discount rates, methodology choices, offsets treated as controlled inputs, not hidden math). Locked once approved_at is set.';

create or replace function calculations.tg_assumption_guard()
returns trigger language plpgsql as $$
begin
  if old.approved_at is not null then
    if new.value            is distinct from old.value
       or new.unit             is distinct from old.unit
       or new.basis             is distinct from old.basis
       or new.assumption_code    is distinct from old.assumption_code
       or new.authority_source    is distinct from old.authority_source
    then
      raise exception
        'Assumption % (%) is already approved -- value/basis is immutable. Insert a new assumption record instead.',
        old.id, old.assumption_code
        using errcode = 'integrity_constraint_violation';
    end if;
  end if;
  return new;
end $$;
create trigger tg_assumption_guard before update on calculations.calculation_assumptions
  for each row execute function calculations.tg_assumption_guard();

-- ============================================================================
-- 5. Outputs + schedule rows (spec 3.5). These are the report-citable line
--    items: calculation_outputs holds the named totals (gross/net/interest/
--    present value...), calculation_schedule_rows holds the underlying
--    transaction-level detail. Both are append-only -- a run's results, once
--    written, are part of its frozen record (see calculations.
--    calculation_runs comment above); a correction is a new run.
-- ============================================================================
create table calculations.calculation_outputs (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  calculation_run_id  uuid not null references calculations.calculation_runs(id),
  output_code         text not null,             -- gross_loss, net_loss, interest, present_value...
  output_name         text,
  amount               numeric(20,4),
  currency              char(3),
  quantity               numeric(20,4),            -- non-monetary quantity where relevant
  confidence_level        text check (confidence_level in ('high','medium','low')),
  methodology_status       text check (methodology_status in ('actual','estimated','modeled','scenario')),
  output_explanation        text,                    -- plain-language explanation
  report_label                text,                    -- standard report label
  report_order                  int,
  created_at                     timestamptz not null default now(),
  created_by                      uuid
);
create index on calculations.calculation_outputs(calculation_run_id, report_order);

create table calculations.calculation_schedule_rows (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  calculation_run_id  uuid not null references calculations.calculation_runs(id),
  schedule_code       text not null,              -- name of schedule
  row_number          int,
  category             text,                        -- group or subtotal
  source_object_type    text,                        -- transaction, invoice, asset, claim, account
  source_object_id       uuid,                        -- canonical source object (polymorphic, matches source_object_type)
  row_date                 date,
  description                text,
  debit_amount                numeric(20,4),
  credit_amount                 numeric(20,4),
  net_amount                     numeric(20,4),
  currency                        char(3),
  evidence_references               jsonb,
  included_flag                      boolean not null default true,
  exclusion_reason                     text,
  reviewer_note                          text,
  created_at                              timestamptz not null default now(),
  created_by                               uuid
);
create index on calculations.calculation_schedule_rows(calculation_run_id, schedule_code, row_number);

-- ============================================================================
-- 6. Independent reperformance (spec section 18). A material approved run
--    must be reproducible by a second reviewer from the same frozen input
--    snapshot and model version; this table records the comparison.
-- ============================================================================
create table calculations.calculation_reperformances (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null,
  matter_id               uuid not null references core.matters(id),
  original_run_id         uuid not null references calculations.calculation_runs(id),
  reperformance_run_id    uuid not null references calculations.calculation_runs(id),
  difference_amount       numeric(20,4),
  difference_pct          numeric(12,6),           -- null when original output = 0 (report absolute variance instead)
  difference_explanation  text,
  reviewer_conclusion     text,
  approval_status         text not null default 'pending'
                           check (approval_status in ('pending','approved','rejected','correction_requested')),
  reviewed_by             uuid,
  reviewed_at             timestamptz,
  record_status           core.record_status not null default 'active',
  created_at              timestamptz not null default now(),
  created_by              uuid,
  updated_at              timestamptz not null default now(),
  updated_by              uuid,
  row_version              integer not null default 1,
  unique (original_run_id, reperformance_run_id),
  check (original_run_id <> reperformance_run_id)
);
create index on calculations.calculation_reperformances(matter_id);

-- ============================================================================
-- 7. Stamp triggers + RLS
--    - Matter-scoped mutable tables (scenarios, calculation_runs,
--      calculation_assumptions, calculation_reperformances): standard
--      sel(read)/ins(contribute) policies via the do-loop, PLUS a bespoke
--      update policy per table so that "contribute" access can operate a run
--      day-to-day (draft/queued/running/completed/failed, adding
--      assumptions, opening a reperformance request) while only "review"
--      access can push a row into a reviewed/approved state -- this maps
--      directly onto core.access_level's read < contribute < review <
--      approve < matter_admin ordering from migration 0002.
--    - Append-only children (calculation_inputs, calculation_outputs,
--      calculation_schedule_rows): sel/ins only, no UPDATE policy at all,
--      PLUS app.tg_deny_mutation so UPDATE/DELETE is rejected outright --
--      same append-only pattern as evidence.chain_of_custody_events /
--      audit.audit_events in migrations 0005/0010.
-- ============================================================================
do $$
declare t text; tables text[] := array[
  'calculations.scenarios','calculations.calculation_runs',
  'calculations.calculation_assumptions','calculations.calculation_reperformances'];
begin
  foreach t in array tables loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;

-- scenarios: contribute may edit a draft; pushing status to 'approved'
-- requires review access.
create policy upd on calculations.scenarios for update to authenticated
  using (app.has_matter_access(matter_id, 'contribute'))
  with check (
    app.has_matter_access(matter_id, 'contribute')
    and (status <> 'approved' or app.has_matter_access(matter_id, 'review'))
  );

-- calculation_runs: contribute may run/complete/fail a draft run; pushing
-- status to reviewed/approved requires review access (calculations.
-- tg_run_guard separately enforces reviewed_by/approved_by are set and that
-- a completed run's frozen fields cannot change regardless of RLS level).
create policy upd on calculations.calculation_runs for update to authenticated
  using (app.has_matter_access(matter_id, 'contribute'))
  with check (
    app.has_matter_access(matter_id, 'contribute')
    and (status not in ('reviewed','approved') or app.has_matter_access(matter_id, 'review'))
  );

-- calculation_assumptions: contribute may log/edit an unapproved assumption;
-- setting approved_at requires review access (calculations.
-- tg_assumption_guard separately locks value/basis once approved).
create policy upd on calculations.calculation_assumptions for update to authenticated
  using (app.has_matter_access(matter_id, 'contribute'))
  with check (
    app.has_matter_access(matter_id, 'contribute')
    and (approved_at is null or app.has_matter_access(matter_id, 'review'))
  );

-- calculation_reperformances: contribute may open/update a pending
-- reperformance; resolving it (approved/rejected/correction_requested)
-- requires review access.
create policy upd on calculations.calculation_reperformances for update to authenticated
  using (app.has_matter_access(matter_id, 'contribute'))
  with check (
    app.has_matter_access(matter_id, 'contribute')
    and (approval_status = 'pending' or app.has_matter_access(matter_id, 'review'))
  );

-- append-only children: sel + ins only, then hard-deny UPDATE/DELETE.
do $$
declare t text; tables text[] := array[
  'calculations.calculation_inputs','calculations.calculation_outputs',
  'calculations.calculation_schedule_rows'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
    execute format('create trigger tg_90_denymut before update or delete on %s
      for each row execute function app.tg_deny_mutation()', t);
  end loop;
end $$;

-- ============================================================================
-- 8. Wire report_claim_links.calculation_run_ref to a real table.
--    Migration 0009 created the column as a bare `uuid` with the comment
--    "FK to calculations.* in a later migration" -- this is that migration.
--    No type change needed (already uuid, already nullable).
-- ============================================================================
alter table reporting.report_claim_links
  add constraint report_claim_calculation_run_fk
  foreign key (calculation_run_ref) references calculations.calculation_runs(id);

create index on reporting.report_claim_links(calculation_run_ref);

comment on column reporting.report_claim_links.calculation_run_ref is
  'The exact calculation run (model version + frozen inputs + parameters + scenario) backing this report claim. A report generator should only surface runs with status = approved unless the template explicitly allows preliminary output (spec: Report Integration Contract).';

-- ============================================================================
-- 9. Seed catalog: the "Minimum Production Release Calculation Set" (spec
--    section 22) -- the 18 models the first Forens_iQ release must ship
--    with. Each gets a model_definitions row and an approved 1.0.0
--    model_versions row whose formula_definition is the literal formula
--    from the spec. Two models (FX_LOSS_NET_V1 and TREASURY_PAYMENT_
--    EXPOSURE_V1) appear in the spec's catalog table only, with no
--    dedicated formula subsection -- their formula_definition below is a
--    reasoned simplification consistent with the recovery/offset and
--    exposure-minus-mitigation patterns the spec uses for sibling models
--    (see the methodology_note on each row for the specific rationale).
-- ============================================================================
insert into calculations.model_definitions
  (model_code, model_name, domain, category, description, business_purpose,
   methodology_type, unit_of_measure, required_reviewer_role, approval_status,
   effective_from, approved_at)
values
  ('FX_LOSS_KNOWN_UNAUTHORIZED_DISBURSEMENTS_V1', 'Known Unauthorized Disbursements', 'fraud', 'loss',
   'Known unauthorized disbursements -- gross, recovery, offset, net loss.',
   'Provides a defensible, evidence-linked basis for quantifying confirmed unauthorized disbursements for fraud examination, vendor/reimbursement/payroll review, treasury-payment review, and court, insurer, or board reporting.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_LOSS_ATTEMPTED_LOSS_V1', 'Attempted Loss', 'fraud', 'loss',
   'Attempted but unsuccessful fraud -- attempted amount.',
   'Separates prevented/failed fraud attempts from realized loss so control effectiveness and true financial exposure are not conflated.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_LOSS_NET_V1', 'Net Loss After Recoveries and Offsets', 'fraud', 'loss',
   'Net loss after recoveries and offsets -- net realized loss.',
   'Gives a single governed net-loss figure after all verified recoveries and offsets, distinct from gross known loss, for restitution and reporting purposes.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_RESTITUTION_CANDIDATE_V1', 'Restitution Candidate Schedule', 'fraud', 'recovery',
   'Restitution candidate schedule -- net victim loss.',
   'Produces the loss figure a restitution order or settlement can be based on, after documented returns, recoveries, and approved offsets.',
   'accounting', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_DUPLICATE_PAYMENT_RECOVERY_V1', 'Duplicate Payment Recovery Opportunity', 'fraud', 'recovery',
   'Duplicate payment recovery opportunity -- potential recovery.',
   'Identifies recoverable vendor overpayments arising from duplicate or erroneous disbursements.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_PAYROLL_OVERPAYMENT_V1', 'Payroll Overpayment', 'fraud', 'loss',
   'Unauthorized or erroneous payroll -- net overpayment.',
   'Quantifies payroll dollars at risk from unauthorized, erroneous, or fraudulent disbursement patterns.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_EXPENSE_OVERPAYMENT_V1', 'Expense Overpayment', 'fraud', 'loss',
   'Unsupported or duplicate expenses -- net questioned expense.',
   'Quantifies expense reimbursement dollars that lack adequate support or violate policy.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_INVENTORY_SHRINKAGE_V1', 'Inventory Shrinkage', 'fraud', 'loss',
   'Inventory shortage -- estimated shortage loss.',
   'Converts book-to-physical inventory variance into a defensible estimated loss value under a stated costing methodology.',
   'accounting', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_UNEXPLAINED_FUNDS_V1', 'Unexplained Funds', 'fraud', 'tracing',
   'Source and application gap -- unexplained excess or shortfall.',
   'Flags periods where documented uses of funds exceed documented sources, as an investigative lead for unrecorded income, borrowing, or incomplete records.',
   'accounting', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_TRACE_DIRECT_V1', 'Direct Funds Trace', 'fraud', 'tracing',
   'Direct funds trace -- amount directly traced.',
   'Establishes a high-confidence, evidence-backed link between a source payment/asset and its destination.',
   'tracing', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('FX_TRACE_LOWEST_INTERMEDIATE_BALANCE_V1', 'Lowest Intermediate Balance Trace', 'fraud', 'tracing',
   'Commingled fund trace -- traceable balance.',
   'Determines the maximum traceable proceeds surviving in a commingled account for asset-recovery and forfeiture purposes.',
   'tracing', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('TREASURY_BANK_RECONCILIATION_V1', 'Bank Reconciliation', 'treasury', 'reconciliation',
   'Bank-to-ledger reconciliation -- unexplained difference.',
   'Surfaces unexplained bank-to-ledger differences that may indicate error, delay, or diversion of funds.',
   'accounting', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('TREASURY_RESTRICTED_CASH_BALANCE_V1', 'Restricted Cash Balance', 'treasury', 'liquidity',
   'Restricted-cash accounting -- available unrestricted cash.',
   'Prevents restricted, pledged, or trust/escrow cash from being presented as available operating cash.',
   'accounting', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('TREASURY_PAYMENT_EXPOSURE_V1', 'Payment Exposure', 'treasury', 'exposure',
   'Suspicious payment exposure -- potential exposure.',
   'Quantifies at-risk value from suspicious or unauthorized payment activity pending investigation or mitigation.',
   'transactional', 'currency', 'senior_examiner', 'approved', now(), now()),

  ('ECON_PREJUDGMENT_INTEREST_V1', 'Prejudgment Interest', 'litigation', 'interest',
   'Prejudgment interest -- interest accrued.',
   'Computes interest owed on a loss or claim principal for restitution, settlement, or judgment purposes.',
   'economic', 'currency', 'testifying_expert', 'approved', now(), now()),

  ('ECON_PRESENT_VALUE_V1', 'Present Value', 'litigation', 'valuation',
   'Present value -- discounted value.',
   'Restates future cash flows or damages in present-value terms for settlement or judgment purposes.',
   'economic', 'currency', 'testifying_expert', 'approved', now(), now()),

  ('GRC_EXCEPTION_RATE_V1', 'Control Exception Rate', 'grc', 'sampling',
   'Control exception rate -- exception percentage.',
   'Summarizes control-testing results as a defensible exception rate for audit and compliance reporting.',
   'statistical', 'percent', 'quality_reviewer', 'approved', now(), now()),

  ('GRC_SAMPLE_ERROR_EXTRAPOLATION_V1', 'Sample Error Extrapolation', 'grc', 'sampling',
   'Population error projection -- estimated error.',
   'Projects a sample-level error rate to the full population under a stated statistical methodology.',
   'statistical', 'currency', 'quality_reviewer', 'approved', now(), now());

insert into calculations.model_versions
  (model_id, version_number, formula_language, formula_definition, methodology_note,
   input_contract, output_contract, calculation_frequency, approval_status, approved_at)
select md.id, v.version_number, v.formula_language, v.formula_definition, v.methodology_note,
       v.input_contract, v.output_contract, v.calculation_frequency, v.approval_status, now()
from calculations.model_definitions md
join (
  values

  ('FX_LOSS_KNOWN_UNAUTHORIZED_DISBURSEMENTS_V1', '1.0.0', 'calculation_dsl',
   $f$gross_known_loss = SUM(eligible_unauthorized_disbursement_amounts)
net_known_loss = gross_known_loss - verified_recoveries - approved_offsets

-- where a payment was reversed before economic loss occurred:
--   eligible_unauthorized_disbursement_amount = 0
-- unless the applicable methodology treats the event as attempted loss.$f$,
   'Calculates gross and net loss from reviewed disbursements classified as unauthorized under the engagement''s approved criteria. Does not determine intent, legal liability, or restitution entitlement.',
   '{"required_inputs":["approved_transaction_population","unauthorized_classification","transaction_amount","transaction_date","payment_status","reversal_or_void_info","recovery_amount","offset_amount","evidence_link","reviewer_approval"]}'::jsonb,
   '{"primary_output":"net_known_loss","components":["gross_known_loss","verified_recoveries","approved_offsets","net_known_loss"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_LOSS_ATTEMPTED_LOSS_V1', '1.0.0', 'calculation_dsl',
   $f$attempted_loss = SUM(attempted_transaction_amount WHERE completion_status IN approved_attempted_statuses)

-- approved_attempted_statuses: blocked, rejected, cancelled, recalled,
-- returned, reversed_before_settlement, detected_before_release, not_completed$f$,
   'Measures attempted fraudulent or unauthorized transactions that were prevented, rejected, reversed before loss, intercepted, or otherwise did not result in a completed financial loss. Attempted loss must always be reported separately from realized loss.',
   '{"required_inputs":["attempted_transaction_population","attempted_transaction_amount","completion_status","actor","channel","account","payment_type","event_date","prevention_source"]}'::jsonb,
   '{"primary_output":"attempted_loss","components":["attempted_loss","attempted_event_count","estimated_avoided_loss"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_LOSS_NET_V1', '1.0.0', 'calculation_dsl',
   $f$net_loss = gross_actual_loss - verified_recoveries - approved_offsets - insurance_proceeds - third_party_recoveries$f$,
   'Aggregates net realized loss across confirmed loss categories after verified recoveries and approved offsets; distinct from gross known loss and from estimated/potential exposure. (Spec gives this model only as a catalog entry -- "net loss after recoveries and offsets, net realized loss" -- with no dedicated formula subsection; this formula generalizes the recovery/offset treatment used elsewhere in the spec, e.g. FX_RESTITUTION_CANDIDATE_V1.)',
   '{"required_inputs":["gross_actual_loss","verified_recoveries","approved_offsets","insurance_proceeds","third_party_recoveries"]}'::jsonb,
   '{"primary_output":"net_loss","components":["gross_actual_loss","verified_recoveries","approved_offsets","insurance_proceeds","third_party_recoveries","net_loss"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_RESTITUTION_CANDIDATE_V1', '1.0.0', 'calculation_dsl',
   $f$restitution_candidate = gross_actual_loss - returned_property_value - verified_recovery - approved_credit_or_offset

-- control: do not automatically deduct expected insurance proceeds, disputed
-- settlements, or contingent future recoveries unless an authorized
-- assumption explicitly allows it.$f$,
   'Produces a restitution-oriented schedule of actual loss less documented return of property, repayments, recoveries, credits, and other recognized offsets.',
   '{"required_inputs":["loss_schedule","recovery_schedule","returned_property_valuation","offset_approvals","payment_receipts","asset_disposition_records","recovery_date","valuation_date_and_methodology"]}'::jsonb,
   '{"primary_output":"restitution_candidate","components":["gross_actual_loss","returned_property_value","verified_recovery","approved_credit_or_offset","restitution_candidate"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_DUPLICATE_PAYMENT_RECOVERY_V1', '1.0.0', 'calculation_dsl',
   $f$-- per duplicate group:
recoverable_amount = total_paid_amount - supported_obligation_amount - documented_credit_or_refund
-- aggregate (only positive recoverable amounts):
total_potential_recovery = SUM(recoverable_amount WHERE recoverable_amount > 0)$f$,
   'Calculates potential recoveries from duplicate, erroneous, or overpaid vendor payments.',
   '{"required_inputs":["invoice","payment_record","vendor","credit_memo","refund_record","void_reversal_info","evidence_of_duplicate_service","vendor_correspondence"]}'::jsonb,
   '{"primary_output":"total_potential_recovery","components":["total_paid_amount","supported_obligation_amount","documented_credit_or_refund","recoverable_amount","total_potential_recovery"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_PAYROLL_OVERPAYMENT_V1', '1.0.0', 'calculation_dsl',
   $f$gross_payroll_overpayment = SUM(payment_amount WHERE inclusion_criteria_met)
net_payroll_overpayment = gross_payroll_overpayment - returned_wages - payroll_adjustments - approved_offsets$f$,
   'Calculates questionable or unauthorized payroll disbursements, including payments after termination, duplicate direct deposits, unauthorized rate increases/bonuses, unsupported overtime, and ghost-employee indicators. Gross wages, taxes, employer contributions, and net pay must be retained separately.',
   '{"required_inputs":["payment_amount","inclusion_criteria","returned_wages","payroll_adjustments","approved_offsets","gross_vs_net_pay_breakdown"]}'::jsonb,
   '{"primary_output":"net_payroll_overpayment","components":["gross_payroll_overpayment","returned_wages","payroll_adjustments","approved_offsets","net_payroll_overpayment"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_EXPENSE_OVERPAYMENT_V1', '1.0.0', 'calculation_dsl',
   $f$questioned_expense = submitted_amount - supported_business_amount - approved_exception_amount - credit_or_repayment$f$,
   'Calculates unsupported, duplicate, policy-noncompliant, or personal expense reimbursements.',
   '{"required_inputs":["submitted_amount","supported_business_amount","approved_exception_amount","credit_or_repayment","receipt_documentation","policy_reference"]}'::jsonb,
   '{"primary_output":"questioned_expense","components":["submitted_amount","supported_business_amount","approved_exception_amount","credit_or_repayment","questioned_expense"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_INVENTORY_SHRINKAGE_V1', '1.0.0', 'calculation_dsl',
   $f$quantity_shortage = book_quantity - physical_count_quantity
shrinkage_value = quantity_shortage * valuation_unit_cost

-- valuation_unit_cost methodology: fifo | weighted_average | specific_identification
-- | standard_cost | replacement_cost | net_realizable_value (must be stated, not implied)$f$,
   'Measures inventory variance and estimates loss subject to approved valuation methodology. The report must state whether the model measures inventory variance, suspected theft, or confirmed misappropriation -- these are not interchangeable.',
   '{"required_inputs":["book_quantity","physical_count_quantity","valuation_unit_cost","valuation_methodology","location","custodian"]}'::jsonb,
   '{"primary_output":"shrinkage_value","components":["book_quantity","physical_count_quantity","quantity_shortage","valuation_unit_cost","shrinkage_value"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_UNEXPLAINED_FUNDS_V1', '1.0.0', 'calculation_dsl',
   $f$unexplained_funds = documented_uses - documented_sources

-- if uses exceed sources, the difference may indicate unexplained funding,
-- unrecorded income, borrowing, transfers, or incomplete data; this is an
-- investigative lead, not automatically a conclusion of wrongdoing.$f$,
   'Calculates the difference between documented sources and documented uses of funds over a period.',
   '{"required_inputs":["bank_deposits","cash_receipts","borrowings","asset_sales","payroll_income","transfers","cash_expenditures","asset_acquisitions","debt_payments","living_expenses","business_expenses"]}'::jsonb,
   '{"primary_output":"unexplained_funds","components":["documented_sources","documented_uses","unexplained_funds"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_TRACE_DIRECT_V1', '1.0.0', 'calculation_dsl',
   $f$directly_traced_amount = MIN(source_proceeds_available, destination_receipt_identified)$f$,
   'Traces a specifically identified payment or asset from source to destination where transaction records establish a direct link. Confidence: high = direct transaction reference or exact linked transfer; medium = strong date/amount/counterparty/account correlation; low = circumstantial or incomplete linkage.',
   '{"required_inputs":["source_transaction","destination_transaction","matching_linkage","evidence_supporting_connection","intermediate_transfer_details"]}'::jsonb,
   '{"primary_output":"directly_traced_amount","components":["source_proceeds_available","destination_receipt_identified","directly_traced_amount","trace_confidence"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('FX_TRACE_LOWEST_INTERMEDIATE_BALANCE_V1', '1.0.0', 'calculation_dsl',
   $f$-- for each relevant period:
traceable_balance_t = MIN(identified_proceeds_deposited_to_date, account_balance_t)
-- final traceable amount = the lowest applicable balance after deposit and
-- before the measurement date, subject to documented methodology assumptions.$f$,
   'Calculates traceable proceeds in a commingled account under a lowest-intermediate-balance methodology. Must not assume later deposits replenish traceable proceeds unless the approved methodology expressly provides for that treatment.',
   '{"required_inputs":["account_daily_balances","identified_proceeds_deposit_date_amount","withdrawals","subsequent_deposits","measurement_date","account_ownership_history"]}'::jsonb,
   '{"primary_output":"traceable_amount","components":["identified_proceeds_deposited","account_balance_schedule","lowest_interim_balance","traceable_amount"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('TREASURY_BANK_RECONCILIATION_V1', '1.0.0', 'calculation_dsl',
   $f$reconciled_balance = ledger_ending_balance + deposits_in_transit - outstanding_checks +/- approved_adjustments
unexplained_difference = bank_ending_balance - reconciled_balance$f$,
   'Reconciles bank statement activity and balances to general-ledger records and tracks unexplained differences. No unexplained difference may be silently netted into another item; negative aging or future-dated items require a warning.',
   '{"required_inputs":["bank_statement_balance","ledger_balance","outstanding_checks","deposits_in_transit","ach_wire_timing_differences","bank_fees","interest","reversals","approved_reconciling_items"]}'::jsonb,
   '{"primary_output":"unexplained_difference","components":["bank_ending_balance","ledger_ending_balance","deposits_in_transit","outstanding_checks","approved_adjustments","reconciled_balance","unexplained_difference"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('TREASURY_RESTRICTED_CASH_BALANCE_V1', '1.0.0', 'calculation_dsl',
   $f$unrestricted_available_cash = total_cash - legally_or_contractually_restricted_cash - pledged_cash - trust_or_escrow_cash$f$,
   'Separates unrestricted funds from restricted funds and assesses whether available-cash calculations improperly include restricted amounts.',
   '{"required_inputs":["total_cash","legally_or_contractually_restricted_cash","pledged_cash","trust_or_escrow_cash","restriction_source"]}'::jsonb,
   '{"primary_output":"unrestricted_available_cash","components":["total_cash","legally_or_contractually_restricted_cash","pledged_cash","trust_or_escrow_cash","unrestricted_available_cash"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('TREASURY_PAYMENT_EXPOSURE_V1', '1.0.0', 'calculation_dsl',
   $f$potential_exposure = SUM(payment_amount WHERE risk_classification IN approved_exposure_categories) - mitigated_amount$f$,
   'Estimates potential financial exposure from suspicious, unauthorized, or high-risk payment activity pending disposition or mitigation. (Spec gives this model only as a catalog entry -- "suspicious payment exposure, potential exposure" -- with no dedicated formula subsection; this formula follows the same exposure-minus-mitigation pattern used for the sibling TREASURY_AUTHORITY_EXCEPTION_EXPOSURE_V1 model.)',
   '{"required_inputs":["payment_population","risk_classification","authorization_status","mitigated_amount"]}'::jsonb,
   '{"primary_output":"potential_exposure","components":["payment_population_amount","risk_classification","mitigated_amount","potential_exposure"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('ECON_PREJUDGMENT_INTEREST_V1', '1.0.0', 'calculation_dsl',
   $f$-- simple interest:
interest = principal * annual_rate * (days / day_count_basis)

-- compound interest:
future_value = principal * (1 + annual_rate / compounding_periods_per_year) ^ (compounding_periods_per_year * years)
interest = future_value - principal$f$,
   'Calculates interest accrued on principal amounts over a defined period using a selected rate and compounding method. Where rates change over time, calculate separate accrual segments.',
   '{"required_inputs":["principal_schedule","accrual_start_date","accrual_end_date","interest_rate","rate_source","compounding_frequency","day_count_basis","payment_and_recovery_dates"]}'::jsonb,
   '{"primary_output":"interest_accrued","components":["principal","annual_rate","accrual_days","day_count_basis","interest_accrued","total_with_interest"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('ECON_PRESENT_VALUE_V1', '1.0.0', 'calculation_dsl',
   $f$PV = SUM(CF_t / (1 + r)^t)

-- CF_t = cash flow in period t; r = discount rate; t = elapsed time in years or periods$f$,
   'Discounts future cash flows to a selected present-value date.',
   '{"required_inputs":["forecast_cash_flows","timing_convention","discount_rate","valuation_date","periodicity","terminal_value_assumption"]}'::jsonb,
   '{"primary_output":"present_value","components":["cash_flow_schedule","discount_rate","present_value"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('GRC_EXCEPTION_RATE_V1', '1.0.0', 'calculation_dsl',
   $f$exception_rate = exception_count / tested_item_count$f$,
   'Measures the percentage of tested items that contain one or more defined exceptions. Must state whether the sample is random, stratified, judgmental, or complete-population testing; a judgmental-sample rate must never be presented as a statistically projected population rate.',
   '{"required_inputs":["tested_population","sample_size","exception_count","sample_method"]}'::jsonb,
   '{"primary_output":"exception_rate","components":["tested_item_count","exception_count","exception_rate"]}'::jsonb,
   'ad_hoc', 'approved'),

  ('GRC_SAMPLE_ERROR_EXTRAPOLATION_V1', '1.0.0', 'calculation_dsl',
   $f$projected_error = population_value * (sample_error_value / sample_value)$f$,
   'Projects sampled error to a broader population where the sampling method permits extrapolation. Must refuse to label results as statistically projectable unless the sample-method metadata supports that claim.',
   '{"required_inputs":["population_count_and_value","sample_count_and_value","sample_selection_method","strata","error_count_and_value","confidence_level"]}'::jsonb,
   '{"primary_output":"projected_error","components":["population_value","sample_value","sample_error_value","projected_error","confidence_level"]}'::jsonb,
   'ad_hoc', 'approved')

  ) as v(model_code, version_number, formula_language, formula_definition, methodology_note,
         input_contract, output_contract, calculation_frequency, approval_status)
  on v.model_code = md.model_code;

-- wire each model_definitions row to its freshly-inserted 1.0.0 version
update calculations.model_definitions md
set current_version_id = mv.id
from calculations.model_versions mv
where mv.model_id = md.id
  and mv.version_number = '1.0.0'
  and md.model_code in (
    'FX_LOSS_KNOWN_UNAUTHORIZED_DISBURSEMENTS_V1','FX_LOSS_ATTEMPTED_LOSS_V1','FX_LOSS_NET_V1',
    'FX_RESTITUTION_CANDIDATE_V1','FX_DUPLICATE_PAYMENT_RECOVERY_V1','FX_PAYROLL_OVERPAYMENT_V1',
    'FX_EXPENSE_OVERPAYMENT_V1','FX_INVENTORY_SHRINKAGE_V1','FX_UNEXPLAINED_FUNDS_V1',
    'FX_TRACE_DIRECT_V1','FX_TRACE_LOWEST_INTERMEDIATE_BALANCE_V1','TREASURY_BANK_RECONCILIATION_V1',
    'TREASURY_RESTRICTED_CASH_BALANCE_V1','TREASURY_PAYMENT_EXPOSURE_V1','ECON_PREJUDGMENT_INTEREST_V1',
    'ECON_PRESENT_VALUE_V1','GRC_EXCEPTION_RATE_V1','GRC_SAMPLE_ERROR_EXTRAPOLATION_V1'
  );
