-- ============================================================================
-- Forens_iQ — Forensic / Litigation / Treasury Investigations Platform
-- Migration 0001: extensions, schemas, grants
-- Target: Supabase (PostgreSQL 15+). Paste into Supabase Studio SQL editor
--         or save under supabase/migrations/ and run `supabase db push`.
--
-- Design note (naming fix): the module prefix for Fraud eXamination artifacts
-- is `fe_` (NOT `fx_`). `fx_` is reserved exclusively for foreign-exchange
-- columns (fx_rate, fx_rate_source). This removes the FX collision flagged in
-- the concept review.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Extensions (Supabase keeps these in the `extensions` schema by convention)
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto      with schema extensions;  -- digest(), hmac(), gen_random_uuid(), pgp_sym_*
create extension if not exists pg_trgm       with schema extensions;  -- fuzzy name / near-duplicate matching
create extension if not exists citext        with schema extensions;  -- case-insensitive email / codes
-- Supabase Vault (encrypted secret store) — used for crypto-shredding & the
-- whistleblower identity vault in migration 0004. Usually pre-installed.
create extension if not exists supabase_vault with schema vault;

-- ---------------------------------------------------------------------------
-- Application schemas (mirror the layered architecture from the spec)
-- ---------------------------------------------------------------------------
create schema if not exists app;            -- helper functions, RLS context, triggers
create schema if not exists core;           -- tenants, matters, authority, access
create schema if not exists security;       -- key registry, tokenization, vault wrappers
create schema if not exists evidence;       -- evidence vault + chain of custody
create schema if not exists canonical;      -- normalized financial + entity model
create schema if not exists identity;       -- entity resolution, relationships
create schema if not exists rules;          -- detection rule registry
create schema if not exists analytics;      -- rule hits / derived signals
create schema if not exists investigation;  -- allegations -> findings, alerts, WB vault
create schema if not exists reporting;      -- reports, sections, claim links
create schema if not exists audit;          -- immutable audit plane + anchors

-- ---------------------------------------------------------------------------
-- Grants. Supabase ships three PostgREST roles:
--   anon           - unauthenticated (NO access to this system at all)
--   authenticated  - a logged-in user (access is further gated by RLS)
--   service_role   - backend/ETL worker (BYPASSRLS; use only in trusted jobs)
-- `anon` is deliberately granted nothing here.
-- ---------------------------------------------------------------------------
grant usage on schema app, core, evidence, canonical, identity,
                       rules, analytics, investigation, reporting, audit
  to authenticated, service_role;

-- security schema: only service_role and SECURITY DEFINER helpers touch it.
grant usage on schema security to service_role;

-- Default privileges: table-level SELECT/DML is granted per-migration so we
-- never accidentally expose a new table. RLS still governs row visibility.
alter default privileges in schema core, evidence, canonical, identity,
      rules, analytics, investigation, reporting, audit
  grant select, insert, update, delete on tables to authenticated, service_role;

comment on schema audit is
  'Immutable append-only audit plane. No UPDATE/DELETE permitted (enforced by trigger). Hash-chained and externally anchored.';
