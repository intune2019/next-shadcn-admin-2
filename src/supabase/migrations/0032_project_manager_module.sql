-- ============================================================================
-- Forens_iQ — Migration 0032: Project Manager module (delivery / internal ops)
--
-- Distinct from investigation.* / workflow.tasks (0028), which track case
-- workflow (interviews, workpapers, review gates) inside a matter. This module
-- is a general Asana/ClickUp-style board: it can be attached to a matter
-- (delivery plan for an engagement) OR stand alone (internal firm project —
-- hiring, tooling, marketing). Access is per-project membership when
-- standalone, or inherited from matter_access when matter-linked.
-- ============================================================================

begin;

create schema if not exists pm;
grant usage on schema pm to authenticated, service_role;
alter default privileges in schema pm
  grant select, insert, update, delete on tables to authenticated, service_role;

create type pm.access_level as enum ('viewer','member','manager','owner');

-- ---------------------------------------------------------------------------
-- pm.projects
-- ---------------------------------------------------------------------------
create table pm.projects (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  matter_id      uuid references core.matters(id),   -- null = standalone/internal project
  project_name   text not null,
  description    text,
  status         text not null default 'planning'
                   check (status in ('planning','active','on_hold','completed','cancelled')),
  start_date     date,
  due_date       date,
  owner_user_id  uuid not null default app.current_user_id(),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on pm.projects(tenant_id, matter_id);
create index on pm.projects(tenant_id, status);

-- ---------------------------------------------------------------------------
-- pm.project_members — membership for STANDALONE projects. Ignored (but kept
-- available for @-mention/notification purposes) when the project has a
-- matter_id, since matter_access is then the source of truth.
-- ---------------------------------------------------------------------------
create table pm.project_members (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  project_id     uuid not null references pm.projects(id),
  user_id        uuid not null,
  role           pm.access_level not null default 'member',
  added_by       uuid,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (project_id, user_id)
);
create index on pm.project_members(user_id);

-- ---------------------------------------------------------------------------
-- pm.has_project_access(project, min_level) — the RLS workhorse. Matter-linked
-- projects defer entirely to app.has_matter_access(); standalone projects use
-- pm.project_members with the same ordinal-comparison pattern as core.
-- ---------------------------------------------------------------------------
create or replace function pm.has_project_access(
  p_project_id uuid,
  p_min_level pm.access_level default 'viewer'
)
returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp, pm, core, app
as $$
declare
  v_matter_id uuid;
  v_ok boolean;
begin
  select matter_id into v_matter_id from pm.projects where id = p_project_id;
  if v_matter_id is not null then
    return app.has_matter_access(
      v_matter_id,
      case p_min_level
        when 'owner'   then 'matter_admin'
        when 'manager' then 'review'
        else 'contribute'   -- viewer/member both map to at-least-contribute on a matter
      end::core.access_level
    );
  end if;

  select exists (
    select 1 from pm.project_members pmm
    where pmm.project_id = p_project_id
      and pmm.user_id = app.current_user_id()
      and pmm.record_status = 'active'
      and array_position(enum_range(null::pm.access_level), pmm.role)
          >= array_position(enum_range(null::pm.access_level), p_min_level)
  ) into v_ok;
  return coalesce(v_ok, false);
end $$;
revoke all on function pm.has_project_access(uuid, pm.access_level) from public;
grant execute on function pm.has_project_access(uuid, pm.access_level) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- pm.milestones
-- ---------------------------------------------------------------------------
create table pm.milestones (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  project_id     uuid not null references pm.projects(id),
  milestone_name text not null,
  due_date       date,
  status         text not null default 'not_started'
                   check (status in ('not_started','in_progress','at_risk','completed')),
  sort_order     int not null default 0,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on pm.milestones(project_id, sort_order);

-- ---------------------------------------------------------------------------
-- pm.tasks — supports subtasks via parent_task_id (one level is typical for
-- shadcn kanban UIs; the FK allows deeper nesting if the frontend wants it).
-- ---------------------------------------------------------------------------
create table pm.tasks (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  project_id       uuid not null references pm.projects(id),
  milestone_id     uuid references pm.milestones(id),
  parent_task_id   uuid references pm.tasks(id),
  title            text not null,
  description      text,
  status           text not null default 'backlog'
                     check (status in ('backlog','todo','in_progress','in_review','blocked','done','cancelled')),
  priority         text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  assignee_user_id uuid,
  reporter_user_id uuid not null default app.current_user_id(),
  start_date       date,
  due_date         date,
  estimated_hours  numeric(6,2),
  actual_hours     numeric(6,2) not null default 0,   -- rolled up by pm.log_time()
  sort_order       int not null default 0,
  completed_at     timestamptz,
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1
);
create index on pm.tasks(project_id, status, sort_order);
create index on pm.tasks(tenant_id, assignee_user_id, status) where record_status = 'active';
create index on pm.tasks(parent_task_id);

create or replace function pm.tg_task_complete()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  if new.status = 'done' and (old.status is distinct from 'done') then
    new.completed_at := now();
  elsif new.status <> 'done' then
    new.completed_at := null;
  end if;
  return new;
end $$;
create trigger tg_complete before update on pm.tasks
  for each row execute function pm.tg_task_complete();

-- ---------------------------------------------------------------------------
-- pm.task_comments — append-only, matches the append-only convention used
-- for chain-of-custody / audit events elsewhere in this platform.
-- ---------------------------------------------------------------------------
create table pm.task_comments (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  project_id     uuid not null references pm.projects(id),
  task_id        uuid not null references pm.tasks(id),
  body           text not null,
  author_user_id uuid not null default app.current_user_id(),
  created_at     timestamptz not null default now()
);
create index on pm.task_comments(task_id, created_at);
create trigger tg_90_denymut before update or delete on pm.task_comments
  for each row execute function app.tg_deny_mutation();

-- ---------------------------------------------------------------------------
-- pm.task_dependencies — blocks / blocked_by / relates_to
-- ---------------------------------------------------------------------------
create table pm.task_dependencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  project_id       uuid not null references pm.projects(id),
  task_id          uuid not null references pm.tasks(id),
  depends_on_task_id uuid not null references pm.tasks(id),
  dependency_type  text not null default 'blocks' check (dependency_type in ('blocks','blocked_by','relates_to')),
  created_at       timestamptz not null default now(),
  created_by       uuid,
  unique (task_id, depends_on_task_id, dependency_type),
  check (task_id <> depends_on_task_id)
);
create index on pm.task_dependencies(task_id);
create index on pm.task_dependencies(depends_on_task_id);

-- ---------------------------------------------------------------------------
-- pm.time_entries — feeds pm.tasks.actual_hours; billable flag lets this
-- double as a source for matter billing later without a separate module.
-- ---------------------------------------------------------------------------
create table pm.time_entries (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  project_id     uuid not null references pm.projects(id),
  task_id        uuid references pm.tasks(id),
  user_id        uuid not null default app.current_user_id(),
  entry_date     date not null default current_date,
  minutes        int not null check (minutes > 0),
  note           text,
  billable       boolean not null default true,
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on pm.time_entries(project_id, entry_date);
create index on pm.time_entries(user_id, entry_date);

create or replace function pm.tg_rollup_actual_hours()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp, pm
as $$
begin
  if new.task_id is not null then
    update pm.tasks
       set actual_hours = coalesce((
         select sum(minutes) / 60.0 from pm.time_entries where task_id = new.task_id
       ), 0)
     where id = new.task_id;
  end if;
  return new;
end $$;
create trigger tg_rollup after insert on pm.time_entries
  for each row execute function pm.tg_rollup_actual_hours();

-- ---------------------------------------------------------------------------
-- Convenience functions: create a project (with owner membership) and log
-- time, mirroring the core.provision_matter() atomic-bootstrap pattern.
-- ---------------------------------------------------------------------------
create or replace function pm.create_project(
  p_tenant_id uuid,
  p_project_name text,
  p_matter_id uuid default null,
  p_description text default null,
  p_due_date date default null
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, pg_temp, pm, core, app
as $$
declare v_id uuid; v_user uuid := app.current_user_id();
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_matter_id is not null and not app.has_matter_access(p_matter_id, 'contribute') then
    raise exception 'Contribute access to the matter is required' using errcode = '42501';
  end if;
  if p_matter_id is null and not app.has_tenant_access(p_tenant_id, 'read') then
    raise exception 'Tenant membership is required' using errcode = '42501';
  end if;

  insert into pm.projects(tenant_id, matter_id, project_name, description, due_date, owner_user_id, created_by)
  values (p_tenant_id, p_matter_id, p_project_name, p_description, p_due_date, v_user, v_user)
  returning id into v_id;

  if p_matter_id is null then
    insert into pm.project_members(tenant_id, project_id, user_id, role, added_by, created_by)
    values (p_tenant_id, v_id, v_user, 'owner', v_user, v_user);
  end if;

  return v_id;
end $$;
revoke all on function pm.create_project(uuid, text, uuid, text, date) from public, anon;
grant execute on function pm.create_project(uuid, text, uuid, text, date) to authenticated;

create or replace function pm.log_time(
  p_task_id uuid, p_minutes int, p_note text default null, p_billable boolean default true
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, pg_temp, pm, app
as $$
declare v_task pm.tasks%rowtype; v_id uuid;
begin
  select * into v_task from pm.tasks where id = p_task_id;
  if not found or not pm.has_project_access(v_task.project_id, 'member') then
    raise exception 'Task not found or insufficient access' using errcode = '42501';
  end if;
  insert into pm.time_entries(tenant_id, project_id, task_id, user_id, minutes, note, billable, created_by)
  values (v_task.tenant_id, v_task.project_id, p_task_id, app.current_user_id(), p_minutes, p_note, p_billable,
          app.current_user_id())
  returning id into v_id;
  return v_id;
end $$;
revoke all on function pm.log_time(uuid, int, text, boolean) from public, anon;
grant execute on function pm.log_time(uuid, int, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Stamp triggers + RLS
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['pm.projects','pm.project_members','pm.milestones','pm.tasks'] loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
  end loop;
end $$;

alter table pm.projects enable row level security;
alter table pm.projects force row level security;
create policy sel on pm.projects for select to authenticated
  using (pm.has_project_access(id, 'viewer'));
create policy ins on pm.projects for insert to authenticated
  with check (
    (matter_id is not null and app.has_matter_access(matter_id, 'contribute'))
    or (matter_id is null and app.has_tenant_access(tenant_id, 'read'))
  );
create policy upd on pm.projects for update to authenticated
  using (pm.has_project_access(id, 'manager'))
  with check (pm.has_project_access(id, 'manager'));

do $$
declare t text; tables text[] := array[
  'pm.project_members','pm.milestones','pm.tasks','pm.task_dependencies'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (pm.has_project_access(project_id, ''viewer''));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (pm.has_project_access(project_id, ''member''));$p$, t);
    execute format($p$create policy upd on %s for update to authenticated
        using (pm.has_project_access(project_id, ''member''))
        with check (pm.has_project_access(project_id, ''member''));$p$, t);
  end loop;
  -- append-only tables: select + insert only
  foreach t in array array['pm.task_comments','pm.time_entries'] loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (pm.has_project_access(project_id, ''viewer''));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (pm.has_project_access(project_id, ''member''));$p$, t);
  end loop;
end $$;

-- project_members: only managers/owners manage membership
create policy mgmt_upd on pm.project_members for update to authenticated
  using (pm.has_project_access(project_id, 'manager'))
  with check (pm.has_project_access(project_id, 'manager'));

-- ---------------------------------------------------------------------------
-- Views for the Next.js/shadcn board + workload widgets
-- ---------------------------------------------------------------------------
create or replace view pm.v_kanban_board with (security_invoker = true) as
select t.id, t.project_id, t.milestone_id, t.parent_task_id, t.title, t.status, t.priority,
       t.assignee_user_id, t.due_date, t.sort_order, t.estimated_hours, t.actual_hours,
       (select count(*) from pm.task_comments c where c.task_id = t.id) as comment_count,
       (select count(*) from pm.task_dependencies d where d.task_id = t.id and d.dependency_type = 'blocked_by') as blocking_count
from pm.tasks t
where t.record_status = 'active';

create or replace view pm.v_my_tasks with (security_invoker = true) as
select t.id, t.project_id, p.project_name, t.title, t.status, t.priority, t.due_date
from pm.tasks t
join pm.projects p on p.id = t.project_id
where t.assignee_user_id = app.current_user_id()
  and t.status not in ('done','cancelled')
  and t.record_status = 'active';

create or replace view pm.v_project_workload with (security_invoker = true) as
select t.project_id, t.assignee_user_id,
       count(*) filter (where t.status not in ('done','cancelled')) as open_tasks,
       coalesce(sum(t.estimated_hours) filter (where t.status not in ('done','cancelled')), 0) as estimated_hours_remaining,
       coalesce(sum(t.actual_hours), 0) as actual_hours_logged
from pm.tasks t
where t.record_status = 'active'
group by t.project_id, t.assignee_user_id;

grant select on pm.v_kanban_board, pm.v_my_tasks, pm.v_project_workload to authenticated, service_role;

commit;
