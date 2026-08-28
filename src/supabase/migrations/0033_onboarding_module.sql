-- ============================================================================
-- Forens_iQ — Migration 0033: Onboarding module (client + employee)
--
-- Two onboarding "scopes" share one engine:
--   client_matter — post-win checklist for standing up a new engagement
--                   (conflict resolution, engagement letter execution,
--                    evidence kickoff, access provisioning, billing setup).
--   employee      — new team member joining the firm or a specific matter.
-- Template-driven so ops/HR can edit checklists from the UI without a
-- migration, same rationale as crm.pipeline_stages being data, not an enum.
-- ============================================================================

begin;

create schema if not exists onboarding;
grant usage on schema onboarding to authenticated, service_role;
alter default privileges in schema onboarding
  grant select, insert, update, delete on tables to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- onboarding.templates / template_items — reusable checklists.
-- ---------------------------------------------------------------------------
create table onboarding.templates (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  template_code  text not null,          -- 'fraud_exam_client_onboarding', 'employee_standard'
  template_name  text not null,
  scope          text not null check (scope in ('client_matter','employee')),
  matter_type    text,                   -- filter for client_matter scope; null = any
  is_active      boolean not null default true,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (tenant_id, template_code)
);

create table onboarding.template_items (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references core.tenants(id),
  template_id      uuid not null references onboarding.templates(id),
  item_title       text not null,
  item_description text,
  category         text not null,        -- conflict_check, engagement_letter, evidence_kickoff,
                                          -- access_provisioning, billing_setup, team_assignment,
                                          -- compliance, equipment, training
  default_owner_role text,               -- matter_admin, approve, contribute (maps loosely to core.access_level)
  is_required      boolean not null default true,
  due_offset_days  int not null default 0,   -- days after onboarding start
  sort_order       int not null default 0,
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1
);
create index on onboarding.template_items(template_id, sort_order);

-- ---------------------------------------------------------------------------
-- onboarding.instances / instance_items — the running checklist.
-- Exactly one of matter_id / user_id is set, matching scope.
-- ---------------------------------------------------------------------------
create table onboarding.instances (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  template_id    uuid not null references onboarding.templates(id),
  scope          text not null check (scope in ('client_matter','employee')),
  matter_id      uuid references core.matters(id),   -- set when scope = client_matter
  user_id        uuid,                                 -- set when scope = employee
  status         text not null default 'not_started'
                   check (status in ('not_started','in_progress','completed','on_hold')),
  owner_user_id  uuid,
  started_at     timestamptz not null default now(),
  completed_at   timestamptz,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  check ((scope = 'client_matter' and matter_id is not null and user_id is null)
      or (scope = 'employee' and user_id is not null and matter_id is null))
);
create index on onboarding.instances(tenant_id, matter_id);
create index on onboarding.instances(tenant_id, user_id);

create table onboarding.instance_items (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  instance_id      uuid not null references onboarding.instances(id),
  template_item_id uuid references onboarding.template_items(id),
  item_title       text not null,
  item_description text,
  category         text not null,
  is_required      boolean not null default true,
  status           text not null default 'pending'
                     check (status in ('pending','in_progress','completed','skipped','blocked')),
  assignee_user_id uuid,
  due_date         date,
  completed_at     timestamptz,
  completed_by     uuid,
  note             text,
  sort_order       int not null default 0,
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1
);
create index on onboarding.instance_items(instance_id, sort_order);
create index on onboarding.instance_items(assignee_user_id, status) where status not in ('completed','skipped');

-- ---------------------------------------------------------------------------
-- onboarding.has_instance_access — same idiom as app.has_matter_access /
-- pm.has_project_access. client_matter defers to matter_access; employee
-- rows are visible to the employee themselves or a tenant contribute+ user
-- (HR / matter_admin-equivalent), never to arbitrary tenant members.
-- ---------------------------------------------------------------------------
create or replace function onboarding.has_instance_access(
  p_instance_id uuid,
  p_min_level core.access_level default 'read'
)
returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp, onboarding, core, app
as $$
declare
  v_scope text; v_matter_id uuid; v_user_id uuid; v_tenant_id uuid;
begin
  select scope, matter_id, user_id, tenant_id
    into v_scope, v_matter_id, v_user_id, v_tenant_id
    from onboarding.instances where id = p_instance_id;

  if v_scope = 'client_matter' then
    return app.has_matter_access(v_matter_id, p_min_level);
  end if;

  -- employee scope
  if v_user_id = app.current_user_id() and p_min_level in ('read','contribute') then
    return true;   -- employees may view/update their own checklist items
  end if;
  return app.has_tenant_access(v_tenant_id, onboarding.greatest_access(p_min_level, 'contribute'));
end $$;

-- small ordinal helper so the employee-scope branch never accepts a *lower*
-- bar than 'contribute' even if the caller asked for 'read'. Schema-qualified
-- (and referenced schema-qualified above) since has_instance_access's
-- search_path is pinned to onboarding, core, app — no public.
create or replace function onboarding.greatest_access(a core.access_level, b core.access_level)
returns core.access_level
language sql immutable
set search_path = pg_catalog, pg_temp, core
as $$
  select case when array_position(enum_range(null::core.access_level), a)
              >= array_position(enum_range(null::core.access_level), b)
         then a else b end
$$;

revoke all on function onboarding.has_instance_access(uuid, core.access_level) from public;
grant execute on function onboarding.has_instance_access(uuid, core.access_level) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- onboarding.start_onboarding — instantiate a checklist from a template.
-- ---------------------------------------------------------------------------
create or replace function onboarding.start_onboarding(
  p_tenant_id uuid,
  p_template_code text,
  p_matter_id uuid default null,
  p_user_id uuid default null,
  p_owner_user_id uuid default null
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, pg_temp, onboarding, core, app
as $$
declare
  v_template onboarding.templates%rowtype;
  v_instance_id uuid;
  v_scope text := case when p_matter_id is not null then 'client_matter' else 'employee' end;
begin
  if p_matter_id is null and p_user_id is null then
    raise exception 'Either matter_id or user_id is required' using errcode = '22023';
  end if;
  if p_matter_id is not null and not app.has_matter_access(p_matter_id, 'contribute') then
    raise exception 'Contribute access to the matter is required' using errcode = '42501';
  end if;
  if p_matter_id is null and not app.has_tenant_access(p_tenant_id, 'contribute') then
    raise exception 'Tenant contribute access is required' using errcode = '42501';
  end if;

  select * into v_template from onboarding.templates
   where tenant_id = p_tenant_id and template_code = p_template_code and is_active;
  if not found then
    raise exception 'Onboarding template % not found or inactive', p_template_code using errcode = '22023';
  end if;

  insert into onboarding.instances(tenant_id, template_id, scope, matter_id, user_id, owner_user_id, created_by)
  values (p_tenant_id, v_template.id, v_scope, p_matter_id, p_user_id,
          coalesce(p_owner_user_id, app.current_user_id()), app.current_user_id())
  returning id into v_instance_id;

  insert into onboarding.instance_items(
    tenant_id, instance_id, template_item_id, item_title, item_description,
    category, is_required, due_date, sort_order, created_by)
  select p_tenant_id, v_instance_id, ti.id, ti.item_title, ti.item_description,
         ti.category, ti.is_required, current_date + ti.due_offset_days, ti.sort_order,
         app.current_user_id()
    from onboarding.template_items ti
   where ti.template_id = v_template.id and ti.record_status = 'active'
   order by ti.sort_order;

  update onboarding.instances set status = 'in_progress' where id = v_instance_id;
  return v_instance_id;
end $$;
revoke all on function onboarding.start_onboarding(uuid, text, uuid, uuid, uuid) from public, anon;
grant execute on function onboarding.start_onboarding(uuid, text, uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- onboarding.complete_item — mark one checklist item done; auto-completes
-- the parent instance once every required item is done/skipped.
-- ---------------------------------------------------------------------------
create or replace function onboarding.complete_item(
  p_item_id uuid, p_note text default null, p_skip boolean default false
)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, onboarding, app
as $$
declare v_item onboarding.instance_items%rowtype; v_remaining int;
begin
  select * into v_item from onboarding.instance_items where id = p_item_id;
  if not found or not onboarding.has_instance_access(v_item.instance_id, 'contribute') then
    raise exception 'Item not found or insufficient access' using errcode = '42501';
  end if;

  update onboarding.instance_items
     set status = case when p_skip then 'skipped' else 'completed' end,
         completed_at = now(), completed_by = app.current_user_id(), note = coalesce(p_note, note)
   where id = p_item_id;

  select count(*) into v_remaining
    from onboarding.instance_items
   where instance_id = v_item.instance_id and is_required
     and status not in ('completed','skipped') and record_status = 'active';

  if v_remaining = 0 then
    update onboarding.instances
       set status = 'completed', completed_at = now()
     where id = v_item.instance_id and status <> 'completed';
  end if;
end $$;
revoke all on function onboarding.complete_item(uuid, text, boolean) from public, anon;
grant execute on function onboarding.complete_item(uuid, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Stamp triggers + RLS
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['onboarding.templates','onboarding.template_items',
                            'onboarding.instances','onboarding.instance_items'] loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
  end loop;
end $$;

alter table onboarding.templates enable row level security;
alter table onboarding.templates force row level security;
create policy sel on onboarding.templates for select to authenticated
  using (app.has_tenant_access(tenant_id, 'read'));
create policy ins on onboarding.templates for insert to authenticated
  with check (app.has_tenant_access(tenant_id, 'contribute'));
create policy upd on onboarding.templates for update to authenticated
  using (app.has_tenant_access(tenant_id, 'contribute'))
  with check (app.has_tenant_access(tenant_id, 'contribute'));

alter table onboarding.template_items enable row level security;
alter table onboarding.template_items force row level security;
create policy sel on onboarding.template_items for select to authenticated
  using (app.has_tenant_access(tenant_id, 'read'));
create policy ins on onboarding.template_items for insert to authenticated
  with check (app.has_tenant_access(tenant_id, 'contribute'));
create policy upd on onboarding.template_items for update to authenticated
  using (app.has_tenant_access(tenant_id, 'contribute'))
  with check (app.has_tenant_access(tenant_id, 'contribute'));

alter table onboarding.instances enable row level security;
alter table onboarding.instances force row level security;
create policy sel on onboarding.instances for select to authenticated
  using (onboarding.has_instance_access(id, 'read'));
create policy upd on onboarding.instances for update to authenticated
  using (onboarding.has_instance_access(id, 'contribute'))
  with check (onboarding.has_instance_access(id, 'contribute'));

alter table onboarding.instance_items enable row level security;
alter table onboarding.instance_items force row level security;
create policy sel on onboarding.instance_items for select to authenticated
  using (onboarding.has_instance_access(instance_id, 'read'));
create policy upd on onboarding.instance_items for update to authenticated
  using (onboarding.has_instance_access(instance_id, 'contribute'))
  with check (onboarding.has_instance_access(instance_id, 'contribute'));

-- ---------------------------------------------------------------------------
-- Bridge: extend crm.win_deal so winning a deal can auto-kick off client
-- onboarding in the same atomic call (redefines the 0031 function).
-- ---------------------------------------------------------------------------
create or replace function crm.win_deal(
  p_deal_id uuid,
  p_create_matter boolean default false,
  p_matter_name text default null,
  p_matter_type text default null,
  p_start_onboarding boolean default false,
  p_onboarding_template_code text default null
)
returns table (client_org_id uuid, matter_id uuid, onboarding_instance_id uuid)
language plpgsql security definer
set search_path = pg_catalog, pg_temp, crm, core, app, onboarding
as $$
declare
  v_deal crm.deals%rowtype;
  v_company crm.companies%rowtype;
  v_org_id uuid;
  v_matter record;
  v_onboarding_id uuid;
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

    if p_start_onboarding then
      v_onboarding_id := onboarding.start_onboarding(
        v_deal.tenant_id,
        coalesce(p_onboarding_template_code, coalesce(p_matter_type, v_deal.engagement_type, 'fraud_exam') || '_client_onboarding'),
        v_matter.id
      );
    end if;
  end if;

  return query select v_org_id, v_matter.id, v_onboarding_id;
end $$;

revoke all on function crm.win_deal(uuid, boolean, text, text, boolean, text) from public, anon;
grant execute on function crm.win_deal(uuid, boolean, text, text, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- View + seed templates
-- ---------------------------------------------------------------------------
create or replace view onboarding.v_my_checklist_items with (security_invoker = true) as
select i.id, i.instance_id, oi.scope, oi.matter_id, m.matter_name, i.item_title, i.category,
       i.status, i.due_date
from onboarding.instance_items i
join onboarding.instances oi on oi.id = i.instance_id
left join core.matters m on m.id = oi.matter_id
where i.assignee_user_id = app.current_user_id()
  and i.status not in ('completed','skipped')
  and i.record_status = 'active';
grant select on onboarding.v_my_checklist_items to authenticated, service_role;

-- Seed helper: call this once per tenant to install the default templates.
create or replace function onboarding.seed_default_templates(p_tenant_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, onboarding, app
as $$
declare v_t uuid; v_e uuid;
begin
  if not app.has_tenant_access(p_tenant_id, 'contribute') then
    raise exception 'Tenant contribute access required' using errcode = '42501';
  end if;

  insert into onboarding.templates(tenant_id, template_code, template_name, scope, matter_type)
  values (p_tenant_id, 'fraud_exam_client_onboarding', 'Fraud Examination — Client Onboarding', 'client_matter', 'fraud_exam')
  on conflict (tenant_id, template_code) do nothing
  returning id into v_t;
  if v_t is null then select id into v_t from onboarding.templates
    where tenant_id = p_tenant_id and template_code = 'fraud_exam_client_onboarding'; end if;

  insert into onboarding.template_items(tenant_id, template_id, item_title, category, default_owner_role, due_offset_days, sort_order)
  values
    (p_tenant_id, v_t, 'Execute conflict-of-interest check', 'conflict_check', 'matter_admin', 0, 1),
    (p_tenant_id, v_t, 'Countersign engagement letter / authority instrument', 'engagement_letter', 'matter_admin', 2, 2),
    (p_tenant_id, v_t, 'Provision matter access for assigned team', 'access_provisioning', 'matter_admin', 2, 3),
    (p_tenant_id, v_t, 'Send evidence-request list to client custodian(s)', 'evidence_kickoff', 'contribute', 3, 4),
    (p_tenant_id, v_t, 'Confirm billing authority and rate schedule', 'billing_setup', 'matter_admin', 3, 5),
    (p_tenant_id, v_t, 'Hold kickoff call and confirm scope/deadlines', 'team_assignment', 'contribute', 5, 6)
  on conflict do nothing;

  insert into onboarding.templates(tenant_id, template_code, template_name, scope)
  values (p_tenant_id, 'employee_standard', 'Standard Employee Onboarding', 'employee')
  on conflict (tenant_id, template_code) do nothing
  returning id into v_e;
  if v_e is null then select id into v_e from onboarding.templates
    where tenant_id = p_tenant_id and template_code = 'employee_standard'; end if;

  insert into onboarding.template_items(tenant_id, template_id, item_title, category, due_offset_days, sort_order)
  values
    (p_tenant_id, v_e, 'Execute confidentiality / NDA agreement', 'compliance', 0, 1),
    (p_tenant_id, v_e, 'Provision Supabase auth account and MFA', 'access_provisioning', 0, 2),
    (p_tenant_id, v_e, 'Review chain-of-custody and evidence-handling policy', 'training', 1, 3),
    (p_tenant_id, v_e, 'Assign initial matter access per manager', 'team_assignment', 2, 4),
    (p_tenant_id, v_e, 'Complete platform walkthrough (RLS/confidentiality model)', 'training', 3, 5),
    (p_tenant_id, v_e, 'Issue equipment / credentials', 'equipment', 3, 6)
  on conflict do nothing;
end $$;
revoke all on function onboarding.seed_default_templates(uuid) from public, anon;
grant execute on function onboarding.seed_default_templates(uuid) to authenticated, service_role;

commit;
