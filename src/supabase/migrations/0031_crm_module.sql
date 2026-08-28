-- ============================================================================
-- Forens_iQ — Migration 0031: CRM module (business development)
--
-- Scope: this is the FIRM'S sales/relationship pipeline (In.Tune & Associates
-- acquiring and managing clients) — NOT the investigation subject/entity model
-- (that's canonical.entities, matter-scoped, for money-flow/fraud analysis).
-- Do not conflate the two: a "contact" here is a business-development
-- relationship; an "entity" in canonical.* is an investigation subject.
--
-- Access model: CRM data is pre-matter (a lead has no matter yet), so it is
-- TENANT-scoped, not matter-scoped. Reuses app.has_tenant_access() from 0018.
-- A `deal` won converts into a core.client_organizations row and, optionally,
-- a matter via core.provision_matter() — the existing 0022 function — closing
-- the loop from "prospect" to "billable engagement" without duplicating logic.
-- ============================================================================

begin;

create schema if not exists crm;
grant usage on schema crm to authenticated, service_role;
alter default privileges in schema crm
  grant select, insert, update, delete on tables to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- crm.companies — prospects and clients. Once won, linked to
-- core.client_organizations (the system-of-record used by matters).
-- ---------------------------------------------------------------------------
create table crm.companies (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references core.tenants(id),
  legal_name         text not null,
  dba_name           text,
  industry           text,
  website            text,
  phone              text,
  billing_address    text,
  lifecycle_stage    text not null default 'prospect'
                        check (lifecycle_stage in ('prospect','lead','opportunity','client','former_client','disqualified')),
  source             text,             -- referral, conference, inbound, outreach, RFP
  owner_user_id      uuid,             -- relationship owner / rainmaker
  client_org_id      uuid references core.client_organizations(id),  -- set once won
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1
);
create index on crm.companies(tenant_id, lifecycle_stage);
create index on crm.companies(tenant_id, owner_user_id);
create index on crm.companies using gin (legal_name extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- crm.contacts — people at a company. Independent of canonical.entities.
-- ---------------------------------------------------------------------------
create table crm.contacts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  company_id     uuid references crm.companies(id),
  first_name     text not null,
  last_name      text not null,
  title          text,
  email          extensions.citext,
  phone          text,
  linkedin_url   text,
  is_primary     boolean not null default false,
  notes          text,
  owner_user_id  uuid,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on crm.contacts(tenant_id, company_id);
create unique index on crm.contacts(tenant_id, email) where email is not null;

-- ---------------------------------------------------------------------------
-- crm.pipelines / crm.pipeline_stages — configurable kanban columns.
-- Seed a default "Business Development" pipeline below.
-- ---------------------------------------------------------------------------
create table crm.pipelines (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  pipeline_name  text not null,
  is_default     boolean not null default false,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (tenant_id, pipeline_name)
);

create table crm.pipeline_stages (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  pipeline_id    uuid not null references crm.pipelines(id),
  stage_name     text not null,          -- New, Qualifying, Proposal, Conflict Check, Engagement Letter Out, Won, Lost
  sort_order     int not null default 0,
  probability_pct numeric(5,2) not null default 0,   -- weighted-forecast %
  is_won         boolean not null default false,
  is_lost        boolean not null default false,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (pipeline_id, stage_name)
);
create index on crm.pipeline_stages(pipeline_id, sort_order);

-- ---------------------------------------------------------------------------
-- crm.deals (opportunities) + stage history (append-only audit trail of
-- pipeline movement — useful for sales-cycle analytics later).
-- ---------------------------------------------------------------------------
create table crm.deals (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references core.tenants(id),
  company_id       uuid not null references crm.companies(id),
  primary_contact_id uuid references crm.contacts(id),
  pipeline_id      uuid not null references crm.pipelines(id),
  stage_id         uuid not null references crm.pipeline_stages(id),
  deal_name        text not null,
  engagement_type  text,             -- fraud_exam, litigation, treasury, monitorship, receivership...
  estimated_value  numeric(18,2),
  currency         char(3) not null default 'USD',
  probability_pct  numeric(5,2),      -- overrides stage default if set
  expected_close_date date,
  actual_close_date   date,
  outcome          text check (outcome in ('open','won','lost','disqualified')) default 'open',
  loss_reason      text,
  owner_user_id    uuid,
  conflict_check_status text not null default 'not_started'
                     check (conflict_check_status in ('not_started','in_progress','clear','conflict_identified','waived')),
  converted_matter_id uuid references core.matters(id),   -- set by crm.win_deal()
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1
);
create index on crm.deals(tenant_id, stage_id);
create index on crm.deals(tenant_id, company_id);
create index on crm.deals(tenant_id, owner_user_id, outcome);

create table crm.deal_stage_history (
  id             uuid primary key default gen_random_uuid(),
  seq            bigint generated always as identity,
  tenant_id      uuid not null,
  deal_id        uuid not null references crm.deals(id),
  from_stage_id  uuid references crm.pipeline_stages(id),
  to_stage_id    uuid not null references crm.pipeline_stages(id),
  changed_by     uuid default app.current_user_id(),
  changed_at     timestamptz not null default now(),
  note           text
);
create index on crm.deal_stage_history(deal_id, seq);

create or replace function crm.tg_deny_mutation_local()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  raise exception 'Append-only table %.% — % is forbidden.', tg_table_schema, tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
  return null;
end $$;
create trigger tg_90_denymut before update or delete on crm.deal_stage_history
  for each row execute function crm.tg_deny_mutation_local();

-- record stage history automatically whenever deals.stage_id changes
create or replace function crm.tg_deal_stage_history()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp, crm
as $$
begin
  if (tg_op = 'INSERT') or (new.stage_id is distinct from old.stage_id) then
    insert into crm.deal_stage_history(tenant_id, deal_id, from_stage_id, to_stage_id, changed_by)
    values (new.tenant_id, new.id, case when tg_op = 'UPDATE' then old.stage_id end, new.stage_id,
            app.current_user_id());
  end if;
  return new;
end $$;
create trigger tg_stage_history after insert or update on crm.deals
  for each row execute function crm.tg_deal_stage_history();

-- ---------------------------------------------------------------------------
-- crm.activities — calls, emails, meetings, notes, tasks (lightweight; the
-- full Project Manager module in 0032 is for delivery work, not BD follow-up).
-- ---------------------------------------------------------------------------
create table crm.activities (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  company_id     uuid references crm.companies(id),
  contact_id     uuid references crm.contacts(id),
  deal_id        uuid references crm.deals(id),
  activity_type  text not null check (activity_type in ('call','email','meeting','note','task')),
  subject        text,
  body           text,
  activity_at    timestamptz not null default now(),
  due_at         timestamptz,          -- for activity_type = 'task'
  completed_at   timestamptz,
  owner_user_id  uuid,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on crm.activities(tenant_id, company_id, activity_at desc);
create index on crm.activities(tenant_id, deal_id);
create index on crm.activities(tenant_id, owner_user_id, due_at) where activity_type = 'task' and completed_at is null;

-- ---------------------------------------------------------------------------
-- crm.tags + crm.company_tags — freeform segmentation (industry vertical,
-- referral source, etc.) for list-building.
-- ---------------------------------------------------------------------------
create table crm.tags (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  tag_name       text not null,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  unique (tenant_id, tag_name)
);
create table crm.company_tags (
  company_id uuid not null references crm.companies(id),
  tag_id     uuid not null references crm.tags(id),
  primary key (company_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- Bridge function: winning a deal creates (or reuses) a client organization
-- and, if requested, provisions a matter via the EXISTING core.provision_matter
-- from 0022 — one atomic hop from "won opportunity" to "billable matter".
-- ---------------------------------------------------------------------------
create or replace function crm.win_deal(
  p_deal_id uuid,
  p_create_matter boolean default false,
  p_matter_name text default null,
  p_matter_type text default null
)
returns table (client_org_id uuid, matter_id uuid)
language plpgsql security definer
set search_path = pg_catalog, pg_temp, crm, core, app
as $$
declare
  v_deal crm.deals%rowtype;
  v_company crm.companies%rowtype;
  v_org_id uuid;
  v_matter record;
begin
  select * into v_deal from crm.deals where id = p_deal_id;
  if not found or not app.has_tenant_access(v_deal.tenant_id, 'contribute') then
    raise exception 'Deal not found or insufficient access' using errcode = '42501';
  end if;

  select * into v_company from crm.companies where id = v_deal.company_id;

  if v_company.client_org_id is null then
    insert into core.client_organizations(tenant_id, legal_name)
    values (v_deal.tenant_id, v_company.legal_name)
    returning id into v_org_id;
    update crm.companies set client_org_id = v_org_id, lifecycle_stage = 'client' where id = v_company.id;
  else
    v_org_id := v_company.client_org_id;
    update crm.companies set lifecycle_stage = 'client' where id = v_company.id;
  end if;

  update crm.deals
     set outcome = 'won', actual_close_date = coalesce(actual_close_date, current_date)
   where id = p_deal_id;

  if p_create_matter then
    if v_deal.conflict_check_status not in ('clear','waived') then
      raise exception 'Conflict check must be clear or waived before matter creation' using errcode = '23514';
    end if;
    select * into v_matter from core.provision_matter(
      v_deal.tenant_id,
      coalesce(p_matter_name, v_deal.deal_name),
      coalesce(p_matter_type, v_deal.engagement_type, 'fraud_exam'),
      'attorney_work_product',
      v_org_id
    );
    update crm.deals set converted_matter_id = v_matter.id where id = p_deal_id;
  end if;

  return query select v_org_id, v_matter.id;
end $$;

revoke all on function crm.win_deal(uuid, boolean, text, text) from public, anon;
grant execute on function crm.win_deal(uuid, boolean, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Stamp triggers + RLS (tenant-scoped, not matter-scoped)
-- ---------------------------------------------------------------------------
do $$
declare t text; tables text[] := array[
  'crm.companies','crm.contacts','crm.pipelines','crm.pipeline_stages',
  'crm.deals','crm.activities'];
begin
  foreach t in array tables loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_tenant_access(tenant_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_tenant_access(tenant_id, 'contribute'));$p$, t);
    execute format($p$create policy upd on %s for update to authenticated
        using (app.has_tenant_access(tenant_id, 'contribute'))
        with check (app.has_tenant_access(tenant_id, 'contribute'));$p$, t);
  end loop;
  -- append-only / junction tables: select + insert only
  foreach t in array array['crm.deal_stage_history','crm.tags','crm.company_tags'] loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_tenant_access(tenant_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_tenant_access(tenant_id, 'contribute'));$p$, t);
  end loop;
end $$;

-- crm.company_tags / crm.tags don't carry tenant_id directly on every row
-- pattern check: tags has tenant_id (ok). company_tags has none — scope via join.
drop policy if exists sel on crm.company_tags;
drop policy if exists ins on crm.company_tags;
alter table crm.company_tags enable row level security;
alter table crm.company_tags force row level security;
create policy sel on crm.company_tags for select to authenticated
  using (exists (select 1 from crm.companies c where c.id = company_id
                 and app.has_tenant_access(c.tenant_id, 'read')));
create policy ins on crm.company_tags for insert to authenticated
  with check (exists (select 1 from crm.companies c where c.id = company_id
                       and app.has_tenant_access(c.tenant_id, 'contribute')));

-- ---------------------------------------------------------------------------
-- Dashboard views (security_invoker so RLS applies per caller, per 0018 fix)
-- ---------------------------------------------------------------------------
create or replace view crm.v_pipeline_summary with (security_invoker = true) as
select
  d.tenant_id,
  d.pipeline_id,
  ps.stage_name,
  ps.sort_order,
  count(*) filter (where d.outcome = 'open') as open_deals,
  coalesce(sum(d.estimated_value) filter (where d.outcome = 'open'), 0) as open_pipeline_value,
  coalesce(sum(d.estimated_value * coalesce(d.probability_pct, ps.probability_pct) / 100.0)
           filter (where d.outcome = 'open'), 0) as weighted_forecast
from crm.deals d
join crm.pipeline_stages ps on ps.id = d.stage_id
group by d.tenant_id, d.pipeline_id, ps.stage_name, ps.sort_order;

create or replace view crm.v_open_followups with (security_invoker = true) as
select a.id, a.tenant_id, a.company_id, c.legal_name as company_name, a.subject, a.due_at, a.owner_user_id
from crm.activities a
join crm.companies c on c.id = a.company_id
where a.activity_type = 'task' and a.completed_at is null and a.record_status = 'active';

grant select on crm.v_pipeline_summary, crm.v_open_followups to authenticated, service_role;

commit;
