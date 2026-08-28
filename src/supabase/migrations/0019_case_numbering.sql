-- ============================================================================
-- Migration 0019: self-enumerating case/item numbers
--
-- matter_number, human_evidence_no, allegation_no, and whistleblower
-- report_code are all `text not null` with a unique constraint but no
-- default — until now the app had to invent them client-side, which
-- collides under concurrent writers and puts formatting in the UI instead
-- of the schema. This migration makes them self-numbering at the DB layer:
-- a BEFORE INSERT trigger fills the column in when the caller leaves it
-- NULL/blank; an explicit value passed by the caller is still honored
-- (needed for migrating legacy case numbers), so this is additive, not a
-- behavior break.
--
-- Formats (matching the convention already in 0005's comment,
-- "MAT-001-EV-000245"):
--   matters.matter_number                 MAT-{tenant-scoped, %03d}
--   evidence_items.human_evidence_no       {matter_number}-EV-{matter-scoped, %06d}
--   allegations.allegation_no              ALG-{matter-scoped, %03d}
--   whistleblower_reports.report_code      WB-{tenant-scoped, %05d}
--
-- (allegation_no deliberately has no matter_number prefix, matching the
-- convention already in use by the seeded demo row — "ALG-001" not
-- "MAT-001-ALG-001" — since it's already scoped by matter_id as a column.)
--
-- Counter storage: a single app.sequences(scope_key, value) table, bumped
-- atomically via INSERT ... ON CONFLICT DO UPDATE ... RETURNING (the
-- ON CONFLICT row lock serializes concurrent callers on the same scope_key
-- without a separate advisory lock). scope_key embeds the tenant/matter id
-- so numbering is independent per tenant or per matter as appropriate.
-- Not exposed to `authenticated` directly — only through the SECURITY
-- DEFINER app.next_seq() function, same pattern as app.has_matter_access.
-- ============================================================================

create table app.sequences (
  scope_key  text primary key,
  value      bigint not null default 0
);

create or replace function app.next_seq(p_scope text)
returns bigint
language sql
security definer
set search_path = pg_catalog, pg_temp, app
as $$
  insert into app.sequences (scope_key, value)
  values (p_scope, 1)
  on conflict (scope_key) do update set value = app.sequences.value + 1
  returning value;
$$;

comment on function app.next_seq(text) is
  'Atomic per-scope counter. Callers should namespace p_scope, e.g.
   ''matter_number:'' || tenant_id, so unrelated numbering sequences
   never collide.';

-- ---------------------------------------------------------------------------
-- core.matters.matter_number  ->  MAT-{tenant seq, %03d}
-- ---------------------------------------------------------------------------
create or replace function core.tg_matter_number()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp, core, app
as $$
begin
  if new.matter_number is null or btrim(new.matter_number) = '' then
    new.matter_number := 'MAT-' ||
      lpad(app.next_seq('matter_number:' || new.tenant_id)::text, 3, '0');
  end if;
  return new;
end;
$$;

create trigger tg_matter_number before insert on core.matters
  for each row execute function core.tg_matter_number();

-- ---------------------------------------------------------------------------
-- evidence.evidence_items.human_evidence_no  ->  {matter_number}-EV-{matter seq, %06d}
-- ---------------------------------------------------------------------------
create or replace function evidence.tg_human_evidence_no()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp, evidence, core, app
as $$
declare v_matter_number text;
begin
  if new.human_evidence_no is null or btrim(new.human_evidence_no) = '' then
    select matter_number into v_matter_number
      from core.matters where id = new.matter_id;
    if v_matter_number is null then
      raise exception 'evidence_items.matter_id % does not resolve to a matter', new.matter_id
        using errcode = 'foreign_key_violation';
    end if;
    new.human_evidence_no := v_matter_number || '-EV-' ||
      lpad(app.next_seq('evidence_no:' || new.matter_id)::text, 6, '0');
  end if;
  return new;
end;
$$;

create trigger tg_human_evidence_no before insert on evidence.evidence_items
  for each row execute function evidence.tg_human_evidence_no();

-- ---------------------------------------------------------------------------
-- investigation.allegations.allegation_no  ->  {matter_number}-ALG-{matter seq, %03d}
-- ---------------------------------------------------------------------------
create or replace function investigation.tg_allegation_no()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp, investigation, app
as $$
begin
  if new.allegation_no is null or btrim(new.allegation_no) = '' then
    new.allegation_no := 'ALG-' ||
      lpad(app.next_seq('allegation_no:' || new.matter_id)::text, 3, '0');
  end if;
  return new;
end;
$$;

create trigger tg_allegation_no before insert on investigation.allegations
  for each row execute function investigation.tg_allegation_no();

-- ---------------------------------------------------------------------------
-- investigation.whistleblower_reports.report_code  ->  WB-{tenant seq, %05d}
-- Tenant-scoped (not matter-scoped): matter_id is nullable on this table —
-- a whistleblower report can arrive before it is triaged onto a matter.
-- ---------------------------------------------------------------------------
create or replace function investigation.tg_whistleblower_report_code()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp, investigation, app
as $$
begin
  if new.report_code is null or btrim(new.report_code) = '' then
    new.report_code := 'WB-' ||
      lpad(app.next_seq('wb_report_code:' || new.tenant_id)::text, 5, '0');
  end if;
  return new;
end;
$$;

create trigger tg_whistleblower_report_code before insert on investigation.whistleblower_reports
  for each row execute function investigation.tg_whistleblower_report_code();

-- ---------------------------------------------------------------------------
-- RLS: app.sequences is internal bookkeeping, touched only through the
-- SECURITY DEFINER function above — no grants to `authenticated` at all.
-- ---------------------------------------------------------------------------
alter table app.sequences enable row level security;
alter table app.sequences force row level security;
revoke all on app.sequences from authenticated, anon;

-- ---------------------------------------------------------------------------
-- Backfill: seed counters past whatever was already manually assigned
-- (the seeded demo matter/evidence/allegation rows), so the first
-- trigger-generated number in each scope never collides with one a human
-- already typed in. Parses the trailing numeric run off the existing value;
-- rows that don't match the expected pattern are ignored (counter stays at
-- 0 for that scope and trigger-generated numbers start fresh at 1).
-- ---------------------------------------------------------------------------
insert into app.sequences (scope_key, value)
select 'matter_number:' || tenant_id, max((regexp_match(matter_number, '(\d+)$'))[1]::bigint)
from core.matters
where matter_number ~ '\d+$'
group by tenant_id
on conflict (scope_key) do update set value = greatest(app.sequences.value, excluded.value);

insert into app.sequences (scope_key, value)
select 'evidence_no:' || matter_id, max((regexp_match(human_evidence_no, '(\d+)$'))[1]::bigint)
from evidence.evidence_items
where human_evidence_no ~ '\d+$'
group by matter_id
on conflict (scope_key) do update set value = greatest(app.sequences.value, excluded.value);

insert into app.sequences (scope_key, value)
select 'allegation_no:' || matter_id, max((regexp_match(allegation_no, '(\d+)$'))[1]::bigint)
from investigation.allegations
where allegation_no ~ '\d+$'
group by matter_id
on conflict (scope_key) do update set value = greatest(app.sequences.value, excluded.value);

insert into app.sequences (scope_key, value)
select 'wb_report_code:' || tenant_id, max((regexp_match(report_code, '(\d+)$'))[1]::bigint)
from investigation.whistleblower_reports
where report_code ~ '\d+$'
group by tenant_id
on conflict (scope_key) do update set value = greatest(app.sequences.value, excluded.value);
