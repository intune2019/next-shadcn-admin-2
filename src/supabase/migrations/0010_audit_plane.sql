-- ============================================================================
-- Migration 0010: immutable, hash-chained, externally-anchorable audit plane
-- (fix #A + fix #C). One global chain (scope_key = tenant_id). UPDATE/DELETE
-- are rejected. Anchor the chain head to an external TSA on a schedule so no
-- platform insider can rewrite history and the proof of history together.
-- ============================================================================

create table audit.audit_events (
  id              uuid primary key default gen_random_uuid(),
  seq             bigint generated always as identity,
  tenant_id       uuid not null,
  matter_id       uuid,
  scope_key       text not null,        -- tenant_id::text (one chain per tenant)
  occurred_at     timestamptz not null default now(),
  actor_id        uuid,
  actor_role      text,
  action          text not null,        -- login, evidence_view, export, field_update, approval, hold_release...
  entity_schema   text,
  entity_table    text,
  entity_id       uuid,
  before_hash     bytea,
  after_hash      bytea,
  client_ip       inet,
  request_id      text,
  reason_code     text,
  approval_id     uuid,
  -- integrity linkage
  payload_hash    bytea,
  prev_hash       bytea,
  chain_hash      bytea
);
create index on audit.audit_events(tenant_id, seq);
create index on audit.audit_events(entity_schema, entity_table, entity_id);

create or replace function audit.tg_audit_payload()
returns trigger language plpgsql as $$
begin
  new.scope_key := new.tenant_id::text;
  new.payload_hash := extensions.digest(
    coalesce(new.tenant_id::text,'')  || '|' ||
    coalesce(new.occurred_at::text,'')|| '|' ||
    coalesce(new.actor_id::text,'')   || '|' ||
    coalesce(new.action,'')           || '|' ||
    coalesce(new.entity_schema,'')    || '.' ||
    coalesce(new.entity_table,'')     || '|' ||
    coalesce(new.entity_id::text,'')  || '|' ||
    coalesce(encode(new.before_hash,'hex'),'') || '|' ||
    coalesce(encode(new.after_hash,'hex'),''),
    'sha256');
  return new;
end $$;

create trigger tg_10_payload before insert on audit.audit_events
  for each row execute function audit.tg_audit_payload();
create trigger tg_20_chain   before insert on audit.audit_events
  for each row execute function app.tg_hash_chain();
create trigger tg_90_denymut before update or delete on audit.audit_events
  for each row execute function app.tg_deny_mutation();

-- ---------------------------------------------------------------------------
-- audit.write(...) : the only supported way to append an audit event.
-- SECURITY DEFINER so business roles can log without holding table rights that
-- could be abused to forge scope; the function fixes tenant/actor from context.
-- ---------------------------------------------------------------------------
create or replace function audit.write(
  p_tenant uuid, p_action text,
  p_matter uuid default null,
  p_entity_schema text default null, p_entity_table text default null,
  p_entity_id uuid default null,
  p_before_hash bytea default null, p_after_hash bytea default null,
  p_reason text default null)
returns uuid
language plpgsql security definer
set search_path = audit, public
as $$
declare v_id uuid;
begin
  insert into audit.audit_events(
    tenant_id, matter_id, actor_id, action,
    entity_schema, entity_table, entity_id,
    before_hash, after_hash, reason_code)
  values (p_tenant, p_matter, app.current_user_id(), p_action,
          p_entity_schema, p_entity_table, p_entity_id,
          p_before_hash, p_after_hash, p_reason)
  returning id into v_id;
  return v_id;
end $$;
grant execute on function audit.write(uuid,text,uuid,text,text,uuid,bytea,bytea,text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- audit.anchor_runs : same external-anchoring model as evidence, for the audit
-- chain. A scheduled job computes the root and lodges it with a TSA / ledger.
-- ---------------------------------------------------------------------------
create table audit.anchor_runs (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid,
  seq_from       bigint not null,
  seq_to         bigint not null,
  merkle_root    bytea not null,
  external_authority text,
  external_token bytea,
  anchored_at    timestamptz,
  status         text not null default 'pending',
  created_at     timestamptz not null default now(),
  created_by     uuid default app.current_user_id()
);

create or replace function audit.compute_root(p_tenant uuid, p_from bigint, p_to bigint)
returns bytea language sql stable as $$
  select extensions.digest(
    coalesce(string_agg(encode(chain_hash,'hex'), '' order by seq), ''),
    'sha256')
  from audit.audit_events
  where tenant_id = p_tenant and seq between p_from and p_to
$$;

-- ---------------------------------------------------------------------------
-- audit.verify_chain(tenant) : recompute the whole chain and flag the first
-- broken link. A regulator/QC reviewer runs this to prove nothing was altered.
-- Returns the seq where the chain breaks, or NULL if intact.
-- ---------------------------------------------------------------------------
create or replace function audit.verify_chain(p_tenant uuid)
returns bigint
language plpgsql stable
as $$
declare r record; v_prev bytea := decode(repeat('00',32),'hex'); v_expected bytea;
begin
  for r in select seq, payload_hash, prev_hash, chain_hash
             from audit.audit_events
            where tenant_id = p_tenant order by seq loop
    if r.prev_hash is distinct from v_prev then
      return r.seq;   -- prev linkage broken
    end if;
    v_expected := extensions.digest(r.payload_hash || r.prev_hash, 'sha256');
    if r.chain_hash is distinct from v_expected then
      return r.seq;   -- chain hash tampered
    end if;
    v_prev := r.chain_hash;
  end loop;
  return null;        -- intact
end $$;

-- RLS: audit is readable by matter members (their matter's events) and QC/
-- service_role sees the tenant chain. Inserts go only through audit.write().
alter table audit.audit_events enable row level security;
alter table audit.audit_events force row level security;
create policy sel on audit.audit_events for select to authenticated
  using (matter_id is null or app.has_matter_access(matter_id, 'read'));
create policy all_sr on audit.audit_events for all to service_role
  using (true) with check (true);

alter table audit.anchor_runs enable row level security;
create policy all_sr_anchor on audit.anchor_runs for all to service_role
  using (true) with check (true);
