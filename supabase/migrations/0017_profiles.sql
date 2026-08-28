-- ============================================================================
-- 0017_profiles.sql
-- No table anywhere in 0001-0016 resolves a bare `uuid` actor column
-- (matter_access.user_id, findings.reviewed_by, etc.) to a display name —
-- there is no core.users/public.profiles table. This adds the minimal one,
-- auto-provisioned on signup, so the frontend can show "who" instead of a
-- raw uuid and pick a user when granting matter_access.
-- ============================================================================
begin;

create table core.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  tenant_id    uuid references core.tenants(id),
  display_name text,
  email        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table core.profiles enable row level security;
alter table core.profiles force row level security;

-- self read/update; any authenticated user can look up display names for
-- actors referenced on rows they can already see (matter_access, reviewed_by,
-- created_by, ...) since those uuids carry no confidentiality signal on their
-- own — matching the audit_events precedent of tenant-wide-readable metadata.
create policy profiles_read on core.profiles
  for select to authenticated using (true);

create policy profiles_self_update on core.profiles
  for update to authenticated using (id = app.current_user_id());

grant select, update on core.profiles to authenticated;
grant select, insert, update, delete on core.profiles to service_role;

create or replace function core.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp, core
as $$
begin
  insert into core.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function core.handle_new_user();

commit;
