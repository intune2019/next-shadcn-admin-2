-- ============================================================================
-- Migration 0014: Canonical SQL Library and Mapping Logic
--
-- The ingestion/ETL layer that gets raw source files (bank exports, ERP
-- exports, payroll exports, etc.) into the canonical.* tables built in
-- migration 0006. Purely additive: no existing 0001-0011/0013 object is
-- altered.
--
-- Pipeline (per spec):
--   raw source extract -> staging.* (immutable per dataset version)
--                       -> mapping.* (versioned, approval-controlled rules)
--                       -> canonical.* (0006)
--                       -> identity.* (entity resolution)
--                       -> quality.* (validation / reconciliation / exceptions)
--                       -> analytics.* (rule-ready views + fraud-relationship
--                          detectors)
--
-- Schema layout follows the spec's "1. SQL Schema Layout" table exactly:
-- `staging` and `mapping` are new schemas (created below); `identity` already
-- exists (0001) but has no tables yet; `quality` is new. `canonical` (0006)
-- is the feed target and is not modified.
--
-- Idempotent ingestion (ADR-0001 / 0006): canonical rows are unique by
-- (matter_id, source_dataset_version_id, source_record_id); dataset versions
-- are unique by (matter, source, raw_file_sha256) -- that registry already
-- exists as evidence.dataset_versions (0005) and is reused here as-is rather
-- than re-implemented, so this migration adds no duplicate dataset-version
-- table. Staging rows add a second idempotency guard:
-- unique(dataset_version_id, source_row_number), which stops literal re-
-- ingestion of the same physical file rows; business-level duplicate
-- source_record_id values are intentionally NOT blocked at insert time --
-- per the spec's exception workflow (section 19) that is a "flag for
-- dedupe/supersession" data-quality decision, not a hard constraint, so it is
-- handled by quality.mapping_exceptions / quality.duplicate_detection_results.
--
-- Crypto-shredding (ADR-0001 decision D / 0004): every raw identifier that
-- must never land in plaintext (bank account numbers, tax IDs) is routed
-- through the EXISTING security.token()/security.vault_put() functions from
-- 0004. This migration does not reinvent tokenization; mapping.normalization_rules
-- rows for 'account_tokenization' and 'tax_id_tokenization' document that
-- routing, and canonical.bank_accounts.account_token / vendors.tax_id_token
-- (0006) remain the only place the tokenized value is stored.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- New schemas + default grants (mirrors 0001's pattern exactly so tables
-- created later in THIS migration automatically inherit table-level grants;
-- RLS policies, added per-table below, do the real access control).
-- ---------------------------------------------------------------------------
create schema if not exists staging;   -- raw system extracts and parsed records (immutable per dataset version)
create schema if not exists mapping;   -- mapping definitions, transformations, validation, source dictionaries
create schema if not exists quality;   -- reconciliations, validation failures, mapping exceptions

grant usage on schema staging, mapping, quality to authenticated, service_role;
alter default privileges in schema staging, mapping, quality
  grant select, insert, update, delete on tables to authenticated, service_role;

-- ============================================================================
-- 6. MAPPING REGISTRY TABLES (global, shared library -- not matter-scoped)
-- ============================================================================

create table mapping.source_systems (
  id             uuid primary key default gen_random_uuid(),
  system_code    text not null unique,     -- generic_bank_csv, sap, workday, adp...
  system_name    text not null,
  system_category text check (system_category in
    ('bank_file_format','erp','accounting','hris','payroll','expense',
     'procurement','treasury_portal','other')),
  vendor_name    text,
  created_at     timestamptz not null default now(),
  created_by     uuid
);

create table mapping.source_objects (
  id                uuid primary key default gen_random_uuid(),
  source_system_id  uuid not null references mapping.source_systems(id),
  object_name       text not null,        -- invoice, vendor, payment, gl_entry...
  object_category   text,
  description       text,
  created_at        timestamptz not null default now(),
  unique (source_system_id, object_name)
);

create table mapping.transformation_definitions (
  id                  uuid primary key default gen_random_uuid(),
  transformation_code text not null unique,
  transformation_name text not null,
  transformation_logic text,             -- approved transform spec (sql/pseudocode/description)
  logic_language      text not null default 'sql',
  description         text,
  created_at          timestamptz not null default now(),
  created_by          uuid,
  approved_by          uuid,
  approved_at          timestamptz
);

-- ---------------------------------------------------------------------------
-- mapping.mapping_versions : THE mapping-package registry.
-- Lifecycle (spec section 20): Draft -> Tested -> Peer Reviewed -> Approved ->
-- Active -> Superseded -> Retired. `target_table_status` is honest about the
-- fact that some spec-intended canonical targets (purchase_orders,
-- receiving_records, contracts, assets, claims) do not exist yet in 0006 --
-- see the seed data / final report for the full list.
-- ---------------------------------------------------------------------------
create table mapping.mapping_versions (
  id                    uuid primary key default gen_random_uuid(),
  source_system_id      uuid not null references mapping.source_systems(id),
  source_object_id      uuid references mapping.source_objects(id),
  package_name          text not null,
  package_description   text,
  target_schema         text not null default 'canonical',
  target_table          text not null,
  target_table_status   text not null default 'available'
                         check (target_table_status in ('available','pending_release_2')),
  version_number        text not null default '0.1.0',
  status                text not null default 'draft'
                         check (status in
                           ('draft','tested','peer_reviewed','approved','active','superseded','retired')),
  -- required package artifacts (spec section 20)
  sample_file_evidence_id       uuid references evidence.evidence_items(id),
  source_data_dictionary_note   text,
  null_handling_policy          text,
  validation_rule_summary       text,
  reconciliation_rule_summary   text,
  expected_output_sample        text,
  change_log                    text,
  -- lifecycle timestamps/actors
  tested_at             timestamptz, tested_by uuid,
  peer_reviewed_at       timestamptz, peer_reviewed_by uuid,
  approved_at            timestamptz, approved_by uuid,
  activated_at           timestamptz,
  superseded_at          timestamptz,
  superseded_by_version_id uuid references mapping.mapping_versions(id),
  retired_at             timestamptz,
  created_at             timestamptz not null default now(),
  created_by             uuid,
  updated_at             timestamptz not null default now(),
  updated_by             uuid,
  row_version            integer not null default 1,
  unique (source_system_id, package_name, version_number)
);

-- No active mapping is edited in place: status must move through the
-- lifecycle in order (rework allowed one step back for failed review/test).
create or replace function mapping.tg_enforce_version_lifecycle()
returns trigger language plpgsql as $$
declare
  v_allowed jsonb := '{
    "draft":         ["draft","tested","retired"],
    "tested":        ["tested","peer_reviewed","draft","retired"],
    "peer_reviewed":  ["peer_reviewed","approved","tested","retired"],
    "approved":      ["approved","active","peer_reviewed","retired"],
    "active":        ["active","superseded","retired"],
    "superseded":    ["superseded","retired"],
    "retired":       ["retired"]
  }'::jsonb;
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if not (v_allowed -> old.status) ? new.status then
      raise exception 'Mapping package % cannot transition from % to %',
        new.id, old.status, new.status using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

create trigger tg_stamp before insert or update on mapping.mapping_versions
  for each row execute function app.tg_stamp_row();
create trigger tg_lifecycle before update on mapping.mapping_versions
  for each row execute function mapping.tg_enforce_version_lifecycle();

-- mapping.mapping_approvals : peer review / QA history behind each lifecycle step.
create table mapping.mapping_approvals (
  id                    uuid primary key default gen_random_uuid(),
  mapping_version_id    uuid not null references mapping.mapping_versions(id),
  review_stage          text not null check (review_stage in
                           ('performance_test','tested','peer_reviewed','approved')),
  reviewer_id           uuid,
  review_notes          text,
  review_result         text check (review_result in ('pass','fail','conditional')),
  performance_test_summary jsonb,
  reviewed_at           timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  created_by            uuid
);
create index on mapping.mapping_approvals(mapping_version_id);

-- mapping.field_mappings : field-by-field crosswalk per mapping package.
create table mapping.field_mappings (
  id                  uuid primary key default gen_random_uuid(),
  mapping_version_id  uuid not null references mapping.mapping_versions(id),
  source_system_id    uuid not null references mapping.source_systems(id),
  source_object_name  text not null,
  source_field_name   text not null,
  source_data_type    text,
  canonical_schema    text not null,
  canonical_table     text not null,
  canonical_field     text not null,
  transformation_id   uuid references mapping.transformation_definitions(id),
  required_flag       boolean not null default false,
  default_value       text,
  null_handling       text not null default 'warn'
                       check (null_handling in ('fail','warn','default','exclude')),
  validation_rule     text,
  confidence_rule     text,
  effective_from      date not null default current_date,
  effective_to        date,
  approved_by         uuid,
  created_at          timestamptz not null default now(),
  created_by          uuid
);
create index on mapping.field_mappings(mapping_version_id);

-- mapping.value_crosswalks : code/status/currency/payment-type crosswalk library.
-- Unmapped values never silently default -- they create a quality.mapping_exceptions
-- row (exception_type = 'unknown_status_code' / 'unrecognized_currency').
create table mapping.value_crosswalks (
  id                  uuid primary key default gen_random_uuid(),
  source_system_id    uuid not null references mapping.source_systems(id),
  source_object       text,
  crosswalk_type      text not null,     -- payment_type, vendor_status, employee_status, ...
  source_code         text not null,
  canonical_code      text not null,
  description         text,
  effective_from      date not null default current_date,
  effective_to        date,
  approved_status     text not null default 'draft' check (approved_status in ('draft','approved')),
  mapping_version_id  uuid references mapping.mapping_versions(id),
  exception_behavior  text not null default 'create_mapping_exception',
  created_at          timestamptz not null default now(),
  created_by          uuid,
  unique (source_system_id, crosswalk_type, source_code, effective_from)
);
create index on mapping.value_crosswalks(crosswalk_type, source_code);

-- mapping.normalization_rules : standardization rule library (section 12).
-- Tokenization rules route to the EXISTING security.token()/vault_put()
-- functions from 0004 rather than reinventing crypto -- see uses_security_function.
create table mapping.normalization_rules (
  id                      uuid primary key default gen_random_uuid(),
  rule_type               text not null check (rule_type in (
                             'name','address','phone','email','invoice_number',
                             'account_tokenization','currency','date','amount','status',
                             'description','tax_id_tokenization','entity_suffix',
                             'device','serial_number')),
  rule_name               text not null,
  rule_logic_description  text,
  canonical_field_target  text,
  transformation_id       uuid references mapping.transformation_definitions(id),
  uses_security_function  text,          -- e.g. security.token(tenant_id, raw_value)
  created_at              timestamptz not null default now(),
  created_by              uuid,
  approved_by             uuid,
  approved_at             timestamptz
);

-- mapping.source_data_dictionaries : source-system data dictionary capture.
create table mapping.source_data_dictionaries (
  id                uuid primary key default gen_random_uuid(),
  source_system_id  uuid not null references mapping.source_systems(id),
  source_object_name text not null,
  field_name        text not null,
  source_data_type  text,
  is_required       boolean not null default false,
  sample_value      text,
  description       text,
  captured_at       timestamptz not null default now(),
  created_by        uuid
);
create index on mapping.source_data_dictionaries(source_system_id, source_object_name);

-- RLS: global/shared registry -- mirrors 0008's rules.rule_definitions pattern
-- exactly (select-to-authenticated + all-to-service_role; ENABLE only, not
-- FORCE, matching the precedent for shared library tables).
do $$
declare t text; tables text[] := array[
  'mapping.source_systems','mapping.source_objects','mapping.transformation_definitions',
  'mapping.mapping_versions','mapping.mapping_approvals','mapping.field_mappings',
  'mapping.value_crosswalks','mapping.normalization_rules','mapping.source_data_dictionaries'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format($p$create policy sel on %s for select to authenticated using (true);$p$, t);
    execute format($p$create policy all_sr on %s for all to service_role using (true) with check (true);$p$, t);
  end loop;
end $$;

-- ============================================================================
-- 5. RAW STAGING LIBRARY
-- Landing zone for uploaded files before validation. Every table shares the
-- mandatory staging column set (spec section 5). raw_payload_json is never
-- altered after ingestion -- enforced by staging.tg_protect_raw_payload below,
-- not just documented in a comment.
-- ============================================================================

create or replace function staging.tg_protect_raw_payload()
returns trigger language plpgsql as $$
begin
  if new.raw_payload_json is distinct from old.raw_payload_json
     or new.raw_payload_hash is distinct from old.raw_payload_hash then
    raise exception 'staging.%: raw_payload_json/raw_payload_hash are immutable after ingestion (row %)',
      tg_table_name, old.staging_row_id
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

do $$
declare
  t text;
  raw_tables text[] := array[
    'bank_transactions_raw','gl_journal_entries_raw','ap_invoices_raw','ap_payments_raw',
    'vendor_master_raw','vendor_bank_accounts_raw','purchase_orders_raw','receiving_records_raw',
    'employee_master_raw','payroll_payments_raw','expense_claims_raw','bank_user_access_raw',
    'payment_approvals_raw','contracts_raw','assets_raw','claims_raw',
    'email_messages_raw','access_logs_raw'
  ];
begin
  foreach t in array raw_tables loop
    execute format($f$
      create table staging.%1$I (
        staging_row_id       uuid primary key default gen_random_uuid(),
        tenant_id             uuid not null,
        matter_id             uuid not null references core.matters(id),
        dataset_version_id    uuid not null references evidence.dataset_versions(id),
        source_file_id        uuid references evidence.evidence_files(id),
        source_row_number     bigint,
        source_record_id      text,
        raw_payload_json      jsonb not null,
        raw_payload_hash      bytea,
        ingested_at           timestamptz not null default now(),
        parse_status          text not null default 'pending'
                               check (parse_status in ('pending','parsed','parse_failed')),
        parse_error           text,
        mapped_status         text not null default 'unmapped'
                               check (mapped_status in
                                 ('unmapped','mapped','mapping_failed','excluded','superseded')),
        canonical_schema      text,
        canonical_table       text,
        canonical_record_id   uuid,
        mapping_version_id    uuid references mapping.mapping_versions(id),
        data_quality_status   text not null default 'unverified'
                               check (data_quality_status in ('passed','warning','failed','unverified')),
        record_status         core.record_status not null default 'active',
        created_at            timestamptz not null default now(),
        created_by            uuid,
        updated_at            timestamptz not null default now(),
        updated_by            uuid,
        row_version           integer not null default 1,
        unique (dataset_version_id, source_row_number)
      );
    $f$, t);
    execute format('create index on staging.%I(matter_id, dataset_version_id)', t);
    execute format('create index on staging.%I(matter_id, mapped_status)', t);
    execute format('create index on staging.%I using gin (raw_payload_json)', t);

    execute format('create trigger tg_stamp before insert or update on staging.%I
                     for each row execute function app.tg_stamp_row()', t);
    execute format('create trigger tg_protect_raw before update on staging.%I
                     for each row execute function staging.tg_protect_raw_payload()', t);

    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy sel on staging.%I for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on staging.%I for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
    execute format($p$create policy upd on staging.%I for update to authenticated
        using (app.has_matter_access(matter_id, 'contribute'))
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;

-- ============================================================================
-- 9. ENTITY RESOLUTION AND IDENTITY MAPPING  (schema `identity` created 0001)
-- Source identities stay separate from canonical identity decisions.
-- ============================================================================

create table identity.identity_claims (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null,
  matter_id             uuid not null references core.matters(id),
  canonical_entity_id   uuid references canonical.entities(id),
  source_system_id      uuid references mapping.source_systems(id),
  source_object_name    text,
  source_record_id      text,
  claimed_name          text,
  claimed_identifier_type  text,   -- tax_id, bank_account, government_id, email, phone, device_id
  claimed_identifier_token text,   -- via security.token(); never the raw value
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_evidence_id    uuid references evidence.evidence_items(id),
  created_at            timestamptz not null default now(),
  created_by            uuid
);
create index on identity.identity_claims(matter_id, canonical_entity_id);

create table identity.entity_aliases (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  entity_id      uuid not null references canonical.entities(id),
  alias_type     text check (alias_type in
                   ('dba','misspelling','maiden_name','source_system_variant','translation','abbreviation')),
  alias_value    text not null,
  alias_value_normalized text,
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on identity.entity_aliases(matter_id, entity_id);
create index on identity.entity_aliases using gin (alias_value_normalized extensions.gin_trgm_ops);

-- identity.entity_match_candidates : potential matches created by rules
-- (deterministic identifier match, pg_trgm name similarity, address/bank
-- collisions...). Weighted per spec section 9.
create table identity.entity_match_candidates (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  entity_id_a    uuid not null references canonical.entities(id),
  entity_id_b    uuid not null references canonical.entities(id),
  match_score    numeric(6,2) not null,
  score_breakdown jsonb,
  match_basis    text[],
  candidate_type text not null check (candidate_type in
                   ('exact_identity','probable_identity','possible_relationship',
                    'shared_attribute','unverified_association')),
  generated_by   text not null,          -- rule code / algorithm version
  review_status  text not null default 'pending' check (review_status in
                   ('pending','auto_linked','high_priority_review','review',
                    'preserved_as_association','dismissed')),
  created_at     timestamptz not null default now(),
  created_by     uuid,
  check (entity_id_a <> entity_id_b),
  unique (matter_id, entity_id_a, entity_id_b, generated_by)
);
create index on identity.entity_match_candidates(matter_id, review_status);

create table identity.entity_match_decisions (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  match_candidate_id uuid not null references identity.entity_match_candidates(id),
  decision           text not null check (decision in
                       ('confirmed_match','disproved_match','possible_relationship_only','needs_more_evidence')),
  decided_by         uuid,
  decision_rationale text,
  decided_at         timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  created_by         uuid
);
create index on identity.entity_match_decisions(matter_id, match_candidate_id);

-- identity.entity_relationships : ownership, employment, control, address,
-- account, device relationships. A match is not a legal conclusion --
-- relationship_status distinguishes review_candidate / high_priority_review /
-- confirmed / disproved / documented_exception.
create table identity.entity_relationships (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null,
  matter_id             uuid not null references core.matters(id),
  from_entity_id        uuid not null references canonical.entities(id),
  to_entity_id          uuid not null references canonical.entities(id),
  relationship_type     text not null,   -- shared_address, shared_bank_account, employment,
                                          -- ownership, control, shared_contact, shared_device,
                                          -- beneficial_owner...
  relationship_status   text not null default 'review_candidate' check (relationship_status in
                           ('review_candidate','high_priority_review','confirmed','disproved',
                            'documented_exception')),
  confidence_score      numeric(5,2),
  match_algorithm_version text,
  match_basis           jsonb,
  source_evidence_id    uuid references evidence.evidence_items(id),
  effective_from        date,
  effective_to          date,
  record_status         core.record_status not null default 'active',
  created_at            timestamptz not null default now(),
  created_by            uuid,
  updated_at            timestamptz not null default now(),
  updated_by            uuid,
  row_version           integer not null default 1,
  check (from_entity_id <> to_entity_id),
  unique (from_entity_id, to_entity_id, relationship_type)
);
create index on identity.entity_relationships(matter_id, relationship_type, relationship_status);

create table identity.relationship_evidence (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  relationship_id uuid not null references identity.entity_relationships(id),
  evidence_id    uuid references evidence.evidence_items(id),
  evidence_role  text,
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on identity.relationship_evidence(relationship_id);

create table identity.entity_merge_history (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  surviving_entity_id uuid not null references canonical.entities(id),
  merged_entity_id    uuid not null references canonical.entities(id),
  match_decision_id   uuid references identity.entity_match_decisions(id),
  action              text not null check (action in ('merge','unmerge')),
  performed_by        uuid,
  performed_at        timestamptz not null default now(),
  rationale           text,
  created_at          timestamptz not null default now()
);
create index on identity.entity_merge_history(matter_id, surviving_entity_id);

create trigger tg_stamp before insert or update on identity.entity_relationships
  for each row execute function app.tg_stamp_row();

-- RLS: matter-scoped identity tables (same forced pattern as 0006/0008).
do $$
declare t text; tables text[] := array[
  'identity.identity_claims','identity.entity_aliases','identity.entity_match_candidates',
  'identity.entity_match_decisions','identity.entity_relationships',
  'identity.relationship_evidence','identity.entity_merge_history'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
  -- resolution decisions and merges are consequential: require 'review' access
  execute $p$create policy ins_review on identity.entity_match_decisions for insert to authenticated
      with check (app.has_matter_access(matter_id, 'review'));$p$;
  execute $p$create policy ins_review on identity.entity_merge_history for insert to authenticated
      with check (app.has_matter_access(matter_id, 'review'));$p$;
  -- entity_relationships is updatable (status moves review_candidate -> confirmed/disproved)
  execute $p$create policy upd on identity.entity_relationships for update to authenticated
      using (app.has_matter_access(matter_id, 'review'))
      with check (app.has_matter_access(matter_id, 'review'));$p$;
end $$;

-- Drop the plain 'ins' policy on the two tables above so it doesn't coexist
-- with the stricter 'review'-gated insert policy (Postgres RLS policies are
-- OR'd together, and INSERT is not needed at 'contribute' for these two).
drop policy ins on identity.entity_match_decisions;
drop policy ins on identity.entity_merge_history;

-- Bonus entity-resolution utility: pg_trgm fuzzy name matching populates
-- identity.entity_match_candidates directly (spec section 9's
-- "Normalized-name similarity 20-65" weight band).
create or replace function identity.suggest_name_match_candidates(
  p_matter_id uuid,
  p_min_similarity numeric default 0.5
) returns integer
language plpgsql
set search_path = extensions, public
as $$
declare
  v_count integer := 0;
  v_pair record;
  v_score numeric(6,2);
  v_candidate_type text;
  v_review_status text;
  v_new_id uuid;
begin
  for v_pair in
    select a.id as entity_a, b.id as entity_b, a.tenant_id,
           similarity(a.name_normalized, b.name_normalized) as sim
    from canonical.entities a
    join canonical.entities b
      on a.matter_id = b.matter_id
     and a.id < b.id
     and a.name_normalized % b.name_normalized
    where a.matter_id = p_matter_id
      and a.name_normalized is not null and b.name_normalized is not null
      and similarity(a.name_normalized, b.name_normalized) >= p_min_similarity
  loop
    v_score := round((20 + v_pair.sim * 45)::numeric, 2);
    v_candidate_type := case when v_score >= 60 then 'probable_identity' else 'shared_attribute' end;
    v_review_status  := case when v_score >= 60 then 'review' else 'preserved_as_association' end;

    insert into identity.entity_match_candidates (
      tenant_id, matter_id, entity_id_a, entity_id_b, match_score, score_breakdown,
      match_basis, candidate_type, generated_by, review_status
    ) values (
      v_pair.tenant_id, p_matter_id, v_pair.entity_a, v_pair.entity_b, v_score,
      jsonb_build_object('name_similarity', v_pair.sim),
      array['name_normalized_trgm'], v_candidate_type, 'pg_trgm_name_similarity_v1', v_review_status
    )
    on conflict (matter_id, entity_id_a, entity_id_b, generated_by) do nothing
    returning id into v_new_id;

    if v_new_id is not null then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function identity.suggest_name_match_candidates(uuid, numeric) to authenticated, service_role;

-- ============================================================================
-- 13. DATA QUALITY AND RECONCILIATION TABLES
-- ============================================================================

-- quality.validation_rules : row/table/dataset-level tests, tied to a mapping
-- package (global, like mapping.* above).
create table quality.validation_rules (
  id                uuid primary key default gen_random_uuid(),
  mapping_version_id uuid references mapping.mapping_versions(id),
  rule_scope        text not null check (rule_scope in ('row','table','dataset')),
  rule_name         text not null,
  rule_description  text,
  check_expression  text,
  severity          text not null default 'fail' check (severity in ('fail','warning')),
  created_at        timestamptz not null default now(),
  created_by        uuid
);

create table quality.validation_results (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  dataset_version_id uuid not null references evidence.dataset_versions(id),
  validation_rule_id uuid references quality.validation_rules(id),
  staging_table      text,
  staging_row_id     uuid,
  result             text not null check (result in ('passed','warning','failed')),
  detail             text,
  created_at         timestamptz not null default now(),
  created_by         uuid
);
create index on quality.validation_results(matter_id, dataset_version_id);

-- ---------------------------------------------------------------------------
-- quality.mapping_exceptions : THE mapping exception workflow (spec section
-- 19), implemented as real check constraints rather than prose. The compound
-- check pins every exception_type to its mandated required_action.
-- ---------------------------------------------------------------------------
create table quality.mapping_exceptions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  dataset_version_id  uuid references evidence.dataset_versions(id),
  mapping_version_id  uuid references mapping.mapping_versions(id),
  staging_table       text,
  staging_row_id      uuid,
  source_record_id    text,
  exception_type      text not null check (exception_type in (
                         'missing_required_field','invalid_date','unknown_status_code',
                         'unrecognized_currency','duplicate_source_id','ambiguous_entity_match',
                         'imbalanced_journal_entry','source_total_mismatch','schema_drift',
                         'unsupported_file_format')),
  required_action     text not null check (required_action in (
                         'fail_row','warn_and_crosswalk_review','fail_or_manual_resolution',
                         'flag_dedupe','require_reviewer_decision','fail_validation',
                         'block_approval','suspend_mapping','quarantine')),
  -- the exception-type -> required-action pairing IS the workflow table from
  -- spec section 19, enforced as a hard constraint:
  constraint mapping_exceptions_workflow_chk check (
    (exception_type = 'missing_required_field' and required_action = 'fail_row') or
    (exception_type = 'invalid_date'            and required_action = 'fail_row') or
    (exception_type = 'unknown_status_code'      and required_action = 'warn_and_crosswalk_review') or
    (exception_type = 'unrecognized_currency'    and required_action = 'fail_or_manual_resolution') or
    (exception_type = 'duplicate_source_id'      and required_action = 'flag_dedupe') or
    (exception_type = 'ambiguous_entity_match'   and required_action = 'require_reviewer_decision') or
    (exception_type = 'imbalanced_journal_entry' and required_action = 'fail_validation') or
    (exception_type = 'source_total_mismatch'    and required_action = 'block_approval') or
    (exception_type = 'schema_drift'             and required_action = 'suspend_mapping') or
    (exception_type = 'unsupported_file_format'  and required_action = 'quarantine')
  ),
  exception_status    text not null default 'open' check (exception_status in
                         ('open','in_review','resolved','overridden','dismissed')),
  field_name          text,
  raw_value           text,
  expected_format     text,
  detail               text,
  resolution_notes     text,
  resolved_by          uuid,
  resolved_at          timestamptz,
  created_at           timestamptz not null default now(),
  created_by            uuid,
  updated_at            timestamptz not null default now(),
  updated_by            uuid,
  row_version           integer not null default 1
);
create index on quality.mapping_exceptions(matter_id, exception_status);
create index on quality.mapping_exceptions(matter_id, exception_type);

create trigger tg_stamp before insert or update on quality.mapping_exceptions
  for each row execute function app.tg_stamp_row();

-- Mandatory dataset checks (spec section 13).
create table quality.reconciliations (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null,
  matter_id             uuid not null references core.matters(id),
  dataset_version_id    uuid not null references evidence.dataset_versions(id),
  reconciliation_type   text not null check (reconciliation_type in
                           ('row_count','amount','balanced_journal','payment_linkage',
                            'account_continuity','mapping_completeness','schema_drift')),
  source_value          numeric(20,4),
  canonical_value       numeric(20,4),
  rejected_value        numeric(20,4) default 0,
  documented_adjustments numeric(20,4) default 0,
  tolerance             numeric(20,4) default 0,
  result                text not null default 'not_evaluated' check (result in
                           ('balanced','out_of_balance','not_evaluated')),
  evaluated_at          timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  created_by            uuid
);
create index on quality.reconciliations(matter_id, dataset_version_id);

create table quality.reconciling_items (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  matter_id        uuid not null references core.matters(id),
  reconciliation_id uuid not null references quality.reconciliations(id),
  description      text,
  amount           numeric(20,4),
  disposition      text not null default 'unresolved' check (disposition in
                      ('unresolved','explained','adjusted','written_off')),
  created_at       timestamptz not null default now(),
  created_by       uuid
);
create index on quality.reconciling_items(reconciliation_id);

create table quality.data_completeness_checks (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null,
  matter_id             uuid not null references core.matters(id),
  data_source_id        uuid references evidence.data_sources(id),
  expected_period_start date,
  expected_period_end   date,
  expected_file_count   integer,
  received_file_count   integer default 0,
  status                text not null default 'not_received' check (status in
                           ('complete','incomplete','not_received')),
  checked_at            timestamptz not null default now(),
  created_by            uuid
);
create index on quality.data_completeness_checks(matter_id, data_source_id);

create table quality.duplicate_detection_results (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  dataset_version_id  uuid references evidence.dataset_versions(id),
  duplicate_basis     text not null check (duplicate_basis in ('source_hash','source_record_id')),
  staging_table       text,
  duplicate_group_key text,
  row_count           integer not null,
  disposition         text not null default 'flagged' check (disposition in
                         ('flagged','superseded','confirmed_duplicate','not_duplicate')),
  created_at          timestamptz not null default now(),
  created_by          uuid
);
create index on quality.duplicate_detection_results(matter_id, dataset_version_id);

create table quality.schema_drift_events (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  mapping_version_id  uuid references mapping.mapping_versions(id),
  dataset_version_id  uuid references evidence.dataset_versions(id),
  drift_type          text not null check (drift_type in
                         ('column_added','column_removed','type_changed','format_changed')),
  field_name          text,
  previous_definition text,
  observed_definition text,
  status               text not null default 'pending_review' check (status in
                          ('pending_review','mapping_suspended','resolved')),
  detected_at          timestamptz not null default now(),
  created_by            uuid
);
create index on quality.schema_drift_events(matter_id, mapping_version_id);

create table quality.data_quality_attestations (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  matter_id           uuid not null references core.matters(id),
  dataset_version_id  uuid not null references evidence.dataset_versions(id),
  readiness_status    text not null check (readiness_status in
                         ('not_ready','failed','warning','approved','superseded','archived')),
  attested_by         uuid not null,
  attestation_notes   text,
  attested_at         timestamptz not null default now(),
  created_at          timestamptz not null default now()
);
create index on quality.data_quality_attestations(matter_id, dataset_version_id);

-- RLS
do $$
declare t text; tables text[] := array[
  'quality.validation_results','quality.mapping_exceptions','quality.reconciliations',
  'quality.reconciling_items','quality.data_completeness_checks',
  'quality.duplicate_detection_results','quality.schema_drift_events',
  'quality.data_quality_attestations'];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
  -- mapping_exceptions resolution requires reviewer authority
  execute $p$create policy upd on quality.mapping_exceptions for update to authenticated
      using (app.has_matter_access(matter_id, 'review'))
      with check (app.has_matter_access(matter_id, 'review'));$p$;
end $$;

-- quality.validation_rules is global (tied to a shared mapping package).
alter table quality.validation_rules enable row level security;
create policy sel on quality.validation_rules for select to authenticated using (true);
create policy all_sr on quality.validation_rules for all to service_role using (true) with check (true);

-- ============================================================================
-- SEED: mapping.source_systems + the 25 minimum initial mapping packages
-- (spec section 21), status = 'draft' -- none of these have been through
-- real testing/peer review/approval yet.
-- ============================================================================
insert into mapping.source_systems (system_code, system_name, system_category) values
  ('generic_bank_csv',        'Generic Bank CSV Export',              'bank_file_format'),
  ('bai2',                    'BAI2 Bank File',                       'bank_file_format'),
  ('camt053',                 'ISO 20022 CAMT.053 Bank Statement',    'bank_file_format'),
  ('mt940',                   'SWIFT MT940 Bank Statement',           'bank_file_format'),
  ('generic_ap',              'Generic Accounts Payable Export',      'accounting'),
  ('generic_vendor_master',   'Generic Vendor Master Export',         'erp'),
  ('generic_payment_register','Generic Payment Register',             'treasury_portal'),
  ('generic_gl',              'Generic General Ledger Journal Export','accounting'),
  ('generic_employee_master', 'Generic Employee Master Export',       'hris'),
  ('generic_payroll',         'Generic Payroll Payment Export',       'payroll'),
  ('generic_expense',         'Generic Expense Claim Export',         'expense'),
  ('generic_po',              'Generic Purchase Order Export',        'procurement'),
  ('generic_receiving',       'Generic Receiving Record Export',      'procurement'),
  ('generic_contract',        'Generic Contract Register',            'other'),
  ('generic_bank_user_access','Generic Bank User Access Export',      'treasury_portal'),
  ('generic_payment_approval','Generic Payment Approval Workflow Export','treasury_portal'),
  ('generic_asset_register',  'Generic Asset Register',               'other'),
  ('generic_claims',          'Generic Claims/Billing Export',        'other'),
  ('quickbooks',              'QuickBooks-Compatible Export',         'accounting'),
  ('netsuite',                'NetSuite-Compatible Export',           'erp'),
  ('sap',                     'SAP-Compatible Finance Export',        'erp'),
  ('oracle_erp',              'Oracle-Compatible Finance Export',     'erp'),
  ('workday',                 'Workday-Compatible HR Export',         'hris'),
  ('adp',                     'ADP-Compatible Payroll Export',        'payroll'),
  ('concur',                  'Concur-Compatible Expense Export',     'expense');

insert into mapping.mapping_versions (
  source_system_id, package_name, package_description, target_schema, target_table,
  target_table_status, version_number, status
)
select ss.id, v.package_name, v.package_description, 'canonical', v.target_table, v.target_table_status,
       '0.1.0', 'draft'
from (values
 ('generic_bank_csv','Generic Bank CSV',
   'Generic single-file bank transaction CSV export (any retail/commercial bank portal download).',
   'transactions','available'),
 ('bai2','BAI2 Bank File',
   'BAI2-format bank transaction and balance file.','transactions','available'),
 ('camt053','CAMT.053 Bank Statement',
   'ISO 20022 camt.053.001 bank statement message.','transactions','available'),
 ('mt940','MT940 Bank Statement',
   'SWIFT MT940 customer statement message.','transactions','available'),
 ('generic_ap','Generic AP Invoice Export',
   'Generic accounts payable invoice/voucher export.','invoices','available'),
 ('generic_vendor_master','Generic Vendor Master Export',
   'Generic vendor/supplier master file.','vendors','available'),
 ('generic_payment_register','Generic Payment Register',
   'Generic AP/treasury payment register export.','payments','available'),
 ('generic_gl','Generic GL Journal Export',
   'Generic general-ledger journal entry export; lands as canonical.transactions with '
   'transaction_type=''journal'' and canonical.transaction_legs debit/credit pairs '
   '(no dedicated canonical.journal_entries table in 0006).','transactions','available'),
 ('generic_employee_master','Generic Employee Master Export',
   'Generic HRIS employee master file.','employees','available'),
 ('generic_payroll','Generic Payroll Payment Export',
   'Generic payroll provider payment export; lands as canonical.transactions with '
   'transaction_type=''payroll'' (dedicated canonical.payroll_payments pending Release 2).',
   'transactions','available'),
 ('generic_expense','Generic Expense Claim Export',
   'Generic expense-management platform claim export; lands as canonical.transactions '
   '(dedicated canonical.expense_claims pending Release 2).','transactions','available'),
 ('generic_po','Generic Purchase Order Export',
   'Generic procurement/ERP purchase-order export; correlated via canonical.invoices.po_number '
   'until canonical.purchase_orders ships in Release 2.','invoices','pending_release_2'),
 ('generic_receiving','Generic Receiving Record Export',
   'Generic goods-receipt / service-acceptance export; no canonical target table until '
   'canonical.receiving_records ships in Release 2.','receiving_records','pending_release_2'),
 ('generic_contract','Generic Contract Register',
   'Generic contract-management system register export; no canonical target table until '
   'canonical.contracts ships in Release 2.','contracts','pending_release_2'),
 ('generic_bank_user_access','Generic Bank User Access Export',
   'Treasury bank-portal user/entitlement export; feeds identity.entity_relationships for '
   'segregation-of-duties review.','entity_relationships','available'),
 ('generic_payment_approval','Generic Payment Approval Workflow Export',
   'Workflow/ERP payment-approval event log; lands on canonical.payments initiator/approver/'
   'releaser fields.','payments','available'),
 ('generic_asset_register','Generic Asset Register',
   'Generic fixed-asset or inventory register; no canonical target table until '
   'canonical.assets ships in Release 2.','assets','pending_release_2'),
 ('generic_claims','Generic Claims/Billing Export',
   'Generic insurance/healthcare/grant claim or billing export; no canonical target table until '
   'canonical.claims ships in Release 2.','claims','pending_release_2'),
 ('quickbooks','QuickBooks-Compatible Export',
   'QuickBooks Online/Desktop AP and GL export.','invoices','available'),
 ('netsuite','NetSuite-Compatible Export',
   'NetSuite saved-search / SuiteAnalytics finance export.','transactions','available'),
 ('sap','SAP-Compatible Finance Export',
   'SAP ECC/S4HANA finance (FI/CO) extract.','transactions','available'),
 ('oracle_erp','Oracle-Compatible Finance Export',
   'Oracle EBS/Fusion finance extract.','transactions','available'),
 ('workday','Workday-Compatible HR Export',
   'Workday HCM worker/compensation export.','employees','available'),
 ('adp','ADP-Compatible Payroll Export',
   'ADP Workforce Now / Vantage payroll export; lands as transaction_type=''payroll''.',
   'transactions','available'),
 ('concur','Concur-Compatible Expense Export',
   'SAP Concur expense report export; lands as transaction_type=''card''/expense.',
   'transactions','available')
) as v(source_system_code, package_name, package_description, target_table, target_table_status)
join mapping.source_systems ss on ss.system_code = v.source_system_code;

-- ---------------------------------------------------------------------------
-- SEED: representative field_mappings for three packages, grounded directly
-- in spec section 7 (Bank Transaction / Vendor Master / AP Invoice Mapping).
-- Not all 25 packages are seeded field-by-field -- that is deliberately left
-- for the mapping-authoring workflow itself; see final report.
-- ---------------------------------------------------------------------------
insert into mapping.field_mappings (
  mapping_version_id, source_system_id, source_object_name, source_field_name, source_data_type,
  canonical_schema, canonical_table, canonical_field, required_flag, null_handling, validation_rule
)
select mv.id, mv.source_system_id, 'bank_transactions', f.source_field_name, f.source_data_type,
       'canonical', f.canonical_table, f.canonical_field, f.required_flag, f.null_handling, f.validation_rule
from mapping.mapping_versions mv
cross join (values
 ('Account Number','text','bank_accounts','account_token',true,'fail',
   'tokenize via security.token(tenant_id, raw_value); never store the raw account number'),
 ('Transaction Date','date','transactions','transaction_date',true,'fail',
   'parse to ISO date using source timezone rule'),
 ('Post Date','date','transactions','posting_date',false,'default',
   'parse to ISO date; retain original text if unparseable'),
 ('Amount','numeric','transactions','amount_original',true,'fail',
   'decimal only, never float; debit negative / credit positive normalization applied'),
 ('Currency','text','transactions','currency_original',true,'fail',
   'must validate against ISO 4217; unrecognized currency raises quality.mapping_exceptions'),
 ('Description','text','transactions','description_raw',false,'default',
   'preserve verbatim; description_normalized generated separately'),
 ('Reference','text','transactions','reference_number',false,'default',
   'trim + uppercase; original preserved in raw_payload_json'),
 ('Counterparty','text','transactions','counterparty_entity_id',false,'warn',
   'routed through the entity-resolution workflow, not a direct field copy'),
 ('Transaction Code','text','transactions','transaction_type',true,'warn',
   'crosswalk via mapping.value_crosswalks (crosswalk_type=payment_type); unmapped code raises a mapping exception'),
 ('Bank Branch','text','bank_accounts','branch_identifier',false,'default',
   'normalize or preserve as metadata')
) as f(source_field_name, source_data_type, canonical_table, canonical_field, required_flag, null_handling, validation_rule)
where mv.package_name = 'Generic Bank CSV';

insert into mapping.field_mappings (
  mapping_version_id, source_system_id, source_object_name, source_field_name, source_data_type,
  canonical_schema, canonical_table, canonical_field, required_flag, null_handling, validation_rule
)
select mv.id, mv.source_system_id, 'vendor_master', f.source_field_name, f.source_data_type,
       f.canonical_schema, f.canonical_table, f.canonical_field, f.required_flag, f.null_handling, f.validation_rule
from mapping.mapping_versions mv
cross join (values
 ('Vendor ID','text','canonical','vendors','vendor_external_id',true,'fail','source-system key, preserved verbatim'),
 ('Vendor Name','text','canonical','vendors','legal_name_raw',true,'fail','preserve raw'),
 ('Vendor Name Normalized','text','canonical','vendors','legal_name_normalized',false,'default',
   'apply legal-entity suffix normalization (mapping.normalization_rules rule_type=entity_suffix)'),
 ('Tax ID','text','canonical','vendors','tax_id_token',false,'warn',
   'tokenize/encrypt via security.token()/security.vault_put(); compare exact token only'),
 ('Address','text','canonical','addresses','street',false,'default',
   'parse into street/city/region/postal_code/country'),
 ('Contact Email','text','canonical','contact_points','value_normalized',false,'default',
   'lowercase, validate format'),
 ('Phone','text','canonical','contact_points','value_normalized',false,'default',
   'convert to E.164 where possible'),
 ('Setup Date','date','canonical','vendors','onboarding_date',false,'default','date normalization'),
 ('Status','text','canonical','vendors','vendor_status',true,'warn',
   'crosswalk via mapping.value_crosswalks (crosswalk_type=vendor_status)'),
 ('Bank Account','text','canonical','vendor_bank_accounts','bank_account_id',false,'warn',
   'tokenized account identification via canonical.bank_accounts.account_token; never store raw'),
 ('Beneficial Owner','text','identity','entity_relationships','relationship_type=beneficial_owner',false,'warn',
   'create asserted ownership relationship with source evidence'),
 ('Created By','text','canonical','vendors','created_by',false,'default','resolve user/service identity')
) as f(source_field_name, source_data_type, canonical_schema, canonical_table, canonical_field, required_flag, null_handling, validation_rule)
where mv.package_name = 'Generic Vendor Master Export';

insert into mapping.field_mappings (
  mapping_version_id, source_system_id, source_object_name, source_field_name, source_data_type,
  canonical_schema, canonical_table, canonical_field, required_flag, null_handling, validation_rule
)
select mv.id, mv.source_system_id, 'ap_invoices', f.source_field_name, f.source_data_type,
       'canonical', f.canonical_table, f.canonical_field, f.required_flag, f.null_handling, f.validation_rule
from mapping.mapping_versions mv
cross join (values
 ('Invoice ID','text','invoices','invoice_number_raw',true,'fail','preserve original'),
 ('Invoice Number','text','invoices','invoice_number_normalized',true,'fail',
   'uppercase, trim, remove harmless punctuation; preserve credit-memo/revision suffixes'),
 ('Vendor Code','text','vendors','vendor_external_id',true,'fail','resolve to canonical.vendors'),
 ('Vendor Name','text','vendors','legal_name_raw',false,'warn','preserve raw, generate normalized name'),
 ('Invoice Date','date','invoices','invoice_date',true,'fail','ISO date conversion'),
 ('Due Date','date','invoices','due_date',false,'default','ISO date conversion'),
 ('Invoice Amount','numeric','invoices','amount_original',true,'fail','decimal conversion'),
 ('Currency','text','invoices','currency_original',true,'fail','ISO validation'),
 ('Purchase Order','text','invoices','po_number',false,'default',
   'resolved to canonical PO pending canonical.purchase_orders (Release 2)'),
 ('Status','text','invoices','invoice_status',true,'warn',
   'crosswalk via mapping.value_crosswalks (crosswalk_type=invoice_status)'),
 ('Payment Reference','text','payments','payment_reference',false,'warn',
   'creates invoice-payment relationship via canonical.payment_invoice_links')
) as f(source_field_name, source_data_type, canonical_table, canonical_field, required_flag, null_handling, validation_rule)
where mv.package_name = 'Generic AP Invoice Export';

-- ---------------------------------------------------------------------------
-- SEED: mapping.value_crosswalks (spec section 11 examples, verbatim).
-- ---------------------------------------------------------------------------
insert into mapping.value_crosswalks (source_system_id, crosswalk_type, source_code, canonical_code)
select ss.id, v.crosswalk_type, v.source_code, v.canonical_code
from (values
 ('generic_payment_register','payment_type','WIRE_OUT','wire_outbound'),
 ('generic_payment_register','payment_type','ACH CCD','ach_business_payment'),
 ('generic_vendor_master','vendor_status','A','active'),
 ('generic_vendor_master','vendor_status','I','inactive'),
 ('generic_employee_master','employee_status','TERM','terminated'),
 ('generic_gl','journal_method','M','manual'),
 ('generic_ap','invoice_status','P','paid'),
 ('generic_ap','invoice_status','V','voided'),
 ('generic_claims','claim_status','DEN','denied'),
 ('generic_bank_csv','currency','$','USD'),
 ('generic_vendor_master','country','United States','US'),
 ('generic_bank_csv','bank_debit_code','DR','debit'),
 ('generic_bank_csv','bank_credit_code','CR','credit')
) as v(source_system_code, crosswalk_type, source_code, canonical_code)
join mapping.source_systems ss on ss.system_code = v.source_system_code;

-- ---------------------------------------------------------------------------
-- SEED: mapping.normalization_rules (spec section 12, all 15 rule types).
-- Tokenization rules route to the EXISTING 0004 security.* functions.
-- ---------------------------------------------------------------------------
insert into mapping.normalization_rules (rule_type, rule_name, rule_logic_description, uses_security_function)
values
 ('name','Name Normalization','Uppercase, remove legal suffixes for matching only, preserve raw name.', null),
 ('address','Address Normalization','Standardize street types, unit identifiers, postal code, country.', null),
 ('phone','Phone Normalization','Convert to E.164 where country is known.', null),
 ('email','Email Normalization','Lowercase domain and address; preserve original.', null),
 ('invoice_number','Invoice Number Normalization','Trim spaces, standardize punctuation, retain meaningful suffixes.', null),
 ('account_tokenization','Account Tokenization','Hash/tokenize account number under tenant-specific key.',
   'security.token(tenant_id, raw_account_number)'),
 ('currency','Currency Normalization','ISO 4217 validation.', null),
 ('date','Date Normalization','Convert source date to ISO; preserve source timezone.', null),
 ('amount','Amount Normalization','Convert accounting negatives, parentheses, commas, and credit/debit fields.', null),
 ('status','Status Normalization','Crosswalk source statuses to canonical statuses via mapping.value_crosswalks.', null),
 ('description','Description Normalization','Remove repeated whitespace, preserve raw and normalized versions.', null),
 ('tax_id_tokenization','Tax-ID Tokenization','Encrypt/tokenize; never show raw identifier in general UI.',
   'security.vault_put(tenant_id, ''tax_id'', subject_ref, raw_tax_id) + security.token(tenant_id, raw_tax_id)'),
 ('entity_suffix','Entity Suffix Normalization','Normalize LLC, LLP, Inc., Ltd., Corp. for matching only.', null),
 ('device','Device Normalization','Standardize serial number, IMEI, MAC formatting.', null),
 ('serial_number','Serial-Number Normalization','Uppercase, remove spaces and harmless punctuation for comparison.', null);

-- ============================================================================
-- 18. MAPPING LOGIC FOR CRITICAL FRAUD RELATIONSHIPS -- worked examples
-- Registered as draft rules (rules.rule_definitions/rule_versions from 0008)
-- so the resulting analytics.rule_hits rows flow through the existing
-- investigation.alerts pipeline / golden-thread view (0011) like any other
-- detection rule.
-- ============================================================================
insert into rules.rule_definitions (rule_code, rule_name, domain, risk_category, description, business_rationale, rule_type, status)
values
 ('IDENTITY_VENDOR_EMPLOYEE_SHARED_ADDRESS','Vendor/Employee Shared Address Match','identity','related_party_fraud',
  'Flags vendor and employee entities that resolve to the same normalized address.',
  'A vendor sharing an employee''s address is a classic shell-vendor / ghost-vendor indicator.',
  'fuzzy','draft'),
 ('IDENTITY_VENDOR_EMPLOYEE_SHARED_BANK_ACCOUNT','Vendor/Employee Shared Bank Account Match','identity','related_party_fraud',
  'Flags vendor and employee entities whose payment/deposit accounts tokenize to the same value.',
  'The same bank account receiving both vendor payments and payroll is a high-confidence conflict-of-interest / fraud indicator.',
  'deterministic','draft'),
 ('AP_DUPLICATE_INVOICE','Duplicate Invoice Detection','AP','overpayment',
  'Groups invoices by vendor, normalized invoice number, amount, and date tolerance to find duplicate submissions.',
  'Duplicate invoice payment is one of the most common AP leakage/fraud patterns.',
  'deterministic','draft');

insert into rules.rule_versions (rule_id, version_number, logic_language, logic_sql, approval_status)
select rd.id, '0.1.0', 'plpgsql', v.logic_ref, 'draft'
from rules.rule_definitions rd
join (values
 ('IDENTITY_VENDOR_EMPLOYEE_SHARED_ADDRESS','select analytics.detect_vendor_employee_address_matches(p_matter_id)'),
 ('IDENTITY_VENDOR_EMPLOYEE_SHARED_BANK_ACCOUNT','select analytics.detect_vendor_employee_bank_matches(p_matter_id)'),
 ('AP_DUPLICATE_INVOICE','select analytics.detect_duplicate_invoices(p_matter_id, 5)')
) as v(rule_code, logic_ref) on v.rule_code = rd.rule_code;

-- ---------------------------------------------------------------------------
-- Vendor-to-Employee Address Match (spec section 18, worked example #1).
-- Writes identity.entity_relationships (type=shared_address) as a review
-- candidate, plus a mirroring analytics.rule_hits row so it surfaces in the
-- existing investigation.alerts queue. NOT a fraud finding.
-- ---------------------------------------------------------------------------
create or replace function analytics.detect_vendor_employee_address_matches(
  p_matter_id uuid,
  p_excluded_address_hashes text[] default array[]::text[]
) returns integer
language plpgsql
as $$
declare
  v_rule_version_id uuid;
  v_count integer := 0;
  v_rel record;
  v_new_rel_id uuid;
begin
  select rv.id into v_rule_version_id
    from rules.rule_versions rv
    join rules.rule_definitions rd on rd.id = rv.rule_id
   where rd.rule_code = 'IDENTITY_VENDOR_EMPLOYEE_SHARED_ADDRESS'
   order by rv.created_at desc limit 1;

  for v_rel in
    select distinct
      va.tenant_id,
      v.entity_id  as vendor_entity_id,
      e.entity_id  as employee_entity_id,
      va.address_hash,
      va.id        as vendor_address_id,
      ea.id        as employee_address_id
    from canonical.vendors v
    join canonical.addresses va on va.entity_id = v.entity_id and va.matter_id = p_matter_id
    join canonical.addresses ea on ea.address_hash = va.address_hash and ea.matter_id = p_matter_id
                                and ea.entity_id is distinct from va.entity_id
    join canonical.employees e  on e.entity_id = ea.entity_id and e.matter_id = p_matter_id
    where v.matter_id = p_matter_id
      and va.address_hash is not null
      and (cardinality(p_excluded_address_hashes) = 0 or va.address_hash <> all(p_excluded_address_hashes))
      and v.entity_id is not null
      and e.entity_id is not null
  loop
    insert into identity.entity_relationships (
      tenant_id, matter_id, from_entity_id, to_entity_id, relationship_type,
      relationship_status, confidence_score, match_algorithm_version, match_basis
    ) values (
      v_rel.tenant_id, p_matter_id, v_rel.vendor_entity_id, v_rel.employee_entity_id,
      'shared_address', 'review_candidate', 60.00, 'address_hash_v1',
      jsonb_build_object('vendor_address_id', v_rel.vendor_address_id,
                          'employee_address_id', v_rel.employee_address_id,
                          'address_hash', v_rel.address_hash)
    )
    on conflict (from_entity_id, to_entity_id, relationship_type) do nothing
    returning id into v_new_rel_id;

    if v_new_rel_id is not null then
      v_count := v_count + 1;
      insert into analytics.rule_hits (
        tenant_id, matter_id, rule_version_id, primary_object_type, primary_object_id,
        primary_business_key, severity, risk_score, confidence_score, reason_codes,
        explanation, evidence_references, review_status
      ) values (
        v_rel.tenant_id, p_matter_id, v_rule_version_id, 'entity_relationship', v_new_rel_id,
        v_rel.vendor_entity_id::text || '~' || v_rel.employee_entity_id::text,
        'medium', 60.00, 60.00,
        jsonb_build_object('rule','IDENTITY_VENDOR_EMPLOYEE_SHARED_ADDRESS'),
        'Vendor entity and employee entity resolve to the same normalized address hash; '
        'review candidate for related-party / shell-vendor risk (not a fraud finding).',
        jsonb_build_object('vendor_address_id', v_rel.vendor_address_id,
                            'employee_address_id', v_rel.employee_address_id),
        'new'
      );
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function analytics.detect_vendor_employee_address_matches(uuid, text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Vendor-to-Employee Bank Account Match (spec section 18, worked example #2).
-- Tokens only (canonical.bank_accounts.account_token, via 0004's
-- security.token()) -- the raw account number is never compared. Creates a
-- HIGH-PRIORITY relationship candidate per the spec's explicit step 5, and
-- links vendor payments + employee payroll transactions into the hit.
-- ---------------------------------------------------------------------------
create or replace function analytics.detect_vendor_employee_bank_matches(
  p_matter_id uuid
) returns integer
language plpgsql
as $$
declare
  v_rule_version_id uuid;
  v_count integer := 0;
  v_rel record;
  v_new_rel_id uuid;
  v_vendor_payment_count integer;
  v_vendor_payment_total numeric(20,4);
  v_employee_payroll_count integer;
  v_employee_payroll_total numeric(20,4);
begin
  select rv.id into v_rule_version_id
    from rules.rule_versions rv
    join rules.rule_definitions rd on rd.id = rv.rule_id
   where rd.rule_code = 'IDENTITY_VENDOR_EMPLOYEE_SHARED_BANK_ACCOUNT'
   order by rv.created_at desc limit 1;

  for v_rel in
    select distinct
      vba.tenant_id,
      v.id         as vendor_id,
      v.entity_id  as vendor_entity_id,
      e.id         as employee_id,
      e.entity_id  as employee_entity_id,
      ba.id        as bank_account_id,
      ba.account_token
    from canonical.vendor_bank_accounts vba
    join canonical.bank_accounts ba          on ba.id = vba.bank_account_id and ba.matter_id = p_matter_id
    join canonical.vendors v                 on v.id  = vba.vendor_id and v.matter_id = p_matter_id
    join canonical.employee_bank_accounts eba on eba.bank_account_id = ba.id and eba.matter_id = p_matter_id
    join canonical.employees e               on e.id  = eba.employee_id and e.matter_id = p_matter_id
    where vba.matter_id = p_matter_id
      and ba.account_token is not null
      and v.entity_id is not null
      and e.entity_id is not null
      and (vba.effective_to is null or vba.effective_to >= current_date)
  loop
    insert into identity.entity_relationships (
      tenant_id, matter_id, from_entity_id, to_entity_id, relationship_type,
      relationship_status, confidence_score, match_algorithm_version, match_basis
    ) values (
      v_rel.tenant_id, p_matter_id, v_rel.vendor_entity_id, v_rel.employee_entity_id,
      'shared_bank_account', 'high_priority_review', 100.00, 'account_token_v1',
      jsonb_build_object('bank_account_id', v_rel.bank_account_id, 'account_token', v_rel.account_token)
    )
    on conflict (from_entity_id, to_entity_id, relationship_type) do nothing
    returning id into v_new_rel_id;

    if v_new_rel_id is not null then
      v_count := v_count + 1;

      select count(*), coalesce(sum(p.amount_original), 0)
        into v_vendor_payment_count, v_vendor_payment_total
        from canonical.payments p
       where p.matter_id = p_matter_id and p.beneficiary_entity_id = v_rel.vendor_entity_id;

      select count(*), coalesce(sum(t.amount_original), 0)
        into v_employee_payroll_count, v_employee_payroll_total
        from canonical.transactions t
       where t.matter_id = p_matter_id
         and t.account_id = v_rel.bank_account_id
         and t.transaction_type = 'payroll';

      insert into analytics.rule_hits (
        tenant_id, matter_id, rule_version_id, primary_object_type, primary_object_id,
        primary_business_key, severity, risk_score, confidence_score, reason_codes,
        explanation, evidence_references, feature_snapshot, review_status
      ) values (
        v_rel.tenant_id, p_matter_id, v_rule_version_id, 'entity_relationship', v_new_rel_id,
        v_rel.vendor_entity_id::text || '~' || v_rel.employee_entity_id::text,
        'critical', 100.00, 100.00,
        jsonb_build_object('rule','IDENTITY_VENDOR_EMPLOYEE_SHARED_BANK_ACCOUNT'),
        'Vendor bank account and employee payroll/deposit account tokenize to the same value; '
        'high-confidence conflict-of-interest indicator. Route to fraud-rule engine for review.',
        jsonb_build_object(
          'bank_account_id', v_rel.bank_account_id,
          'vendor_id', v_rel.vendor_id, 'vendor_payment_count', v_vendor_payment_count,
          'vendor_payment_total', v_vendor_payment_total,
          'employee_id', v_rel.employee_id, 'employee_payroll_count', v_employee_payroll_count,
          'employee_payroll_total', v_employee_payroll_total
        ),
        jsonb_build_object('confidence_weight_basis','exact_bank_account_token=100'),
        'new'
      );
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function analytics.detect_vendor_employee_bank_matches(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Duplicate Invoice (spec section 18, worked example #4). Groups by vendor +
-- normalized invoice number + amount + currency, clustered to a date
-- tolerance window around the earliest invoice in the group; excludes
-- voided/credited/reversed invoices; produces ONE grouped rule_hit per
-- duplicate cluster (never repetitive line-level alerts).
-- ---------------------------------------------------------------------------
create or replace function analytics.detect_duplicate_invoices(
  p_matter_id uuid,
  p_date_tolerance_days integer default 5
) returns integer
language plpgsql
as $$
declare
  v_rule_version_id uuid;
  v_count integer := 0;
  v_grp record;
begin
  select rv.id into v_rule_version_id
    from rules.rule_versions rv
    join rules.rule_definitions rd on rd.id = rv.rule_id
   where rd.rule_code = 'AP_DUPLICATE_INVOICE'
   order by rv.created_at desc limit 1;

  for v_grp in
    with base as (
      select i.*,
             min(i.invoice_date) over (
               partition by i.vendor_id, i.invoice_number_normalized, i.amount_original, i.currency_original
             ) as grp_min_date
      from canonical.invoices i
      where i.matter_id = p_matter_id
        and coalesce(i.invoice_status, '') not in ('voided','credit_memo','reversed')
        and i.invoice_number_normalized is not null
        and i.vendor_id is not null
        and i.amount_original is not null
    ),
    clustered as (
      select * from base
      where invoice_date is null or grp_min_date is null
         or abs(invoice_date - grp_min_date) <= p_date_tolerance_days
    ),
    grouped as (
      select
        tenant_id, vendor_id, invoice_number_normalized, amount_original, currency_original,
        count(*) as dup_count,
        array_agg(id) as invoice_ids,
        min(invoice_date) as first_invoice_date,
        max(invoice_date) as last_invoice_date,
        sum(case when exists (
              select 1 from canonical.payment_invoice_links pil where pil.invoice_id = clustered.id
            ) then 1 else 0 end) as paid_count
      from clustered
      group by tenant_id, vendor_id, invoice_number_normalized, amount_original, currency_original
      having count(*) > 1
    )
    select * from grouped
  loop
    v_count := v_count + 1;
    insert into analytics.rule_hits (
      tenant_id, matter_id, rule_run_id, rule_version_id, primary_object_type, primary_object_id,
      primary_business_key, event_date, amount_base, currency_base, severity, risk_score,
      confidence_score, reason_codes, explanation, evidence_references, feature_snapshot, review_status
    ) values (
      v_grp.tenant_id, p_matter_id, null, v_rule_version_id, 'invoice_duplicate_group', v_grp.invoice_ids[1],
      v_grp.vendor_id::text || '~' || v_grp.invoice_number_normalized,
      v_grp.last_invoice_date,
      case when v_grp.paid_count > 1 then (v_grp.paid_count - 1) * v_grp.amount_original else 0 end,
      v_grp.currency_original,
      case when v_grp.paid_count > 1 then 'high' else 'medium' end,
      case when v_grp.paid_count > 1 then 90.00 else 60.00 end,
      80.00,
      jsonb_build_object('rule','AP_DUPLICATE_INVOICE','duplicate_count', v_grp.dup_count, 'paid_count', v_grp.paid_count),
      format('Vendor %s has %s invoices with normalized invoice number %s and amount %s %s within %s day(s) of each other; %s appear paid.',
             v_grp.vendor_id, v_grp.dup_count, v_grp.invoice_number_normalized, v_grp.amount_original,
             v_grp.currency_original, p_date_tolerance_days, v_grp.paid_count),
      jsonb_build_object('invoice_ids', to_jsonb(v_grp.invoice_ids)),
      jsonb_build_object('dup_count', v_grp.dup_count, 'paid_count', v_grp.paid_count,
                          'first_invoice_date', v_grp.first_invoice_date, 'last_invoice_date', v_grp.last_invoice_date),
      'new'
    );
  end loop;
  return v_count;
end;
$$;
grant execute on function analytics.detect_duplicate_invoices(uuid, integer) to authenticated, service_role;

-- ============================================================================
-- Done. Sanity summary (informational only; no side effects):
--   staging   : 18 raw landing tables, all immutable-payload + matter-RLS.
--   mapping   : 9 global registry tables incl. the Draft->...->Retired
--               mapping-version lifecycle, seeded with the 25 minimum
--               initial mapping packages (status='draft').
--   identity  : 7 entity-resolution tables incl. pg_trgm-backed alias/name
--               matching and the shared-address / shared-bank-account
--               relationship candidates.
--   quality   : 9 validation/reconciliation/exception tables; the mapping
--               exception workflow is a hard check constraint, not prose.
--   analytics : 3 worked fraud-relationship detector functions, registered
--               as draft rules.rule_definitions/rule_versions so their hits
--               flow through the existing investigation.alerts pipeline.
-- ============================================================================
