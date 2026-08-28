-- ============================================================================
-- Migration 0006: canonical financial + entity core
-- Money rule (spec): DECIMAL only, never float. Original + base currency both
-- preserved with the fx_rate/source/date lineage. `fx_` = foreign exchange ONLY.
-- Idempotency (fix #I): canonical rows are unique by
-- (matter_id, source_dataset_version_id, source_record_id) so replaying an
-- import can never double-book a transaction, invoice, or payment.
-- ============================================================================

-- Reusable money columns are repeated inline (PG has no column templates).

-- ---------------------------------------------------------------------------
-- canonical.entities  (master node: person | org | account | device | asset)
-- ---------------------------------------------------------------------------
create table canonical.entities (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  entity_type    text not null,        -- person, organization, account, device, asset, address...
  display_name   text,
  name_normalized text,                 -- lower/suffix-stripped for matching
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id text,
  source_evidence_id uuid references evidence.evidence_items(id),
  confidence_score numeric(5,2),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  row_version    integer not null default 1
);
create index on canonical.entities(matter_id);
create index on canonical.entities using gin (name_normalized extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- canonical.addresses / contact_points  (shared-attribute fraud analysis)
-- ---------------------------------------------------------------------------
create table canonical.addresses (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  entity_id      uuid references canonical.entities(id),
  street         text, city text, region text, postal_code text, country text,
  address_hash   text,                 -- normalized hash for match rules
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on canonical.addresses(matter_id, address_hash);

create table canonical.contact_points (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  entity_id      uuid references canonical.entities(id),
  kind           text not null,        -- email, phone, device_id, ip, wallet
  value_normalized extensions.citext,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on canonical.contact_points(matter_id, kind, value_normalized);

-- ---------------------------------------------------------------------------
-- canonical.bank_accounts  (tokenized; raw number crypto-shreddable)
-- ---------------------------------------------------------------------------
create table canonical.bank_accounts (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  owner_entity_id    uuid references canonical.entities(id),
  account_token      text,             -- security.token(tenant, raw#)  <- matching key
  account_vault_key_id uuid references security.encryption_keys(id),  -- raw#, shreddable
  account_class      text,             -- operating, personal, trust, escrow, restricted
  institution_name   text,
  branch_identifier  text,
  is_restricted      boolean not null default false,
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  source_evidence_id uuid references evidence.evidence_items(id),
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1
);
create index on canonical.bank_accounts(matter_id, account_token);

-- ---------------------------------------------------------------------------
-- canonical.vendors + vendor_bank_accounts + employees + employee_bank_accounts
-- ---------------------------------------------------------------------------
create table canonical.vendors (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  vendor_external_id text,
  legal_name_raw     text,
  legal_name_normalized text,
  tax_id_token       text,
  vendor_status      text,             -- active, inactive, blocked, terminated
  onboarding_date    date,
  entity_id          uuid references canonical.entities(id),
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, source_dataset_version_id, source_record_id)
);
create index on canonical.vendors(matter_id);

create table canonical.vendor_bank_accounts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  vendor_id      uuid not null references canonical.vendors(id),
  bank_account_id uuid not null references canonical.bank_accounts(id),
  effective_from date, effective_to date,
  change_event_at timestamptz,          -- for "bank change before payment" rule
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on canonical.vendor_bank_accounts(matter_id, vendor_id);

create table canonical.employees (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  employee_external_id text,
  entity_id          uuid references canonical.entities(id),
  status             text,             -- active, leave, terminated, contractor
  hire_date          date,
  termination_date   date,
  department         text,
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, source_dataset_version_id, source_record_id)
);
create index on canonical.employees(matter_id);

create table canonical.employee_bank_accounts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  employee_id    uuid not null references canonical.employees(id),
  bank_account_id uuid not null references canonical.bank_accounts(id),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on canonical.employee_bank_accounts(matter_id, employee_id);

-- ---------------------------------------------------------------------------
-- canonical.transactions + transaction_legs  (money-flow graph substrate)
-- ---------------------------------------------------------------------------
create table canonical.transactions (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  transaction_type   text,             -- wire, ach, check, card, cash, transfer, journal, payroll, claim, fee
  transaction_date   date,
  posting_date       date,
  effective_date     date,
  amount_original    numeric(20,4) not null,
  currency_original  char(3) not null,
  amount_base        numeric(20,4),
  currency_base      char(3),
  fx_rate            numeric(20,10),
  fx_rate_date       date,
  fx_rate_source     text,
  debit_credit_indicator text,          -- debit | credit
  account_id         uuid references canonical.bank_accounts(id),
  counterparty_entity_id uuid references canonical.entities(id),
  reference_number   text,
  description_raw    text,
  description_normalized text,
  reversal_of_transaction_id uuid references canonical.transactions(id),
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  source_evidence_id uuid references evidence.evidence_items(id),
  confidence_score   numeric(5,2),
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, source_dataset_version_id, source_record_id)   -- idempotent
);
create index on canonical.transactions(matter_id, transaction_date);
create index on canonical.transactions(matter_id, account_id);

create table canonical.transaction_legs (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  transaction_id uuid not null references canonical.transactions(id),
  leg_sequence   int not null,
  from_entity_id uuid references canonical.entities(id),
  to_entity_id   uuid references canonical.entities(id),
  from_account_id uuid references canonical.bank_accounts(id),
  to_account_id   uuid references canonical.bank_accounts(id),
  amount         numeric(20,4) not null,
  currency       char(3) not null,
  role           text,                  -- source | destination | accounting
  source_evidence_id uuid references evidence.evidence_items(id),
  confidence_score numeric(5,2),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (transaction_id, leg_sequence)
);
create index on canonical.transaction_legs(matter_id, transaction_id);

-- ---------------------------------------------------------------------------
-- canonical.invoices + payments + link
-- ---------------------------------------------------------------------------
create table canonical.invoices (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  vendor_id          uuid references canonical.vendors(id),
  invoice_number_raw text,
  invoice_number_normalized text,
  invoice_date       date,
  due_date           date,
  amount_original    numeric(20,4),
  currency_original  char(3),
  invoice_status     text,             -- posted, paid, voided, credit_memo
  po_number          text,
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  source_evidence_id uuid references evidence.evidence_items(id),
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, source_dataset_version_id, source_record_id)
);
create index on canonical.invoices(matter_id, vendor_id, invoice_number_normalized);

create table canonical.payments (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  matter_id          uuid not null references core.matters(id),
  payment_reference  text,
  payment_date       date,
  amount_original    numeric(20,4),
  currency_original  char(3),
  from_account_id    uuid references canonical.bank_accounts(id),
  beneficiary_entity_id uuid references canonical.entities(id),
  beneficiary_account_id uuid references canonical.bank_accounts(id),
  initiator_user_ref text,
  approver_user_ref  text,
  releaser_user_ref  text,
  payment_status     text,
  transaction_id     uuid references canonical.transactions(id),
  source_dataset_version_id uuid references evidence.dataset_versions(id),
  source_record_id   text,
  source_evidence_id uuid references evidence.evidence_items(id),
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (matter_id, source_dataset_version_id, source_record_id)
);
create index on canonical.payments(matter_id, payment_reference);

create table canonical.payment_invoice_links (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  matter_id      uuid not null references core.matters(id),
  payment_id     uuid not null references canonical.payments(id),
  invoice_id     uuid not null references canonical.invoices(id),
  applied_amount numeric(20,4),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (payment_id, invoice_id)
);

-- ---------------------------------------------------------------------------
-- Stamp triggers + RLS for all canonical tables
-- ---------------------------------------------------------------------------
do $$
declare t text; tables text[] := array[
  'canonical.entities','canonical.addresses','canonical.contact_points',
  'canonical.bank_accounts','canonical.vendors','canonical.vendor_bank_accounts',
  'canonical.employees','canonical.employee_bank_accounts','canonical.transactions',
  'canonical.transaction_legs','canonical.invoices','canonical.payments',
  'canonical.payment_invoice_links'];
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
end $$;
