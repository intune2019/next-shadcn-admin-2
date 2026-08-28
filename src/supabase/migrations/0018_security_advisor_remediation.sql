-- ============================================================================
-- Migration 0018: security-advisor remediation
--
-- Addresses four findings from the Supabase Security Advisor:
--   1. RLS disabled in public — core.tenants, core.client_organizations,
--      evidence.anchor_runs never got ENABLE ROW LEVEL SECURITY. Any
--      authenticated user (any signed-up account, regardless of
--      matter_access) had full SELECT/INSERT/UPDATE/DELETE across every
--      tenant's rows in these three tables via the blanket ALTER DEFAULT
--      PRIVILEGES grant in 0001 — the single highest-severity gap here,
--      since core.tenants is the tenant-isolation root.
--   2. Security-definer views — analytics.v_payment_360/v_evidence_lineage/
--      v_report_traceability/v_golden_thread run with the view owner's
--      privileges by default (plain Postgres view semantics, not a literal
--      `security definer` keyword), which bypasses the querying user's RLS
--      entirely. 0011's own comment claiming these are "SECURITY INVOKER
--      (default)" is wrong — invoker semantics for views is an explicit
--      PG15+ opt-in (`security_invoker = true`), never the default.
--   3. SECURITY DEFINER functions with no explicit privilege grant fall back
--      to Postgres's implicit EXECUTE-to-PUBLIC default for new functions:
--        - app.has_matter_access: locked down for defense-in-depth even
--          though missing schema USAGE currently blocks anon in practice —
--          don't rely on that as the only barrier.
--        - app.run_scheduled_anchoring: meant to be pg_cron-only (see the
--          cron.schedule call in 0015), but any authenticated user could
--          call it directly and force a system-wide anchoring cycle
--          on-demand, across every tenant, outside its schedule.
--      audit.write and app.enqueue already had explicit grants to
--      `authenticated` — that's the intended usage (audit.write in
--      particular is never called from a trigger; it's the only supported
--      way business-role sessions append audit events at all), so revoking
--      the grant outright would break the feature. Instead, both take
--      p_tenant/p_matter as caller-supplied parameters and never checked
--      the caller actually has any relationship to them — any authenticated
--      user could forge audit events or queue jobs against a tenant they
--      have zero matter_access to. Fixed by adding the same authorization
--      check RLS itself uses, inside each function.
--   4. Multiple permissive policies on core.matter_access — access_self_read
--      (FOR SELECT) and access_admin_write (FOR ALL, which also matches
--      SELECT) were both evaluated and OR'd on every SELECT. Consolidated
--      into one policy per action.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. RLS on core.tenants, core.client_organizations, evidence.anchor_runs
-- ---------------------------------------------------------------------------

-- Tenant-level equivalent of app.has_matter_access, for the tables that are
-- tenant-scoped rather than matter-scoped. There is no core.tenant_members
-- (or any user<->tenant table) in this schema — "access to a tenant" is
-- derived the same way everything else is: holding matter_access on at
-- least one matter within it.
create or replace function app.has_tenant_access(
  p_tenant_id uuid,
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
    join core.matters m on m.id = ma.matter_id
    where m.tenant_id = p_tenant_id
      and ma.user_id  = app.current_user_id()
      and ma.record_status = 'active'
      and (ma.effective_to is null or ma.effective_to > now())
      and array_position(enum_range(null::core.access_level), ma.access_level)
          >= array_position(enum_range(null::core.access_level), p_min_level)
  ) into v_ok;
  return coalesce(v_ok, false);
end;
$$;
revoke all on function app.has_tenant_access(uuid, core.access_level) from public;
grant execute on function app.has_tenant_access(uuid, core.access_level)
  to authenticated, service_role;

alter table core.tenants enable row level security;
alter table core.tenants force row level security;
create policy tenants_sel on core.tenants
  for select to authenticated
  using (app.has_tenant_access(id, 'read'));
-- No insert/update/delete policy for `authenticated` => those are denied
-- outright (service_role bypasses RLS and is unaffected). Tenant
-- creation/rename is an onboarding operation, matching the existing
-- bootstrap model where the first matter_access grant on a new matter must
-- also come from service_role — see core.matter_access below.

alter table core.client_organizations enable row level security;
alter table core.client_organizations force row level security;
create policy client_orgs_sel on core.client_organizations
  for select to authenticated
  using (app.has_tenant_access(tenant_id, 'read'));
create policy client_orgs_ins on core.client_organizations
  for insert to authenticated
  with check (app.has_tenant_access(tenant_id, 'contribute'));
create policy client_orgs_upd on core.client_organizations
  for update to authenticated
  using (app.has_tenant_access(tenant_id, 'contribute'))
  with check (app.has_tenant_access(tenant_id, 'contribute'));

-- evidence.anchor_runs: same "service_role only" model already used for its
-- sibling audit.anchor_runs (0010) — external TSA/ledger anchoring batches
-- aren't end-user objects.
alter table evidence.anchor_runs enable row level security;
alter table evidence.anchor_runs force row level security;
create policy anchor_runs_sr on evidence.anchor_runs
  for all to service_role using (true) with check (true);

-- ---------------------------------------------------------------------------
-- 2. security_invoker on the analytics traceability views (0011)
-- ---------------------------------------------------------------------------
alter view analytics.v_payment_360         set (security_invoker = true);
alter view analytics.v_evidence_lineage    set (security_invoker = true);
alter view analytics.v_report_traceability set (security_invoker = true);
alter view analytics.v_golden_thread       set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 3. SECURITY DEFINER function privileges
-- ---------------------------------------------------------------------------

revoke all on function app.has_matter_access(uuid, core.access_level) from public;
grant execute on function app.has_matter_access(uuid, core.access_level)
  to authenticated, service_role;

-- No positive grant needed for the cron job itself — it runs as the role
-- that scheduled it (postgres), a superuser, which needs no EXECUTE grant.
-- Revoking PUBLIC closes the "any authenticated user can force a
-- system-wide anchoring cycle on demand" gap.
revoke all on function app.run_scheduled_anchoring() from public;

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
  if p_matter is not null then
    if not app.has_matter_access(p_matter, 'read') then
      raise exception 'audit.write: no access to matter %', p_matter using errcode = '42501';
    end if;
  elsif not app.has_tenant_access(p_tenant, 'read') then
    raise exception 'audit.write: no access to tenant %', p_tenant using errcode = '42501';
  end if;

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
-- grants unchanged (authenticated, service_role) — the function is now
-- self-authorizing instead of trusting the caller-supplied tenant/matter.

create or replace function app.enqueue(
  p_queue text, p_tenant uuid, p_payload jsonb, p_matter uuid default null
)
returns bigint
language plpgsql security definer
set search_path = pgmq, public
as $$
declare v_msg_id bigint;
begin
  -- Same forgery gap as audit.write, same fix. p_tenant/p_matter both null
  -- is the internal/system-job call shape (e.g. app.run_scheduled_anchoring
  -- enqueues 'anchoring' with p_tenant := null::uuid) and is left
  -- unauthorized-checked since there's no caller identity to check there.
  if p_matter is not null then
    if not app.has_matter_access(p_matter, 'read') then
      raise exception 'app.enqueue: no access to matter %', p_matter using errcode = '42501';
    end if;
  elsif p_tenant is not null and not app.has_tenant_access(p_tenant, 'read') then
    raise exception 'app.enqueue: no access to tenant %', p_tenant using errcode = '42501';
  end if;

  select pgmq.send(
    p_queue,
    jsonb_build_object(
      'tenant_id', p_tenant,
      'matter_id', p_matter,
      'enqueued_by', app.current_user_id(),
      'enqueued_at', now(),
      'payload', p_payload
    )
  ) into v_msg_id;
  return v_msg_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Consolidate multiple permissive policies on core.matter_access
-- ---------------------------------------------------------------------------
drop policy if exists access_self_read on core.matter_access;
drop policy if exists access_admin_write on core.matter_access;

create policy access_select on core.matter_access
  for select to authenticated
  using (user_id = app.current_user_id()
         or app.has_matter_access(matter_id, 'matter_admin'));

create policy access_insert on core.matter_access
  for insert to authenticated
  with check (app.has_matter_access(matter_id, 'matter_admin'));

create policy access_update on core.matter_access
  for update to authenticated
  using (app.has_matter_access(matter_id, 'matter_admin'))
  with check (app.has_matter_access(matter_id, 'matter_admin'));

create policy access_delete on core.matter_access
  for delete to authenticated
  using (app.has_matter_access(matter_id, 'matter_admin'));
