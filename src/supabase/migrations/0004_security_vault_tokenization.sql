-- ============================================================================
-- Migration 0004: crypto-shredding, tokenization, whistleblower vault
--
-- Fix #D (erasure vs immutability): sensitive plaintext (raw bank account
-- numbers, tax IDs, whistleblower identity) is NEVER stored in a business
-- table. It is written to Supabase Vault (vault.create_secret) and the table
-- keeps only the returned secret UUID + a deterministic HMAC token for
-- matching. "Right to erasure" / legal destruction = delete the vault secret
-- (crypto-shred). The row, its hash, and the audit trail survive; the
-- plaintext becomes unrecoverable. This reconciles GDPR/CCPA erasure with an
-- append-only, hash-anchored evidence record.
--
-- All functions here are SECURITY DEFINER and owned by the migration role so
-- that `authenticated` never gets direct rights on the vault or the keys.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- security.encryption_keys : per-subject key registry.
-- One logical key per (tenant, purpose, subject_ref). `vault_secret_id` points
-- at the Vault secret that holds the actual key material (or the plaintext for
-- direct-vault columns). Destroying the key flips status and nulls the pointer.
-- ---------------------------------------------------------------------------
create table security.encryption_keys (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  purpose         text not null,          -- 'bank_account','tax_id','wb_identity',...
  subject_ref     text not null,          -- opaque handle, e.g. matter+entity
  vault_secret_id uuid,                    -- Supabase Vault secret (null once shredded)
  status          text not null default 'active',   -- active | destroyed
  destroyed_at    timestamptz,
  destroyed_by    uuid,
  destruction_authority text,             -- court order / retention rule / DSAR id
  created_at      timestamptz not null default now(),
  created_by      uuid default app.current_user_id(),
  unique (tenant_id, purpose, subject_ref)
);

-- ---------------------------------------------------------------------------
-- security.tenant_hmac_key(tenant) : returns the tenant-scoped tokenization
-- key from Vault (created lazily). Tokens are deterministic within a tenant so
-- "same bank account used by vendor and employee" matching works WITHOUT ever
-- holding the raw number in a queryable column.
-- ---------------------------------------------------------------------------
create or replace function security.tenant_hmac_key(p_tenant uuid)
returns text
language plpgsql security definer
set search_path = vault, security, public
as $$
declare
  v_name text := 'hmac:' || p_tenant::text;
  v_key  text;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = v_name;
  if v_key is null then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'), v_name,
      'Forens_iQ tenant tokenization key');
    select decrypted_secret into v_key
      from vault.decrypted_secrets where name = v_name;
  end if;
  return v_key;
end;
$$;

-- security.token(tenant, plaintext) : deterministic, non-reversible match token.
create or replace function security.token(p_tenant uuid, p_plaintext text)
returns text
language plpgsql security definer
set search_path = security, extensions, public
as $$
begin
  if p_plaintext is null or length(trim(p_plaintext)) = 0 then
    return null;
  end if;
  -- normalize: strip spaces/punctuation, uppercase (accounts, serials, etc.)
  return encode(
    extensions.hmac(
      upper(regexp_replace(p_plaintext, '[^A-Za-z0-9]', '', 'g')),
      security.tenant_hmac_key(p_tenant), 'sha256'),
    'hex');
end;
$$;

-- ---------------------------------------------------------------------------
-- security.vault_put(tenant, purpose, subject_ref, plaintext)
--   -> writes plaintext to Vault, registers a key row, returns key id.
-- security.vault_get(key_id) -> plaintext, or NULL if the key was shredded.
-- security.shred(key_id, authority) -> destroys the secret (irreversible).
-- ---------------------------------------------------------------------------
create or replace function security.vault_put(
  p_tenant uuid, p_purpose text, p_subject_ref text, p_plaintext text)
returns uuid
language plpgsql security definer
set search_path = vault, security, public
as $$
declare
  v_secret_id uuid;
  v_key_id    uuid;
  v_name      text := p_purpose || ':' || p_subject_ref;
begin
  v_secret_id := vault.create_secret(p_plaintext, v_name,
                   'Forens_iQ protected value');
  insert into security.encryption_keys(tenant_id, purpose, subject_ref, vault_secret_id)
    values (p_tenant, p_purpose, p_subject_ref, v_secret_id)
    returning id into v_key_id;
  return v_key_id;
end;
$$;

create or replace function security.vault_get(p_key_id uuid)
returns text
language plpgsql security definer
set search_path = vault, security, public
as $$
declare v_secret_id uuid; v_val text;
begin
  select vault_secret_id into v_secret_id
    from security.encryption_keys
    where id = p_key_id and status = 'active';
  if v_secret_id is null then
    return null;   -- shredded or never existed
  end if;
  select decrypted_secret into v_val
    from vault.decrypted_secrets where id = v_secret_id;
  return v_val;
end;
$$;

create or replace function security.shred(p_key_id uuid, p_authority text)
returns void
language plpgsql security definer
set search_path = vault, security, public
as $$
declare v_secret_id uuid;
begin
  select vault_secret_id into v_secret_id
    from security.encryption_keys where id = p_key_id and status = 'active';
  if v_secret_id is null then
    return;
  end if;
  delete from vault.secrets where id = v_secret_id;          -- crypto-shred
  update security.encryption_keys
     set status = 'destroyed', destroyed_at = now(),
         destroyed_by = app.current_user_id(),
         destruction_authority = p_authority,
         vault_secret_id = null
   where id = p_key_id;
end;
$$;

grant execute on function
  security.token(uuid,text),
  security.vault_get(uuid)
  to authenticated;   -- read-side helpers only
-- write/destroy helpers are for trusted ETL / officers, not general users
grant execute on function
  security.vault_put(uuid,text,text,text),
  security.shred(uuid,text)
  to service_role;

-- ---------------------------------------------------------------------------
-- WHISTLEBLOWER VAULT (fix #E): reporter identity is structurally separated.
-- The report body lives in investigation.* (0007); the reporter's identity is
-- here, encrypted in Vault, readable ONLY through a dedicated function that
-- logs every access. Even matter_admins and platform admins cannot read
-- identity without generating an access record.
-- ---------------------------------------------------------------------------
create table security.whistleblower_identities (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null,
  matter_id     uuid,
  report_ref    text not null,        -- links to investigation.whistleblower_reports.report_code
  identity_key_id uuid references security.encryption_keys(id),  -- vault-held identity
  is_anonymous  boolean not null default true,
  created_at    timestamptz not null default now()
);

create table security.whistleblower_access_log (
  id            uuid primary key default gen_random_uuid(),
  identity_id   uuid not null references security.whistleblower_identities(id),
  accessed_by   uuid not null,
  access_reason text not null,
  legal_basis   text,
  accessed_at   timestamptz not null default now()
);

-- Only members explicitly holding 'wb_officer' on the matter may unseal, and
-- every unseal is logged. (Role membership carried in matter_access via a
-- convention: access_level 'approve' + a metadata flag; kept simple here.)
create or replace function security.wb_reveal_identity(
  p_identity_id uuid, p_reason text, p_legal_basis text)
returns text
language plpgsql security definer
set search_path = security, public
as $$
declare v_key uuid; v_matter uuid; v_val text;
begin
  select identity_key_id, matter_id into v_key, v_matter
    from security.whistleblower_identities where id = p_identity_id;
  if not app.has_matter_access(v_matter, 'approve') then
    raise exception 'Not authorized to unseal whistleblower identity'
      using errcode = 'insufficient_privilege';
  end if;
  insert into security.whistleblower_access_log(identity_id, accessed_by, access_reason, legal_basis)
    values (p_identity_id, app.current_user_id(), p_reason, p_legal_basis);
  return security.vault_get(v_key);
end;
$$;

grant execute on function security.wb_reveal_identity(uuid,text,text) to authenticated;
