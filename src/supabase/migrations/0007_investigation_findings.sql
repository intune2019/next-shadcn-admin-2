-- ============================================================================
-- Migration 0007: investigation object hierarchy + whistleblower reports
-- Enforces the spec's legal separation:
--   allegation -> lead/hypothesis -> fact -> finding -> conclusion -> recommendation
-- An allegation can NEVER equal a finding. A finding cannot be "substantiated"
-- without a reviewer, evidence set, and methodology (guarded at the app layer;
-- schema keeps the review columns mandatory-by-convention).
-- ============================================================================

create table investigation.allegations (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  allegation_no  text not null,
  reported_conduct text,
  reported_at    timestamptz,
  reporter_ref   text,                 -- opaque; identity (if any) lives in the WB vault
  scheme_category text,                -- asset_misappropriation, corruption, financial_stmt, treasury, regulatory
  status         text not null default 'reported',
  -- reported|triaged|under_review|evidence_developing|substantiated|
  -- partially_substantiated|unsubstantiated|unable_to_determine|closed
  confidentiality core.confidentiality_level not null default 'attorney_work_product',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (matter_id, allegation_no)
);
create index on investigation.allegations(matter_id);

create table investigation.leads (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  allegation_id  uuid references investigation.allegations(id),
  lead_type      text,                 -- hypothesis | lead | anomaly
  statement      text,
  status         text not null default 'open',   -- open|supported|not_supported|inconclusive|superseded
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on investigation.leads(matter_id, allegation_id);

create table investigation.facts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  statement      text not null,
  fact_type      text,                 -- observed|documented|calculated|witness|inferred
  confidence     text,                 -- high|medium|low
  contrary_evidence text,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on investigation.facts(matter_id);

-- each fact must cite at least one evidence/analytic source (enforced in app)
create table investigation.fact_sources (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  fact_id        uuid not null references investigation.facts(id),
  source_kind    text not null,        -- evidence_item | transaction | rule_hit | calculation_run
  source_id      uuid not null,
  source_locator text,                 -- page/row/worksheet pointer
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on investigation.fact_sources(fact_id);

create table investigation.findings (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  allegation_id  uuid references investigation.allegations(id),
  title          text not null,
  question_addressed text,
  conclusion_status text not null default 'draft',
  -- draft|under_review|supported|partially_supported|not_supported|inconclusive|superseded|withdrawn|final
  methodology    text,
  financial_impact numeric(20,4),
  currency       char(3),
  classification text,                 -- substantiated, control_deficiency, policy_violation, referral_recommended...
  reviewed_by    uuid,                 -- required before 'supported'/'final'
  reviewed_at    timestamptz,
  approved_by    uuid,
  approved_at    timestamptz,
  confidentiality core.confidentiality_level not null default 'attorney_work_product',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on investigation.findings(matter_id, allegation_id);

create table investigation.finding_sources (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  finding_id     uuid not null references investigation.findings(id),
  fact_id        uuid references investigation.facts(id),
  is_contrary    boolean not null default false,   -- track contrary evidence explicitly
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on investigation.finding_sources(finding_id);

create table investigation.recommendations (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  finding_id     uuid references investigation.findings(id),
  recommendation text not null,
  owner_user_id  uuid,
  target_date    date,
  status         text not null default 'open',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on investigation.recommendations(matter_id, finding_id);

-- ---------------------------------------------------------------------------
-- Guard trigger: a finding cannot reach a substantive conclusion without a
-- reviewer and at least one linked fact. Belt-and-braces beside app logic.
-- ---------------------------------------------------------------------------
create or replace function investigation.tg_finding_guard()
returns trigger language plpgsql as $$
begin
  if new.conclusion_status in ('supported','partially_supported','final') then
    if new.reviewed_by is null then
      raise exception 'Finding % cannot be % without a reviewer', new.id, new.conclusion_status
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from investigation.finding_sources fs
                   where fs.finding_id = new.id and fs.is_contrary = false) then
      raise exception 'Finding % cannot be % without at least one supporting fact', new.id, new.conclusion_status
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

create trigger tg_guard before update on investigation.findings
  for each row execute function investigation.tg_finding_guard();

-- ---------------------------------------------------------------------------
-- Whistleblower reports (body). Identity is in security.* (0004). This table
-- is readable by matter members; the identity is NOT reachable from here.
-- ---------------------------------------------------------------------------
create table investigation.whistleblower_reports (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid references core.matters(id),
  report_code    text not null,
  narrative      text,
  is_ongoing     boolean,
  retaliation_fear boolean,
  received_at    timestamptz not null default now(),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (tenant_id, report_code)
);

-- ---------------------------------------------------------------------------
-- Stamp + RLS
-- ---------------------------------------------------------------------------
do $$
declare t text; tables text[] := array[
  'investigation.allegations','investigation.leads','investigation.facts',
  'investigation.findings','investigation.recommendations',
  'investigation.whistleblower_reports'];
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
    execute format($p$create policy upd on %s for update to authenticated
        using (app.has_matter_access(matter_id, 'contribute'))
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
  -- source-link tables (no matter-admin needed, contribute suffices)
  foreach t in array array['investigation.fact_sources','investigation.finding_sources'] loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;
