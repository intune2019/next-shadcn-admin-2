-- ============================================================================
-- Migration 0003: core tenancy, matters, authority, access model
-- Every business table carries the mandatory standard columns from the spec.
-- RLS is enabled AND forced (forced so even the table owner is subject to
-- policy — defense against a platform insider, fix #C).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- core.tenants  (the firm / operator instance)
-- ---------------------------------------------------------------------------
create table core.tenants (
  id             uuid primary key default gen_random_uuid(),
  tenant_name    text not null,
  data_region    text not null default 'us-east',   -- residency anchor (fix #D)
  status         text not null default 'active',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);

-- ---------------------------------------------------------------------------
-- core.client_organizations
-- ---------------------------------------------------------------------------
create table core.client_organizations (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  legal_name     text not null,
  tax_id_token   text,                 -- tokenized only (see security.token)
  industry       text,
  parent_org_id  uuid references core.client_organizations(id),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on core.client_organizations(tenant_id);

-- ---------------------------------------------------------------------------
-- core.matters
-- ---------------------------------------------------------------------------
create table core.matters (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references core.tenants(id),
  client_org_id     uuid references core.client_organizations(id),
  matter_number     text not null,
  matter_name       text not null,
  matter_type       text not null,     -- fraud_exam, litigation, treasury, monitorship, receivership...
  jurisdiction      text,
  matter_timezone   text not null default 'UTC',
  status            text not null default 'open',
  lead_user_id      uuid,
  confidentiality   core.confidentiality_level not null default 'client_confidential',
  record_status     core.record_status not null default 'active',
  created_at        timestamptz not null default now(),
  created_by        uuid,
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  row_version       integer not null default 1,
  unique (tenant_id, matter_number)
);
create index on core.matters(tenant_id);

-- ---------------------------------------------------------------------------
-- core.matter_access  (the membership table RLS depends on)
-- ---------------------------------------------------------------------------
create table core.matter_access (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  matter_id      uuid not null references core.matters(id),
  user_id        uuid not null,                       -- = auth.users.id
  access_level   core.access_level not null default 'read',
  -- optional confidentiality ceiling: user cannot see items above this level
  max_confidentiality core.confidentiality_level not null default 'highly_restricted',
  granted_by     uuid,
  effective_from timestamptz not null default now(),
  effective_to   timestamptz,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1,
  unique (matter_id, user_id)
);
create index on core.matter_access(user_id);
create index on core.matter_access(matter_id);

-- ---------------------------------------------------------------------------
-- core.matter_parties
-- ---------------------------------------------------------------------------
create table core.matter_parties (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  matter_id      uuid not null references core.matters(id),
  party_name     text not null,
  party_role     text not null,       -- client, opposing, counsel, court, regulator, witness...
  counsel        text,
  confidentiality core.confidentiality_level not null default 'client_confidential',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on core.matter_parties(matter_id);

-- ---------------------------------------------------------------------------
-- core.authority_instruments  (why the team may act + what bounds it)
-- ---------------------------------------------------------------------------
create table core.authority_instruments (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references core.tenants(id),
  matter_id          uuid not null references core.matters(id),
  authority_type     text not null,   -- engagement_letter, court_order, subpoena, cid, consent_decree...
  issuing_party      text,
  effective_date     date,
  expiration_date    date,
  mandate            text,
  source_evidence_id uuid,            -- FK added in 0005 after evidence exists
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid,
  updated_at         timestamptz not null default now(),
  updated_by         uuid,
  row_version        integer not null default 1
);
create index on core.authority_instruments(matter_id);

-- ---------------------------------------------------------------------------
-- core.scope_items / reporting_obligations / deadlines
-- (authority parsed into discrete, enforceable requirements)
-- ---------------------------------------------------------------------------
create table core.scope_items (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  matter_id      uuid not null references core.matters(id),
  authority_id   uuid references core.authority_instruments(id),
  clause_category text,               -- duty, limitation, report, access, deadline, compensation
  clause_text    text,
  normalized_requirement text,
  in_scope       boolean not null default true,
  compliance_status text not null default 'not_started',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on core.scope_items(matter_id);

create table core.reporting_obligations (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  matter_id      uuid not null references core.matters(id),
  authority_id   uuid references core.authority_instruments(id),
  recipient      text,
  report_type    text,
  frequency      text,
  next_due_date  date,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on core.reporting_obligations(matter_id, next_due_date);

create table core.deadlines (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  matter_id      uuid not null references core.matters(id),
  deadline_type  text,
  due_at         timestamptz not null,   -- stored UTC; display in matter_timezone
  owner_user_id  uuid,
  completed      boolean not null default false,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on core.deadlines(matter_id, due_at);

-- ---------------------------------------------------------------------------
-- Stamp triggers
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'core.client_organizations','core.matters','core.matter_access',
    'core.matter_parties','core.authority_instruments','core.scope_items',
    'core.reporting_obligations','core.deadlines'
  ] loop
    execute format(
      'create trigger tg_stamp before insert or update on %s
         for each row execute function app.tg_stamp_row()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- RLS. Enable + FORCE on every matter-scoped table.
-- matter_access itself is self-referential: a user may read only their own
-- grants; matter_admins manage grants for their matter.
-- ---------------------------------------------------------------------------
alter table core.matters                enable row level security;
alter table core.matters                force  row level security;
alter table core.matter_access          enable row level security;
alter table core.matter_access          force  row level security;
alter table core.matter_parties         enable row level security;
alter table core.matter_parties         force  row level security;
alter table core.authority_instruments  enable row level security;
alter table core.authority_instruments  force  row level security;
alter table core.scope_items            enable row level security;
alter table core.scope_items            force  row level security;
alter table core.reporting_obligations  enable row level security;
alter table core.reporting_obligations  force  row level security;
alter table core.deadlines              enable row level security;
alter table core.deadlines              force  row level security;

-- matters: visible if the caller has any access to that matter
create policy matter_read on core.matters
  for select to authenticated
  using (app.has_matter_access(id, 'read'));
create policy matter_write on core.matters
  for update to authenticated
  using (app.has_matter_access(id, 'matter_admin'))
  with check (app.has_matter_access(id, 'matter_admin'));

-- matter_access: see your own rows; matter_admins see/manage all rows on their matter
create policy access_self_read on core.matter_access
  for select to authenticated
  using (user_id = app.current_user_id()
         or app.has_matter_access(matter_id, 'matter_admin'));
create policy access_admin_write on core.matter_access
  for all to authenticated
  using (app.has_matter_access(matter_id, 'matter_admin'))
  with check (app.has_matter_access(matter_id, 'matter_admin'));

-- Generic matter-scoped policies for the remaining tables
do $$
declare t text;
begin
  foreach t in array array[
    'core.matter_parties','core.authority_instruments','core.scope_items',
    'core.reporting_obligations','core.deadlines'
  ] loop
    execute format($p$
      create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$
      create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
    execute format($p$
      create policy upd on %s for update to authenticated
        using (app.has_matter_access(matter_id, 'contribute'))
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;
