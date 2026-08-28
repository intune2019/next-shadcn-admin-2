-- ============================================================================
-- Migration 0002: RLS access model + shared trigger functions
--
-- POOLER-SAFE ISOLATION (fix #B from the review):
-- On Supabase the connection pooler runs in transaction mode, so per-session
-- GUCs / `SET LOCAL app.matter_id` do NOT survive reliably. Tenant/matter
-- isolation is therefore driven by MEMBERSHIP joined to auth.uid() (the JWT
-- subject), NOT by a settable session variable an attacker or a lost session
-- could forge. Optional signed JWT claims can be layered on later, but the
-- membership table is the source of truth.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Access-level ordinality (least privilege). Higher = more power.
-- ---------------------------------------------------------------------------
create type core.access_level as enum (
  'none', 'read', 'contribute', 'review', 'approve', 'matter_admin'
);

create type core.record_status as enum (
  'active', 'superseded', 'voided', 'archived'  -- NB: no hard "deleted"; logical only
);

-- ---------------------------------------------------------------------------
-- app.current_user_id() : the authenticated principal (Supabase auth.uid()).
-- Wrapped so non-Supabase environments can stub it.
-- ---------------------------------------------------------------------------
create or replace function app.current_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid
$$;

-- ---------------------------------------------------------------------------
-- app.has_matter_access(matter, min_level) : the RLS workhorse.
-- Returns true iff the current principal holds >= min_level on that matter AND
-- the grant is active and unexpired. service_role bypasses RLS entirely so it
-- is not consulted here.
-- ---------------------------------------------------------------------------
-- NB: plpgsql (not sql) so the reference to core.matter_access — created in the
-- next migration (0003) — is resolved at first call, not at CREATE time. This
-- lets the policy helper exist before the table it reads.
create or replace function app.has_matter_access(
  p_matter_id uuid,
  p_min_level core.access_level default 'read'
)
returns boolean
language plpgsql stable security definer
set search_path = core, public
as $$
declare v_ok boolean;
begin
  select exists (
    select 1
    from core.matter_access ma
    where ma.matter_id = p_matter_id
      and ma.user_id   = app.current_user_id()
      and ma.record_status = 'active'
      and (ma.effective_to is null or ma.effective_to > now())
      and array_position(enum_range(null::core.access_level), ma.access_level)
          >= array_position(enum_range(null::core.access_level), p_min_level)
  ) into v_ok;
  return coalesce(v_ok, false);
end;
$$;

-- Document-level confidentiality can additionally clamp visibility inside a
-- matter (a user may see the matter but not privileged / court-sealed items).
create type core.confidentiality_level as enum (
  'public','internal','client_confidential','attorney_client_privileged',
  'attorney_work_product','highly_restricted','court_sealed',
  'regulatory_restricted','law_enforcement_restricted','phi','pii','pci','trade_secret'
);

-- ---------------------------------------------------------------------------
-- Shared trigger: stamp audit columns + optimistic concurrency (row_version).
-- ---------------------------------------------------------------------------
create or replace function app.tg_stamp_row()
returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'INSERT') then
    new.created_at := coalesce(new.created_at, now());
    new.created_by := coalesce(new.created_by, app.current_user_id());
    new.updated_at := new.created_at;
    new.updated_by := new.created_by;
    new.row_version := 1;
  elsif (tg_op = 'UPDATE') then
    new.created_at := old.created_at;   -- immutable
    new.created_by := old.created_by;   -- immutable
    new.updated_at := now();
    new.updated_by := app.current_user_id();
    new.row_version := old.row_version + 1;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared trigger: reject UPDATE/DELETE on append-only tables (custody, audit).
-- Corrections are added as NEW rows, never by mutating history.
-- ---------------------------------------------------------------------------
create or replace function app.tg_deny_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'Append-only table %.% — % is forbidden. Insert a correcting record instead.',
    tg_table_schema, tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared trigger: tamper-evident hash chaining (fix #A).
-- Requires the table to expose: seq bigint (identity), scope_key text,
-- payload_hash bytea, prev_hash bytea, chain_hash bytea.
-- chain_hash = sha256(payload_hash || prev_hash). prev_hash links to the most
-- recent row sharing the same scope_key (e.g. one chain per evidence item, or
-- one global chain for the audit plane). Anchoring of chain_hash roots to an
-- external RFC-3161 TSA / public ledger happens in the anchor tables.
-- ---------------------------------------------------------------------------
create or replace function app.tg_hash_chain()
returns trigger
language plpgsql
as $$
declare
  v_prev bytea;
begin
  -- payload_hash must already be set by the table's own BEFORE trigger or the
  -- inserting statement; we only compute the linkage here.
  execute format(
    'select chain_hash from %I.%I where scope_key = $1 order by seq desc limit 1',
    tg_table_schema, tg_table_name
  ) into v_prev using new.scope_key;

  new.prev_hash  := coalesce(v_prev, decode(repeat('00',32),'hex'));  -- genesis
  new.chain_hash := extensions.digest(new.payload_hash || new.prev_hash, 'sha256');
  return new;
end;
$$;
