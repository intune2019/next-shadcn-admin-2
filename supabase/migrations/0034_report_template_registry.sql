-- ============================================================================
-- Forens_iQ — Migration 0034: Report template registry
--
-- Design borrows three concepts from Frappe/ERPNext's DocType metadata engine
-- (reviewed as a reference, not reproduced or forked):
--   1. Forms are DATA, not code: report_templates/template_sections/
--      template_fields describe a report the way DocType/Field describe a
--      form — the Next.js/shadcn report builder renders from this, it does
--      not hardcode field lists.
--   2. Property-Setter pattern: template_field_overrides lets a TENANT
--      customize a shared system template (hide a field, relabel it, change
--      mandatory-ness) without forking the template — same idea as Frappe
--      layering a Property Setter over a stock DocType.
--   3. Report-type split (Query / Calculation-bound / Narrative / Exhibit
--      index), each template field can bind to live platform data via
--      template_data_bindings — this is what makes assemble_report() (0024)
--      data-driven instead of hardcoded PL/pgSQL.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- reporting.report_templates — tenant_id NULL = system template (shared,
-- shipped by the platform); tenant_id set = a tenant's own custom template.
-- ---------------------------------------------------------------------------
create table reporting.report_templates (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references core.tenants(id),   -- null = system-provided
  template_code  text not null,
  template_name  text not null,
  matter_type    text,                 -- fraud_exam, litigation, treasury, grc_audit... null = any
  report_type    text not null check (report_type in
                    ('narrative_findings','calculation_summary','exhibit_index',
                     'grc_audit','treasury_governance','universal_findings','custom')),
  description    text,
  version        int not null default 1,
  is_system      boolean not null default false,
  is_active      boolean not null default true,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), template_code, version)
);
create index on reporting.report_templates(matter_type, report_type) where is_active;

-- ---------------------------------------------------------------------------
-- reporting.template_sections — ordered sections within a template (maps to
-- Frappe's Section Break concept, but explicit rather than a field type).
-- ---------------------------------------------------------------------------
create table reporting.template_sections (
  id               uuid primary key default gen_random_uuid(),
  template_id      uuid not null references reporting.report_templates(id),
  section_key      text not null,
  section_title    text not null,
  sort_order       int not null default 0,
  is_required      boolean not null default true,
  depends_on_section_key text,     -- conditional section, evaluated client-side
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid,
  unique (template_id, section_key)
);
create index on reporting.template_sections(template_id, sort_order);

-- ---------------------------------------------------------------------------
-- reporting.template_fields — the DocType "Field" equivalent.
-- ---------------------------------------------------------------------------
create table reporting.template_fields (
  id                uuid primary key default gen_random_uuid(),
  template_id       uuid not null references reporting.report_templates(id),
  section_id        uuid references reporting.template_sections(id),
  fieldname         text not null,        -- machine key, snake_case
  label             text not null,
  field_type        text not null check (field_type in
                       ('text','long_text','number','currency','date','datetime',
                        'select','multiselect','link','table','check','attach',
                        'evidence_binding','calculation_binding','finding_binding',
                        'entity_binding','signature')),
  options           text,                 -- select choices (comma-sep) or link target ('evidence','canonical.entities'...)
  is_mandatory      boolean not null default false,
  default_value     text,
  placeholder        text,
  help_text          text,
  depends_on_fieldname text,              -- conditional visibility, client-evaluated
  validation_rule    text,                -- e.g. a regex or a named server-side validator
  sort_order         int not null default 0,
  is_readonly         boolean not null default false,
  print_hide          boolean not null default false,   -- excluded from rendered output, capture-only
  record_status       core.record_status not null default 'active',
  created_at          timestamptz not null default now(),
  created_by           uuid, updated_at timestamptz not null default now(),
  updated_by           uuid, row_version integer not null default 1,
  unique (template_id, fieldname)
);
create index on reporting.template_fields(template_id, sort_order);
create index on reporting.template_fields(section_id);

-- ---------------------------------------------------------------------------
-- reporting.template_field_overrides — the Property-Setter equivalent.
-- A tenant customizes a SYSTEM template's field without forking the whole
-- template; resolved at read time by get_effective_template_fields() below.
-- ---------------------------------------------------------------------------
create table reporting.template_field_overrides (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references core.tenants(id),
  template_field_id uuid not null references reporting.template_fields(id),
  property          text not null check (property in
                       ('label','is_mandatory','default_value','options','placeholder',
                        'help_text','print_hide','is_readonly','sort_order')),
  set_value         text not null,        -- stored as text, cast by the app per property type
  record_status     core.record_status not null default 'active',
  created_at        timestamptz not null default now(),
  created_by        uuid, updated_at timestamptz not null default now(),
  updated_by        uuid, row_version integer not null default 1,
  unique (tenant_id, template_field_id, property)
);
create index on reporting.template_field_overrides(tenant_id, template_field_id);

-- ---------------------------------------------------------------------------
-- reporting.template_data_bindings — how a field auto-populates from live
-- platform data (what assemble_report() reads instead of hardcoding joins).
-- ---------------------------------------------------------------------------
create table reporting.template_data_bindings (
  id                uuid primary key default gen_random_uuid(),
  template_field_id uuid not null references reporting.template_fields(id),
  binding_type      text not null check (binding_type in
                       ('evidence_item','finding','calculation_run','entity',
                        'transaction','control_test','matter_field','custom_query')),
  source_schema     text,          -- e.g. 'investigation', 'calculations', 'canonical'
  source_table      text,
  filter_expression jsonb,         -- structured filter, e.g. {"status":"final"} — evaluated by assemble_report()
  is_required_for_finalization boolean not null default false,  -- e.g. "cannot finalize without >=1 finding bound"
  created_at        timestamptz not null default now(),
  created_by        uuid
);
create index on reporting.template_data_bindings(template_field_id);

-- ---------------------------------------------------------------------------
-- reporting.template_approval_steps — required sign-off chain for a template,
-- distinct from the per-instance approval events already tracked by
-- reporting.report_approvals (0026) / decide_report() (0027). This is the
-- REQUIRED-STEPS DEFINITION; report_approvals is the ACTUAL LOG against it.
-- ---------------------------------------------------------------------------
create table reporting.template_approval_steps (
  id             uuid primary key default gen_random_uuid(),
  template_id    uuid not null references reporting.report_templates(id),
  step_order     int not null,
  step_name      text not null,
  approver_role  core.access_level not null default 'review',
  is_required    boolean not null default true,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  unique (template_id, step_order)
);

-- ---------------------------------------------------------------------------
-- reporting.template_render_profiles — output shaping per template.
-- ---------------------------------------------------------------------------
create table reporting.template_render_profiles (
  id             uuid primary key default gen_random_uuid(),
  template_id    uuid not null references reporting.report_templates(id),
  output_format  text not null default 'pdf' check (output_format in ('pdf','docx','html')),
  letterhead_evidence_id uuid references evidence.evidence_items(id),  -- firm letterhead asset
  page_size      text not null default 'letter',
  include_exhibit_index boolean not null default true,
  include_signature_block boolean not null default true,
  is_default     boolean not null default true,
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on reporting.template_render_profiles(template_id);

-- ---------------------------------------------------------------------------
-- reporting.get_effective_template_fields — resolves base fields + tenant
-- overrides into one row set, exactly what the Next.js report builder should
-- call to render a form (never read template_fields directly on the client).
-- ---------------------------------------------------------------------------
create or replace function reporting.get_effective_template_fields(
  p_template_id uuid, p_tenant_id uuid
)
returns table (
  field_id uuid, section_id uuid, fieldname text, label text, field_type text,
  options text, is_mandatory boolean, default_value text, placeholder text,
  help_text text, depends_on_fieldname text, sort_order int, is_readonly boolean, print_hide boolean
)
language sql stable
set search_path = pg_catalog, pg_temp, reporting
as $$
  select
    f.id, f.section_id, f.fieldname,
    coalesce((select o.set_value from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'label' and o.record_status = 'active'), f.label),
    f.field_type,
    coalesce((select o.set_value from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'options' and o.record_status = 'active'), f.options),
    coalesce((select o.set_value::boolean from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'is_mandatory' and o.record_status = 'active'), f.is_mandatory),
    coalesce((select o.set_value from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'default_value' and o.record_status = 'active'), f.default_value),
    coalesce((select o.set_value from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'placeholder' and o.record_status = 'active'), f.placeholder),
    coalesce((select o.set_value from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'help_text' and o.record_status = 'active'), f.help_text),
    f.depends_on_fieldname,
    coalesce((select o.set_value::int from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'sort_order' and o.record_status = 'active'), f.sort_order),
    coalesce((select o.set_value::boolean from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'is_readonly' and o.record_status = 'active'), f.is_readonly),
    coalesce((select o.set_value::boolean from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'print_hide' and o.record_status = 'active'), f.print_hide)
  from reporting.template_fields f
  where f.template_id = p_template_id and f.record_status = 'active'
  order by coalesce((select o.set_value::int from reporting.template_field_overrides o
              where o.template_field_id = f.id and o.tenant_id = p_tenant_id
                and o.property = 'sort_order' and o.record_status = 'active'), f.sort_order);
$$;
grant execute on function reporting.get_effective_template_fields(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Wire reporting.reports (0009) to a template so an instance always knows
-- which template it was assembled from.
-- ---------------------------------------------------------------------------
alter table reporting.reports add column if not exists template_id uuid references reporting.report_templates(id);
create index if not exists reports_template_idx on reporting.reports(template_id);

-- ---------------------------------------------------------------------------
-- RLS: system templates (tenant_id null) are readable by everyone
-- authenticated; only writable by service_role (platform-shipped, curated
-- centrally — same posture ERPNext takes with its own stock DocTypes).
-- Tenant templates and all overrides are tenant-scoped normally.
-- ---------------------------------------------------------------------------
alter table reporting.report_templates enable row level security;
alter table reporting.report_templates force row level security;
create policy sel on reporting.report_templates for select to authenticated
  using (tenant_id is null or app.has_tenant_access(tenant_id, 'read'));
create policy ins on reporting.report_templates for insert to authenticated
  with check (tenant_id is not null and app.has_tenant_access(tenant_id, 'contribute'));
create policy upd on reporting.report_templates for update to authenticated
  using (tenant_id is not null and app.has_tenant_access(tenant_id, 'contribute'))
  with check (tenant_id is not null and app.has_tenant_access(tenant_id, 'contribute'));

-- Tables with a direct template_id column.
do $$
declare t text;
begin
  foreach t in array array['reporting.template_sections','reporting.template_fields',
                            'reporting.template_approval_steps',
                            'reporting.template_render_profiles'] loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    -- readable whenever the parent template is readable (system or own-tenant)
    execute format($p$create policy sel on %s for select to authenticated
      using (exists (select 1 from reporting.report_templates rt
                     where rt.id = template_id
                       and (rt.tenant_id is null or app.has_tenant_access(rt.tenant_id,'read'))));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
      with check (exists (select 1 from reporting.report_templates rt
                     where rt.id = template_id and rt.tenant_id is not null
                       and app.has_tenant_access(rt.tenant_id,'contribute')));$p$, t);
  end loop;
end $$;

-- template_data_bindings has no template_id column of its own (it hangs off
-- template_field_id) — RLS must join through template_fields to reach the
-- parent template's tenant.
alter table reporting.template_data_bindings enable row level security;
alter table reporting.template_data_bindings force row level security;
create policy sel on reporting.template_data_bindings for select to authenticated
  using (exists (
    select 1 from reporting.template_fields tf
    join reporting.report_templates rt on rt.id = tf.template_id
    where tf.id = template_field_id
      and (rt.tenant_id is null or app.has_tenant_access(rt.tenant_id, 'read'))
  ));
create policy ins on reporting.template_data_bindings for insert to authenticated
  with check (exists (
    select 1 from reporting.template_fields tf
    join reporting.report_templates rt on rt.id = tf.template_id
    where tf.id = template_field_id
      and rt.tenant_id is not null
      and app.has_tenant_access(rt.tenant_id, 'contribute')
  ));

alter table reporting.template_field_overrides enable row level security;
alter table reporting.template_field_overrides force row level security;
create policy sel on reporting.template_field_overrides for select to authenticated
  using (app.has_tenant_access(tenant_id, 'read'));
create policy ins on reporting.template_field_overrides for insert to authenticated
  with check (app.has_tenant_access(tenant_id, 'contribute'));
create policy upd on reporting.template_field_overrides for update to authenticated
  using (app.has_tenant_access(tenant_id, 'contribute'))
  with check (app.has_tenant_access(tenant_id, 'contribute'));

do $$
declare t text;
begin
  foreach t in array array['reporting.report_templates','reporting.template_field_overrides'] loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
  end loop;
end $$;

commit;
