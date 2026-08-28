-- ============================================================================
-- Migration 0008: detection rule registry + explainable alerts
-- A rule != an alert != a finding. Rules produce hits; hits group into alerts;
-- only a reviewed alert can be promoted (via a fact) toward a finding.
-- Rule codes use domain prefixes (AP_, TREASURY_, PAYROLL_, PROC_, GL_, GRC_);
-- the fraud-exam module elsewhere uses `fe_` — `fx_` stays currency-only.
-- ============================================================================

create table rules.rule_definitions (
  id             uuid primary key default gen_random_uuid(),
  rule_code      text not null,        -- AP_DUPLICATE_INVOICE
  rule_name      text not null,
  domain         text,                 -- AP, treasury, payroll, procurement, GL, GRC, AML
  risk_category  text,
  description    text,
  business_rationale text,
  rule_type      text,                 -- deterministic, statistical, fuzzy, graph, temporal, scoring
  status         text not null default 'draft',   -- draft|testing|approved|suspended|retired
  owner_user_id  uuid,
  reviewer_role  text,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  approved_at    timestamptz,
  approved_by    uuid,
  current_version_id uuid,
  unique (rule_code)
);

create table rules.rule_versions (
  id               uuid primary key default gen_random_uuid(),
  rule_id          uuid not null references rules.rule_definitions(id),
  version_number   text not null,      -- semver 1.2.0
  logic_language   text not null default 'sql',
  logic_sql        text not null,      -- parameterized, read-only, tenant/matter bound
  logic_checksum   bytea,
  parameter_schema jsonb,
  default_parameters jsonb,
  explainability_template text,
  approval_status  text not null default 'draft',
  approved_by      uuid,
  approved_at      timestamptz,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  unique (rule_id, version_number)
);
alter table rules.rule_definitions
  add constraint rule_current_version_fk
  foreign key (current_version_id) references rules.rule_versions(id);

-- auto-checksum the frozen SQL so an approved rule can't be silently edited
create or replace function rules.tg_version_checksum()
returns trigger language plpgsql as $$
begin
  new.logic_checksum := extensions.digest(new.logic_sql, 'sha256');
  return new;
end $$;
create trigger tg_checksum before insert or update on rules.rule_versions
  for each row execute function rules.tg_version_checksum();

create table rules.rule_runs (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  matter_id        uuid not null references core.matters(id),
  rule_version_id  uuid not null references rules.rule_versions(id),
  dataset_version_ids jsonb,           -- frozen population snapshot pointers
  parameter_values jsonb,
  run_type         text default 'manual',   -- scheduled|manual|backfill|validation|test
  status           text default 'queued',
  records_tested   bigint,
  hits_created     bigint,
  started_at       timestamptz,
  finished_at      timestamptz,
  run_sql_checksum bytea,
  created_at       timestamptz not null default now(),
  created_by       uuid
);
create index on rules.rule_runs(matter_id);

-- ---------------------------------------------------------------------------
-- analytics.rule_hits : every hit carries its full explanation + lineage.
-- ---------------------------------------------------------------------------
create table analytics.rule_hits (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  matter_id        uuid not null references core.matters(id),
  rule_run_id      uuid references rules.rule_runs(id),
  rule_version_id  uuid references rules.rule_versions(id),
  primary_object_type text,            -- invoice, payment, vendor, employee, journal_entry
  primary_object_id uuid,
  primary_business_key text,
  event_date       date,
  amount_base      numeric(20,4),
  currency_base    char(3),
  severity         text,               -- critical|high|medium|low|informational
  risk_score       numeric(5,2),
  confidence_score numeric(5,2),
  reason_codes     jsonb,
  explanation      text,
  evidence_references jsonb,
  feature_snapshot jsonb,              -- every variable used, for reproducibility
  review_status    text not null default 'new',
  created_at       timestamptz not null default now(),
  created_by       uuid
);
create index on analytics.rule_hits(matter_id, primary_object_type, primary_object_id);

-- ---------------------------------------------------------------------------
-- investigation.alerts : grouped, reviewable case objects.
-- ---------------------------------------------------------------------------
create table investigation.alerts (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  matter_id        uuid not null references core.matters(id),
  alert_title      text,
  alert_type       text,               -- transaction|vendor|person|account|control|relationship
  primary_subject_id uuid,
  aggregate_risk_score numeric(5,2),
  aggregate_severity text,
  financial_exposure numeric(20,4),
  review_status    text not null default 'new',   -- new|triaged|assigned|under_review|escalated|closed
  assigned_to      uuid,
  disposition      text,               -- false_positive|explained|control_gap|linked_to_finding|referred...
  related_allegation_id uuid references investigation.allegations(id),
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1
);
create index on investigation.alerts(matter_id, review_status);

create table investigation.alert_hits (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  alert_id       uuid not null references investigation.alerts(id),
  rule_hit_id    uuid not null references analytics.rule_hits(id),
  unique (alert_id, rule_hit_id)
);

-- ---------------------------------------------------------------------------
-- RLS + stamps for matter-scoped rule tables
-- ---------------------------------------------------------------------------
do $$
declare t text; tables text[] := array[
  'rules.rule_runs','analytics.rule_hits','investigation.alerts'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
  -- alerts also updatable
  execute 'create trigger tg_stamp before insert or update on investigation.alerts
    for each row execute function app.tg_stamp_row()';
  execute $p$create policy upd on investigation.alerts for update to authenticated
      using (app.has_matter_access(matter_id, 'review'))
      with check (app.has_matter_access(matter_id, 'review'));$p$;
  execute 'alter table investigation.alert_hits enable row level security';
  execute 'alter table investigation.alert_hits force row level security';
  execute $p$create policy sel on investigation.alert_hits for select to authenticated
      using (app.has_matter_access(matter_id, 'read'));$p$;
  execute $p$create policy ins on investigation.alert_hits for insert to authenticated
      with check (app.has_matter_access(matter_id, 'contribute'));$p$;
end $$;

-- rule registry is global-ish (shared library); readable by any authenticated
-- user, writable only by service_role / rule owners (kept simple: read-only to
-- authenticated, all to service_role).
alter table rules.rule_definitions enable row level security;
alter table rules.rule_versions    enable row level security;
create policy sel on rules.rule_definitions for select to authenticated using (true);
create policy sel on rules.rule_versions    for select to authenticated using (true);
create policy all_sr on rules.rule_definitions for all to service_role using (true) with check (true);
create policy all_sr2 on rules.rule_versions    for all to service_role using (true) with check (true);
