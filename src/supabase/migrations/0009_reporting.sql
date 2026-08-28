-- ============================================================================
-- Migration 0009: reporting + claim-to-evidence traceability
-- Every material report statement must be traceable to a finding/fact/
-- calculation/evidence. report_claim_links is that spine.
-- ============================================================================

create table reporting.reports (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  matter_id        uuid not null references core.matters(id),
  report_type      text not null,      -- fraud_exam, treasury_governance, damages, monitor...
  title            text not null,
  version          text not null default '0.1.0',
  status           text not null default 'outline',
  -- outline|drafting|evidence_linking|technical_review|legal_review|approved|issued|amended|superseded
  evidence_cutoff  date,
  calculation_cutoff date,
  confidentiality  core.confidentiality_level not null default 'attorney_work_product',
  issued_at        timestamptz,
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1,
  unique (matter_id, title, version)
);
create index on reporting.reports(matter_id);

create table reporting.report_sections (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  report_id      uuid not null references reporting.reports(id),
  section_number text,
  heading        text,
  body           text,
  sort_order     int,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on reporting.report_sections(report_id);

create table reporting.report_claim_links (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  report_section_id uuid not null references reporting.report_sections(id),
  claim_text     text,                 -- the material assertion in the sentence
  statement_type text,                 -- fact|expert_opinion|legal_issue|recommendation|mgmt_representation
  finding_id     uuid references investigation.findings(id),
  fact_id        uuid references investigation.facts(id),
  evidence_id    uuid references evidence.evidence_items(id),
  calculation_run_ref uuid,            -- FK to calculations.* in a later migration
  reviewer_approved boolean not null default false,
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on reporting.report_claim_links(report_section_id);

-- Stamp + RLS
do $$
declare t text; tables text[] := array[
  'reporting.reports','reporting.report_sections'];
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
  execute 'alter table reporting.report_claim_links enable row level security';
  execute 'alter table reporting.report_claim_links force row level security';
  execute $p$create policy sel on reporting.report_claim_links for select to authenticated
      using (app.has_matter_access(matter_id, 'read'));$p$;
  execute $p$create policy ins on reporting.report_claim_links for insert to authenticated
      with check (app.has_matter_access(matter_id, 'contribute'));$p$;
end $$;
