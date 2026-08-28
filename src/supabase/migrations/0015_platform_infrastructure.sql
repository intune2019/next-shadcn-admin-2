-- ============================================================================
-- Migration 0015: platform infrastructure — queue/event bus, WORM evidence
-- storage, full-text search, and scheduled external anchoring.
--
-- Closes the gap between the Back-End Build Specification's "Recommended
-- database split" (§2) / "APIs and Service Boundaries" (§22) and what a
-- self-hosted Supabase stack provides out of the box:
--   • Queue/event bus            -> pgmq (already bundled in this Postgres image)
--   • Secrets/KMS                -> already covered (Supabase Vault, migration 0004)
--   • Object storage w/ WORM     -> storage.objects RLS deny-mutation policy
--   • Search (doc/metadata)      -> tsvector + GIN on evidence/investigation text
--   • Scheduled anchoring jobs   -> pg_cron enqueues onto pgmq; pg_net available
--     for the eventual outbound TSA POST (no external TSA endpoint/credentials
--     are configured yet — anchor_runs rows land as 'pending_external' until an
--     operator supplies one; nothing here fakes a successful external anchor).
-- Graph store and analytical warehouse are explicitly optional-at-launch per
-- the spec itself and are intentionally not stood up here.
-- ============================================================================

-- pgmq and pg_cron are not relocatable — each must install into its own
-- native schema (pgmq -> schema `pgmq`; pg_cron -> schema `pg_catalog`, since
-- the postgres image preloads it via shared_preload_libraries). Only pg_net
-- honors "with schema".
create extension if not exists pgmq;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- 1. Queue/event bus
-- One queue per async job family named in the spec's §2 "Queue/event bus"
-- line: ingestion, hashing, OCR, extraction, analytics, alerts, report
-- compilation, notification processing — plus the anchoring jobs already
-- modeled by evidence.anchor_runs / audit.anchor_runs.
-- ---------------------------------------------------------------------------
do $$
declare q text;
begin
  foreach q in array array['ingestion','hashing','ocr','analytics','alerts',
                            'report_compilation','notifications','anchoring'] loop
    if not exists (select 1 from pgmq.list_queues() where queue_name = q) then
      perform pgmq.create(q);
    end if;
  end loop;
end $$;

-- service_role only: queue tables carry raw job payloads across tenants.
do $$
declare q text;
begin
  foreach q in array array['ingestion','hashing','ocr','analytics','alerts',
                            'report_compilation','notifications','anchoring'] loop
    execute format('revoke all on pgmq.q_%I from authenticated, anon', q);
    execute format('grant all on pgmq.q_%I to service_role', q);
  end loop;
end $$;

-- app.enqueue(): thin, audited wrapper so business code never touches pgmq
-- directly and every enqueue carries tenant/matter context (API rule from
-- spec §22: "every write request must include tenant and matter context").
create or replace function app.enqueue(
  p_queue text, p_tenant uuid, p_payload jsonb, p_matter uuid default null
)
returns bigint
language plpgsql security definer
set search_path = pgmq, public
as $$
declare v_msg_id bigint;
begin
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
grant execute on function app.enqueue(text, uuid, jsonb, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. WORM / object-lock evidence storage
-- The self-hosted stack runs storage-api in 'file' backend mode, which has no
-- native S3 Object Lock. We enforce the same guarantee one layer down: Storage
-- metadata lives in Postgres (storage.objects), and Postgres RLS can reject
-- UPDATE/DELETE unconditionally for anything in the 'evidence' bucket — the
-- same deny-mutation pattern already used for chain_of_custody_events and
-- audit_events (app.tg_deny_mutation). A corrected file becomes a NEW object
-- version (evidence.evidence_files.version_label), never an overwrite.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('evidence', 'evidence', false, 52428800)
on conflict (id) do nothing;

drop trigger if exists tg_worm_deny_mutation on storage.objects;
create trigger tg_worm_deny_mutation
  before update or delete on storage.objects
  for each row
  when (old.bucket_id = 'evidence')
  execute function app.tg_deny_mutation();

-- ---------------------------------------------------------------------------
-- 3. Search (§22 "Search and OCR service")
-- Native Postgres full-text search over evidence and investigation free-text
-- fields. Real OCR still requires an external OCR API/credentials this
-- deployment does not have; evidence.evidence_files.storage_uri + the `ocr`
-- pgmq queue above is where that worker would plug in — once OCR text lands
-- (e.g. in a future evidence.evidence_ocr_text table), index it the same way.
-- ---------------------------------------------------------------------------
alter table evidence.evidence_items
  add column if not exists search_tsv tsvector
  generated always as (
    setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(evidence_type,'')), 'B') ||
    setweight(to_tsvector('english', coalesce(source_custodian,'')), 'C') ||
    setweight(to_tsvector('english', coalesce(human_evidence_no,'')), 'B')
  ) stored;
create index if not exists evidence_items_search_idx on evidence.evidence_items using gin (search_tsv);

alter table investigation.allegations
  add column if not exists search_tsv tsvector
  generated always as (to_tsvector('english', coalesce(reported_conduct,''))) stored;
create index if not exists allegations_search_idx on investigation.allegations using gin (search_tsv);

alter table investigation.leads
  add column if not exists search_tsv tsvector
  generated always as (to_tsvector('english', coalesce(statement,''))) stored;
create index if not exists leads_search_idx on investigation.leads using gin (search_tsv);

alter table investigation.findings
  add column if not exists search_tsv tsvector
  generated always as (
    setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(methodology,'')), 'B')
  ) stored;
create index if not exists findings_search_idx on investigation.findings using gin (search_tsv);

-- ---------------------------------------------------------------------------
-- 4. Scheduled external anchoring (ADR decision A: "run the anchoring job
-- from an isolated worker, not from the DB" — pg_cron is the least-bad
-- approximation available in a single self-hosted stack; it only computes the
-- root and enqueues the external POST, it never marks a run 'anchored' itself)
-- ---------------------------------------------------------------------------
create or replace function app.run_scheduled_anchoring()
returns void
language plpgsql security definer
set search_path = evidence, audit, extensions, public
as $$
declare
  r record;
  v_root bytea;
  v_run_id uuid;
begin
  -- evidence custody chain: anchor any tenant/evidence scope with unanchored events
  for r in
    select scope_key, min(seq) as seq_from, max(seq) as seq_to
    from evidence.chain_of_custody_events e
    where not exists (
      select 1 from evidence.anchor_runs a
      where a.scope = 'custody' and a.seq_to >= e.seq
    )
    group by scope_key
  loop
    v_root := evidence.compute_custody_root(r.seq_from, r.seq_to);
    insert into evidence.anchor_runs(scope, seq_from, seq_to, merkle_root, status)
    values ('custody', r.seq_from, r.seq_to, v_root, 'pending_external')
    returning id into v_run_id;
    perform app.enqueue('anchoring', null::uuid,
      jsonb_build_object('anchor_run_id', v_run_id, 'scope', 'custody',
                          'table', 'evidence.anchor_runs'));
  end loop;

  -- audit plane: anchor per tenant
  for r in
    select tenant_id, min(seq) as seq_from, max(seq) as seq_to
    from audit.audit_events e
    where not exists (
      select 1 from audit.anchor_runs a
      where a.tenant_id = e.tenant_id and a.seq_to >= e.seq
    )
    group by tenant_id
  loop
    v_root := audit.compute_root(r.tenant_id, r.seq_from, r.seq_to);
    insert into audit.anchor_runs(tenant_id, seq_from, seq_to, merkle_root, status)
    values (r.tenant_id, r.seq_from, r.seq_to, v_root, 'pending_external')
    returning id into v_run_id;
    perform app.enqueue('anchoring', r.tenant_id,
      jsonb_build_object('anchor_run_id', v_run_id, 'scope', 'audit',
                          'table', 'audit.anchor_runs'));
  end loop;
end;
$$;

-- cron.schedule upserts on (jobname, username), so this is safe to re-run.
select cron.schedule(
  'forensiq-anchor-runs', '*/15 * * * *', $$select app.run_scheduled_anchoring()$$
);

-- ---------------------------------------------------------------------------
-- 5. Alert -> notification bridge (§22 "Notification service")
-- Every new investigation.alerts row enqueues a notification job; the actual
-- delivery channel (email/SMS/webhook) is a worker concern, not a DB concern.
-- ---------------------------------------------------------------------------
create or replace function investigation.tg_alert_notify()
returns trigger language plpgsql as $$
begin
  perform app.enqueue('notifications', new.tenant_id,
    jsonb_build_object(
      'kind', 'alert_created',
      'alert_id', new.id,
      'alert_title', new.alert_title,
      'severity', new.aggregate_severity
    ),
    new.matter_id);
  return new;
end $$;

drop trigger if exists tg_notify on investigation.alerts;
create trigger tg_notify after insert on investigation.alerts
  for each row execute function investigation.tg_alert_notify();
