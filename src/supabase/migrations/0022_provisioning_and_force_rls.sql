-- ============================================================================
-- Migration 0022: authorized matter provisioning + complete FORCE RLS coverage
-- ============================================================================

begin;

-- Matter creation is intentionally not exposed as a direct INSERT. This
-- function performs the matter and initial access-grant writes in one
-- transaction, and only an existing tenant matter_admin may call it.
create or replace function core.provision_matter(
  p_tenant_id uuid,
  p_matter_name text,
  p_matter_type text,
  p_confidentiality core.confidentiality_level default 'attorney_work_product',
  p_client_org_id uuid default null
)
returns table (id uuid, matter_number text)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp, core, app
as $$
declare
  v_user_id uuid := app.current_user_id();
  v_matter_id uuid;
  v_matter_number text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not app.has_tenant_access(p_tenant_id, 'matter_admin') then
    raise exception 'Matter administrator access is required for this tenant'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_matter_name), '') is null then
    raise exception 'Matter name is required' using errcode = '22023';
  end if;

  if nullif(btrim(p_matter_type), '') is null then
    raise exception 'Matter type is required' using errcode = '22023';
  end if;

  if p_client_org_id is not null and not exists (
    select 1
    from core.client_organizations co
    where co.id = p_client_org_id and co.tenant_id = p_tenant_id
  ) then
    raise exception 'Client organization does not belong to this tenant'
      using errcode = '23503';
  end if;

  insert into core.matters (
    tenant_id,
    client_org_id,
    matter_name,
    matter_type,
    confidentiality,
    created_by,
    updated_by
  ) values (
    p_tenant_id,
    p_client_org_id,
    btrim(p_matter_name),
    btrim(p_matter_type),
    p_confidentiality,
    v_user_id,
    v_user_id
  )
  returning core.matters.id, core.matters.matter_number
    into v_matter_id, v_matter_number;

  insert into core.matter_access (
    tenant_id,
    matter_id,
    user_id,
    access_level,
    granted_by,
    created_by,
    updated_by
  ) values (
    p_tenant_id,
    v_matter_id,
    v_user_id,
    'matter_admin',
    v_user_id,
    v_user_id,
    v_user_id
  );

  return query select v_matter_id, v_matter_number;
end;
$$;

revoke all on function core.provision_matter(
  uuid, text, text, core.confidentiality_level, uuid
) from public, anon;
grant execute on function core.provision_matter(
  uuid, text, text, core.confidentiality_level, uuid
) to authenticated;

comment on function core.provision_matter(
  uuid, text, text, core.confidentiality_level, uuid
) is 'Atomically provisions a matter for an existing tenant matter_admin and grants that caller matter_admin on the new matter.';

-- Complete the insider-defense posture promised by the foundation ADR. These
-- catalog tables already have RLS policies; FORCE ensures table-owner sessions
-- do not silently bypass those policies. Superusers and BYPASSRLS service roles
-- retain their intended administrative access.
alter table audit.anchor_runs force row level security;
alter table calculations.model_definitions force row level security;
alter table calculations.model_versions force row level security;
alter table mapping.field_mappings force row level security;
alter table mapping.mapping_approvals force row level security;
alter table mapping.mapping_versions force row level security;
alter table mapping.normalization_rules force row level security;
alter table mapping.source_data_dictionaries force row level security;
alter table mapping.source_objects force row level security;
alter table mapping.source_systems force row level security;
alter table mapping.transformation_definitions force row level security;
alter table mapping.value_crosswalks force row level security;
alter table quality.validation_rules force row level security;
alter table rules.population_definitions force row level security;
alter table rules.rule_definitions force row level security;
alter table rules.rule_parameter_definitions force row level security;
alter table rules.rule_test_cases force row level security;
alter table rules.rule_test_results force row level security;
alter table rules.rule_versions force row level security;

commit;
