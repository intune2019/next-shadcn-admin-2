-- ============================================================================
-- Migration 0005: evidence vault + tamper-evident chain of custody + anchoring
-- ============================================================================

-- ---------------------------------------------------------------------------
-- evidence.data_sources / dataset_versions  (source-preserving ingestion)
-- Idempotency (fix #I): a dataset version is unique by its raw file hash, so
-- re-uploading the identical extract cannot create a second version.
-- ---------------------------------------------------------------------------
create table evidence.data_sources (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  source_name    text not null,
  source_system  text,                 -- SAP, QuickBooks, Wells Fargo, ADP...
  system_owner   text,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on evidence.data_sources(matter_id);

create table evidence.dataset_versions (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  matter_id         uuid not null references core.matters(id),
  data_source_id    uuid not null references evidence.data_sources(id),
  raw_file_sha256   bytea not null,
  record_count      bigint,
  control_total     numeric(20,4),
  period_start      date,
  period_end        date,
  readiness_status  text not null default 'not_ready', -- not_ready|failed|warning|approved|superseded|archived
  superseded_by     uuid references evidence.dataset_versions(id),
  record_status     core.record_status not null default 'active',
  created_at        timestamptz not null default now(),
  created_by        uuid,
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  row_version       integer not null default 1,
  unique (matter_id, data_source_id, raw_file_sha256)   -- idempotent ingest
);
create index on evidence.dataset_versions(matter_id);

-- ---------------------------------------------------------------------------
-- evidence.evidence_items + files + hashes
-- ---------------------------------------------------------------------------
create table evidence.evidence_items (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  human_evidence_no  text not null,     -- MAT-001-EV-000245
  evidence_type      text not null,     -- document,email,image,device,bank_record,dataset...
  title              text,
  source_type        text,
  acquired_at        timestamptz,
  source_custodian   text,
  original_format    text,
  storage_uri        text,              -- object-store pointer, never a public URL
  status             text not null default 'preserved',
  integrity_status   text not null default 'unknown',
  legal_hold_status  text not null default 'held',
  confidentiality    core.confidentiality_level not null default 'client_confidential',
  privilege_status   text,
  admission_status   text default 'proposed',
  parent_evidence_id uuid references evidence.evidence_items(id),
  -- physical-item identifiers (nullable for digital)
  serial_number      text,
  imei               text,
  vin                text,
  asset_tag          text,
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid,
  updated_at         timestamptz not null default now(),
  updated_by         uuid,
  row_version        integer not null default 1,
  unique (matter_id, human_evidence_no)
);
create index on evidence.evidence_items(matter_id);

create table evidence.evidence_files (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  evidence_id    uuid not null references evidence.evidence_items(id),
  file_name      text,
  mime_type      text,
  byte_size      bigint,
  storage_uri    text,
  version_label  text default 'original',
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on evidence.evidence_files(evidence_id);

create table evidence.evidence_hashes (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  evidence_file_id uuid not null references evidence.evidence_files(id),
  algorithm      text not null default 'sha256',
  hash_value     bytea not null,
  verified_at    timestamptz not null default now(),
  verification_result text not null default 'verified',  -- verified|mismatch|incomplete
  created_at     timestamptz not null default now(),
  created_by     uuid
);
create index on evidence.evidence_hashes(evidence_file_id);

-- now that evidence exists, wire the authority -> evidence FK from 0003
alter table core.authority_instruments
  add constraint authority_source_evidence_fk
  foreign key (source_evidence_id) references evidence.evidence_items(id);

-- ---------------------------------------------------------------------------
-- evidence.chain_of_custody_events  — APPEND-ONLY + HASH-CHAINED (fix #A)
-- One hash chain per evidence item (scope_key = evidence_id). Any attempt to
-- UPDATE/DELETE is rejected; corrections are new events.
-- ---------------------------------------------------------------------------
create table evidence.chain_of_custody_events (
  id             uuid primary key default gen_random_uuid(),
  seq            bigint generated always as identity,
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  evidence_id    uuid not null references evidence.evidence_items(id),
  scope_key      text not null,         -- set to evidence_id::text
  event_type     text not null,         -- collected,received,imaged,hashed,moved,viewed,exported,produced,returned,destroyed
  from_party     text,
  to_party       text,
  occurred_at    timestamptz not null default now(),
  authorized_by  uuid,
  reason_code    text,
  location_before text,
  location_after  text,
  hash_before    bytea,
  hash_after     bytea,
  attestation    text,
  -- integrity linkage (populated by triggers)
  payload_hash   bytea,
  prev_hash      bytea,
  chain_hash     bytea,
  created_at     timestamptz not null default now(),
  created_by     uuid default app.current_user_id()
);
create index on evidence.chain_of_custody_events(evidence_id, seq);

-- per-row payload hash (business content only), then chain linkage
create or replace function evidence.tg_coc_payload()
returns trigger language plpgsql as $$
begin
  new.scope_key := new.evidence_id::text;
  new.payload_hash := extensions.digest(
    coalesce(new.evidence_id::text,'') || '|' ||
    coalesce(new.event_type,'')        || '|' ||
    coalesce(new.from_party,'')        || '|' ||
    coalesce(new.to_party,'')          || '|' ||
    coalesce(new.occurred_at::text,'') || '|' ||
    coalesce(new.authorized_by::text,'')|| '|' ||
    coalesce(new.reason_code,'')       || '|' ||
    coalesce(encode(new.hash_after,'hex'),''),
    'sha256');
  return new;
end $$;

create trigger tg_10_payload before insert on evidence.chain_of_custody_events
  for each row execute function evidence.tg_coc_payload();
create trigger tg_20_chain   before insert on evidence.chain_of_custody_events
  for each row execute function app.tg_hash_chain();
create trigger tg_90_denymut before update or delete on evidence.chain_of_custody_events
  for each row execute function app.tg_deny_mutation();

-- ---------------------------------------------------------------------------
-- EXTERNAL ANCHORING (fix #A): periodically fold custody + audit chain heads
-- into a Merkle-style root and push it to an independent timestamp authority
-- (RFC-3161 TSA) or public ledger. The token proves the root existed at time
-- T and cannot be back-dated even by a platform DBA.
-- ---------------------------------------------------------------------------
create table evidence.anchor_runs (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid,
  scope          text not null,           -- 'custody' | 'audit'
  seq_from       bigint not null,
  seq_to         bigint not null,
  merkle_root    bytea not null,
  external_authority text,                 -- e.g. 'freetsa.org', 'sigstore', 'opentimestamps'
  external_token bytea,                    -- TSA response / OTS proof (opaque)
  anchored_at    timestamptz,
  status         text not null default 'pending',  -- pending|anchored|failed
  created_at     timestamptz not null default now(),
  created_by     uuid default app.current_user_id()
);

-- Compute a fold-root over a custody seq range (simple linear Merkle fold;
-- swap for a true binary Merkle tree in production).
create or replace function evidence.compute_custody_root(p_from bigint, p_to bigint)
returns bytea language sql stable as $$
  select extensions.digest(
    coalesce(string_agg(encode(chain_hash,'hex'), '' order by seq), ''),
    'sha256')
  from evidence.chain_of_custody_events
  where seq between p_from and p_to
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'evidence.data_sources','evidence.dataset_versions','evidence.evidence_items',
    'evidence.evidence_files','evidence.evidence_hashes',
    'evidence.chain_of_custody_events'
  ] loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_matter_access(matter_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
  -- UPDATE allowed only on non-append-only evidence tables
  foreach t in array array[
    'evidence.data_sources','evidence.dataset_versions','evidence.evidence_items',
    'evidence.evidence_files'
  ] loop
    execute format($p$create policy upd on %s for update to authenticated
        using (app.has_matter_access(matter_id, 'contribute'))
        with check (app.has_matter_access(matter_id, 'contribute'));$p$, t);
  end loop;
end $$;

-- stamp triggers on the mutable evidence tables
do $$
declare t text;
begin
  foreach t in array array[
    'evidence.data_sources','evidence.dataset_versions','evidence.evidence_items',
    'evidence.evidence_files'
  ] loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
  end loop;
end $$;
