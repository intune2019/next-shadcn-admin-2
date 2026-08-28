-- ============================================================================
-- Forens_iQ — Migration 0030: evidence access/production/hold logging (P0),
-- general-ledger + journal-entry layer (P0).
-- Draft for review — matches the append-only / hash-chain / RLS conventions
-- established in 0002/0005/0010. Target: Supabase (PostgreSQL 15+).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- evidence.evidence_access_events  — APPEND-ONLY log of every READ of a
-- privileged/restricted evidence item, per spec §5/§Non-Negotiable Principles:
-- "No access to privileged, confidential, protected, or restricted data
--  without a logged authorization decision." This is distinct from
-- chain_of_custody_events (which logs physical/custodial transfer, not view).
-- ---------------------------------------------------------------------------
create table evidence.evidence_access_events (
  id             uuid primary key default gen_random_uuid(),
  seq            bigint generated always as identity,
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  evidence_id    uuid not null references evidence.evidence_items(id),
  scope_key      text not null,          -- = evidence_id::text
  access_type    text not null,          -- viewed, downloaded, exported, printed, shared
  accessed_by    uuid not null default app.current_user_id(),
  access_reason  text,
  authorized_by  uuid,                    -- required if confidentiality > client_confidential (app-enforced)
  confidentiality_at_access core.confidentiality_level,
  payload_hash   bytea,
  prev_hash      bytea,
  chain_hash     bytea,
  created_at     timestamptz not null default now()
);
create index on evidence.evidence_access_events(evidence_id, seq);

create or replace function evidence.tg_access_payload()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp, evidence
as $$
begin
  new.scope_key := new.evidence_id::text;
  new.payload_hash := extensions.digest(
    coalesce(new.evidence_id::text,'')   || '|' ||
    coalesce(new.access_type,'')         || '|' ||
    coalesce(new.accessed_by::text,'')   || '|' ||
    coalesce(new.access_reason,'')       || '|' ||
    coalesce(new.created_at::text,''),
    'sha256');
  return new;
end $$;

create trigger tg_10_payload before insert on evidence.evidence_access_events
  for each row execute function evidence.tg_access_payload();
create trigger tg_20_chain   before insert on evidence.evidence_access_events
  for each row execute function app.tg_hash_chain();
create trigger tg_90_denymut before update or delete on evidence.evidence_access_events
  for each row execute function app.tg_deny_mutation();

alter table evidence.evidence_access_events enable row level security;
alter table evidence.evidence_access_events force  row level security;
create policy sel on evidence.evidence_access_events for select to authenticated
  using (app.has_matter_access(matter_id, 'review'));   -- reading the access log is itself review-tier
create policy ins on evidence.evidence_access_events for insert to authenticated
  with check (app.has_matter_access(matter_id, 'read'));

-- Convenience wrapper: call this from the app on every evidence view/download
-- so RLS + the confidentiality check happen server-side, not just client-side.
create or replace function evidence.log_access(
  p_evidence_id uuid, p_access_type text, p_reason text default null
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, pg_temp, evidence, core, app
as $$
declare
  v_item evidence.evidence_items%rowtype;
  v_id   uuid;
begin
  select * into v_item from evidence.evidence_items where id = p_evidence_id;
  if not found or not app.has_matter_access(v_item.matter_id, 'read') then
    raise exception 'Evidence not found or insufficient access' using errcode = '42501';
  end if;
  if v_item.confidentiality in ('highly_restricted','court_sealed','regulatory_restricted',
                                 'law_enforcement_restricted')
     and p_reason is null then
    raise exception 'Access reason is required for this confidentiality level' using errcode = '22023';
  end if;
  insert into evidence.evidence_access_events(
    tenant_id, matter_id, evidence_id, access_type, accessed_by, access_reason,
    confidentiality_at_access)
  values (v_item.tenant_id, v_item.matter_id, p_evidence_id, p_access_type,
          app.current_user_id(), p_reason, v_item.confidentiality)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function evidence.log_access(uuid, text, text) from public, anon;
grant execute on function evidence.log_access(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- evidence.evidence_productions  — what was formally produced to whom,
-- Bates range, under what authority/protective order.
-- ---------------------------------------------------------------------------
create table evidence.evidence_productions (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  production_number  text not null,       -- e.g. PROD-001
  produced_to        text not null,
  produced_by        uuid,
  produced_at        timestamptz,
  bates_prefix       text,
  bates_start        integer,
  bates_end          integer,
  protective_order_evidence_id uuid references evidence.evidence_items(id),
  confidentiality_designation core.confidentiality_level,
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, production_number)
);
create index on evidence.evidence_productions(matter_id);

create table evidence.evidence_production_items (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  production_id  uuid not null references evidence.evidence_productions(id),
  evidence_id    uuid not null references evidence.evidence_items(id),
  bates_number   text,
  redaction_applied boolean not null default false,
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on evidence.evidence_production_items(production_id);
create index on evidence.evidence_production_items(evidence_id);

-- ---------------------------------------------------------------------------
-- evidence.evidence_hold_events  — APPEND-ONLY legal-hold history. Replaces
-- treating evidence_items.legal_hold_status as freely mutable; that column
-- is kept as a denormalized "current status" cache, maintained only via this
-- table (trigger below), so hold history survives even if the cache is wrong.
-- ---------------------------------------------------------------------------
create table evidence.evidence_hold_events (
  id             uuid primary key default gen_random_uuid(),
  seq            bigint generated always as identity,
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  evidence_id    uuid not null references evidence.evidence_items(id),
  scope_key      text not null,
  event_type     text not null,          -- held, released, exempted
  authority_id   uuid references core.authority_instruments(id),
  reason         text,
  actioned_by    uuid default app.current_user_id(),
  payload_hash   bytea,
  prev_hash      bytea,
  chain_hash     bytea,
  created_at     timestamptz not null default now()
);
create index on evidence.evidence_hold_events(evidence_id, seq);

create or replace function evidence.tg_hold_payload()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp, evidence
as $$
begin
  new.scope_key := new.evidence_id::text;
  new.payload_hash := extensions.digest(
    coalesce(new.evidence_id::text,'') || '|' || coalesce(new.event_type,'') || '|' ||
    coalesce(new.authority_id::text,'') || '|' || coalesce(new.created_at::text,''),
    'sha256');
  return new;
end $$;

create trigger tg_10_payload before insert on evidence.evidence_hold_events
  for each row execute function evidence.tg_hold_payload();
create trigger tg_20_chain   before insert on evidence.evidence_hold_events
  for each row execute function app.tg_hash_chain();
create trigger tg_90_denymut before update or delete on evidence.evidence_hold_events
  for each row execute function app.tg_deny_mutation();

-- Keep evidence_items.legal_hold_status as a cache, sourced only from here.
create or replace function evidence.tg_apply_hold_status()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp, evidence
as $$
begin
  update evidence.evidence_items
     set legal_hold_status = case new.event_type
           when 'held' then 'held' when 'released' then 'released' else 'exempt' end
   where id = new.evidence_id;
  return new;
end $$;
create trigger tg_30_apply after insert on evidence.evidence_hold_events
  for each row execute function evidence.tg_apply_hold_status();

do $$
declare t text;
begin
  foreach t in array array[
    'evidence.evidence_productions','evidence.evidence_production_items',
    'evidence.evidence_hold_events'
  ] loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;
create trigger tg_stamp before insert or update on evidence.evidence_productions
  for each row execute function app.tg_stamp_row();

-- ============================================================================
-- GL / journal-entry layer (P0 gap — spec §6 "Canonical Financial Data Model")
-- ============================================================================

create table canonical.chart_of_accounts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  account_number text not null,
  account_name   text not null,
  account_type   text not null,        -- asset, liability, equity, revenue, expense
  parent_account_id uuid references canonical.chart_of_accounts(id),
  is_active      boolean not null default true,
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (matter_id, account_number)
);
create index on canonical.chart_of_accounts(matter_id);

create table canonical.journal_entries (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  je_number          text,
  je_date            date not null,
  posting_period     text,             -- e.g. '2026-07'
  source_module      text,             -- manual, AP, AR, payroll, system
  prepared_by_ref    text,
  approved_by_ref    text,
  description        text,
  is_manual          boolean not null default true,   -- manual JEs are the classic fraud vector
  is_reversing       boolean not null default false,
  reversal_of_je_id  uuid references canonical.journal_entries(id),
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  source_evidence_id uuid references evidence.evidence_items(id),
  confidence_score   numeric(5,2),
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, source_dataset_version_id, source_record_id)
);
create index on canonical.journal_entries(matter_id, je_date);
create index on canonical.journal_entries(matter_id, is_manual);

create table canonical.journal_entry_lines (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  journal_entry_id uuid not null references canonical.journal_entries(id),
  line_number    int not null,
  account_id     uuid not null references canonical.chart_of_accounts(id),
  debit_amount   numeric(20,4) not null default 0,
  credit_amount  numeric(20,4) not null default 0,
  currency       char(3) not null default 'USD',
  memo           text,
  counterparty_entity_id uuid references canonical.entities(id),
  linked_transaction_id  uuid references canonical.transactions(id),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (journal_entry_id, line_number),
  check (not (debit_amount <> 0 and credit_amount <> 0))   -- a line is a debit XOR a credit
);
create index on canonical.journal_entry_lines(matter_id, journal_entry_id);
create index on canonical.journal_entry_lines(matter_id, account_id);

-- Balance guard: every journal entry's debits must equal its credits.
-- Deferred so multi-line inserts in one transaction pass.
create or replace function canonical.tg_je_balance_guard()
returns trigger language plpgsql
set search_path = pg_catalog, pg_temp, canonical
as $$
declare v_je uuid; v_debits numeric; v_credits numeric;
begin
  v_je := coalesce(new.journal_entry_id, old.journal_entry_id);
  select coalesce(sum(debit_amount),0), coalesce(sum(credit_amount),0)
    into v_debits, v_credits
    from canonical.journal_entry_lines
   where journal_entry_id = v_je and record_status = 'active';
  if v_debits <> v_credits then
    raise exception 'Journal entry % is out of balance: debits % <> credits %',
      v_je, v_debits, v_credits using errcode = '23514';
  end if;
  return null;
end $$;
create constraint trigger tg_je_balance
  after insert or update or delete on canonical.journal_entry_lines
  deferrable initially deferred
  for each row execute function canonical.tg_je_balance_guard();

do $$
declare t text; tables text[] := array[
  'canonical.chart_of_accounts','canonical.journal_entries','canonical.journal_entry_lines'];
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
end $$;

commit;
