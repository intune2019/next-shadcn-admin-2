-- ============================================================================
-- Forens_iQ — Migration 0035: Accounting module (the FIRM's own books)
--
-- NOT to be confused with canonical.chart_of_accounts / journal_entries
-- (0030), which model a CLIENT's books inside a matter for forensic
-- examination. This schema is In.Tune & Associates' own operating GL:
-- billing clients for engagements, paying vendors, reconciling the firm's
-- bank accounts, and closing its own books.
--
-- Posting model (borrowed concept from ERPNext's GL Entry, not its schema):
-- every subsidiary document (sales invoice, purchase invoice, payment,
-- manual journal entry) posts into ONE append-only ledger — accounting.gl_
-- entries. Nothing updates or deletes a GL entry; corrections post a
-- reversing entry that references the original. Trial balance, GL, and P&L/
-- balance sheet are all just queries over that one table.
-- ============================================================================

begin;

create schema if not exists accounting;
grant usage on schema accounting to authenticated, service_role;
alter default privileges in schema accounting
  grant select, insert, update, delete on tables to authenticated, service_role;

-- ============================================================================
-- SETUP
-- ============================================================================

create table accounting.companies (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references core.tenants(id),
  company_name   text not null,
  default_currency char(3) not null default 'USD',
  fiscal_year_start_month int not null default 1 check (fiscal_year_start_month between 1 and 12),
  is_default     boolean not null default true,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1,
  unique (tenant_id, company_name)
);

create table accounting.fiscal_years (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  company_id     uuid not null references accounting.companies(id),
  year_name      text not null,          -- 'FY2026'
  start_date     date not null,
  end_date       date not null,
  is_closed      boolean not null default false,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  unique (company_id, year_name),
  check (end_date > start_date)
);

create table accounting.chart_of_accounts (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  company_id         uuid not null references accounting.companies(id),
  account_number     text,
  account_name       text not null,
  root_type          text not null check (root_type in ('asset','liability','equity','income','expense')),
  account_type       text,               -- Bank, Receivable, Payable, Fixed Asset, Cost of Goods Sold...
  parent_account_id  uuid references accounting.chart_of_accounts(id),
  is_group           boolean not null default false,   -- true = header/summary account, no direct postings
  currency           char(3) not null default 'USD',
  is_active          boolean not null default true,
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (company_id, account_name)
);
create index on accounting.chart_of_accounts(company_id, root_type);
create index on accounting.chart_of_accounts(parent_account_id);

create table accounting.cost_centers (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  company_id          uuid not null references accounting.companies(id),
  cost_center_name    text not null,
  parent_cost_center_id uuid references accounting.cost_centers(id),
  is_group            boolean not null default false,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  created_by          uuid,
  unique (company_id, cost_center_name)
);

create table accounting.payment_terms (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  term_name      text not null,
  due_days       int not null default 30,
  description    text,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  unique (tenant_id, term_name)
);

create table accounting.modes_of_payment (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  mode_name      text not null,          -- Cash, ACH, Wire, Check, Credit Card, Trust Transfer
  default_account_id uuid references accounting.chart_of_accounts(id),
  created_at     timestamptz not null default now(),
  created_by     uuid,
  unique (tenant_id, mode_name)
);

-- ============================================================================
-- PARTIES — bridges to core.client_organizations (CRM already flows into
-- this via crm.win_deal) and to vendors the firm itself pays.
-- ============================================================================

create table accounting.customers (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  company_id     uuid not null references accounting.companies(id),
  customer_name  text not null,
  client_org_id  uuid references core.client_organizations(id),  -- link back to the matter-owning org
  default_currency char(3) not null default 'USD',
  payment_terms_id uuid references accounting.payment_terms(id),
  is_active      boolean not null default true,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on accounting.customers(company_id);
create index on accounting.customers(client_org_id);

create table accounting.suppliers (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  company_id     uuid not null references accounting.companies(id),
  supplier_name  text not null,
  supplier_type  text,                   -- expert_witness, court_reporter, e-discovery_vendor, software, general
  default_currency char(3) not null default 'USD',
  payment_terms_id uuid references accounting.payment_terms(id),
  is_active      boolean not null default true,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
create index on accounting.suppliers(company_id);

-- ============================================================================
-- GL — the single append-only ledger everything else posts into.
-- ============================================================================

create table accounting.gl_entries (
  id                 uuid primary key default gen_random_uuid(),
  seq                bigint generated always as identity,
  tenant_id          uuid not null,
  company_id         uuid not null references accounting.companies(id),
  posting_date       date not null,
  account_id         uuid not null references accounting.chart_of_accounts(id),
  debit_amount       numeric(20,4) not null default 0,
  credit_amount      numeric(20,4) not null default 0,
  currency           char(3) not null default 'USD',
  party_type         text check (party_type in ('customer','supplier')),
  party_id           uuid,
  cost_center_id     uuid references accounting.cost_centers(id),
  voucher_type       text not null check (voucher_type in
                        ('sales_invoice','purchase_invoice','payment_entry',
                         'journal_entry','credit_note','debit_note','reversal')),
  voucher_id         uuid not null,
  reversal_of_gl_entry_id uuid references accounting.gl_entries(id),
  remarks            text,
  created_at         timestamptz not null default now(),
  created_by         uuid,
  check (not (debit_amount <> 0 and credit_amount <> 0))
);
create index on accounting.gl_entries(company_id, posting_date);
create index on accounting.gl_entries(account_id, posting_date);
create index on accounting.gl_entries(voucher_type, voucher_id);
create index on accounting.gl_entries(party_type, party_id);

create trigger tg_90_denymut before update or delete on accounting.gl_entries
  for each row execute function app.tg_deny_mutation();

-- Internal helper: post a balanced set of GL lines atomically. Never called
-- directly by the frontend — only by the posting functions below, which
-- validate the source document first.
create or replace function accounting.post_gl_lines(p_lines jsonb)
returns void
language plpgsql
set search_path = pg_catalog, pg_temp, accounting
as $$
declare
  v_total_debit numeric := 0; v_total_credit numeric := 0; v_line jsonb;
begin
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_total_debit := v_total_debit + coalesce((v_line->>'debit_amount')::numeric, 0);
    v_total_credit := v_total_credit + coalesce((v_line->>'credit_amount')::numeric, 0);
  end loop;
  if round(v_total_debit, 4) <> round(v_total_credit, 4) then
    raise exception 'GL posting out of balance: debits % <> credits %', v_total_debit, v_total_credit
      using errcode = '23514';
  end if;

  insert into accounting.gl_entries(
    tenant_id, company_id, posting_date, account_id, debit_amount, credit_amount,
    currency, party_type, party_id, cost_center_id, voucher_type, voucher_id, remarks, created_by)
  select
    (l->>'tenant_id')::uuid, (l->>'company_id')::uuid, (l->>'posting_date')::date,
    (l->>'account_id')::uuid, coalesce((l->>'debit_amount')::numeric,0), coalesce((l->>'credit_amount')::numeric,0),
    coalesce(l->>'currency','USD'), l->>'party_type', nullif(l->>'party_id','')::uuid,
    nullif(l->>'cost_center_id','')::uuid, l->>'voucher_type', (l->>'voucher_id')::uuid,
    l->>'remarks', app.current_user_id()
  from jsonb_array_elements(p_lines) l;
end $$;

-- ============================================================================
-- AR — Sales Invoices
-- ============================================================================

create table accounting.sales_invoices (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  company_id       uuid not null references accounting.companies(id),
  customer_id      uuid not null references accounting.customers(id),
  matter_id        uuid references core.matters(id),   -- bill against an engagement
  invoice_number   text not null,
  invoice_date     date not null default current_date,
  due_date         date,
  currency         char(3) not null default 'USD',
  subtotal         numeric(20,4) not null default 0,
  tax_total        numeric(20,4) not null default 0,
  grand_total      numeric(20,4) not null default 0,
  outstanding_amount numeric(20,4) not null default 0,
  status           text not null default 'draft' check (status in
                      ('draft','submitted','partially_paid','paid','overdue','cancelled')),
  payment_terms_id uuid references accounting.payment_terms(id),
  receivable_account_id uuid references accounting.chart_of_accounts(id),
  remarks          text,
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1,
  unique (company_id, invoice_number)
);
create index on accounting.sales_invoices(company_id, status);
create index on accounting.sales_invoices(matter_id);
create index on accounting.sales_invoices(customer_id);

create table accounting.sales_invoice_lines (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  invoice_id        uuid not null references accounting.sales_invoices(id),
  item_description  text not null,
  quantity          numeric(12,2) not null default 1,
  rate              numeric(20,4) not null default 0,
  amount            numeric(20,4) not null,
  income_account_id uuid not null references accounting.chart_of_accounts(id),
  cost_center_id    uuid references accounting.cost_centers(id),
  time_entry_id     uuid references pm.time_entries(id),  -- billed-hours bridge to PM
  sort_order        int not null default 0
);
create index on accounting.sales_invoice_lines(invoice_id);
create index on accounting.sales_invoice_lines(time_entry_id);

-- Submits a DRAFT invoice: posts Dr Accounts Receivable / Cr Income per line.
create or replace function accounting.submit_sales_invoice(p_invoice_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, accounting, app
as $$
declare
  v_inv accounting.sales_invoices%rowtype;
  v_lines jsonb;
begin
  select * into v_inv from accounting.sales_invoices where id = p_invoice_id;
  if not found or v_inv.status <> 'draft' then
    raise exception 'Invoice not found or not in draft status' using errcode = '22023';
  end if;
  if v_inv.receivable_account_id is null then
    raise exception 'Invoice has no receivable account set' using errcode = '22023';
  end if;

  select jsonb_agg(jsonb_build_object(
    'tenant_id', v_inv.tenant_id, 'company_id', v_inv.company_id, 'posting_date', v_inv.invoice_date,
    'account_id', sil.income_account_id, 'debit_amount', 0, 'credit_amount', sil.amount,
    'currency', v_inv.currency, 'cost_center_id', sil.cost_center_id,
    'voucher_type', 'sales_invoice', 'voucher_id', v_inv.id, 'remarks', v_inv.invoice_number
  ))
  into v_lines
  from accounting.sales_invoice_lines sil where sil.invoice_id = p_invoice_id;

  v_lines := v_lines || jsonb_build_array(jsonb_build_object(
    'tenant_id', v_inv.tenant_id, 'company_id', v_inv.company_id, 'posting_date', v_inv.invoice_date,
    'account_id', v_inv.receivable_account_id, 'debit_amount', v_inv.grand_total, 'credit_amount', 0,
    'currency', v_inv.currency, 'party_type', 'customer', 'party_id', v_inv.customer_id,
    'voucher_type', 'sales_invoice', 'voucher_id', v_inv.id, 'remarks', v_inv.invoice_number
  ));

  perform accounting.post_gl_lines(v_lines);

  update accounting.sales_invoices
     set status = 'submitted', outstanding_amount = grand_total, due_date = coalesce(due_date, invoice_date)
   where id = p_invoice_id;
end $$;
revoke all on function accounting.submit_sales_invoice(uuid) from public, anon;
grant execute on function accounting.submit_sales_invoice(uuid) to authenticated;

-- Bills unbilled billable time straight from PM — the CRM/PM/Accounting
-- loop closer. Creates a draft invoice with one line per time entry.
create or replace function accounting.create_invoice_from_time_entries(
  p_company_id uuid, p_customer_id uuid, p_matter_id uuid,
  p_income_account_id uuid, p_time_entry_ids uuid[], p_invoice_number text
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, pg_temp, accounting, pm, app
as $$
declare v_invoice_id uuid; v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from accounting.companies where id = p_company_id;

  insert into accounting.sales_invoices(tenant_id, company_id, customer_id, matter_id, invoice_number, created_by)
  values (v_tenant_id, p_company_id, p_customer_id, p_matter_id, p_invoice_number, app.current_user_id())
  returning id into v_invoice_id;

  -- Rate/amount are left at 0 here deliberately: pricing (rate card, matter
  -- billing rate, discounts) is a business decision the app layer applies
  -- before the invoice is submitted — this function's job is only to pull
  -- the correct unbilled time entries onto a draft invoice, once.
  insert into accounting.sales_invoice_lines(
    tenant_id, invoice_id, item_description, quantity, rate, amount, income_account_id, time_entry_id)
  select v_tenant_id, v_invoice_id,
         coalesce(te.note, 'Professional services'), te.minutes / 60.0, 0, 0,
         p_income_account_id, te.id
    from pm.time_entries te
   where te.id = any(p_time_entry_ids) and te.billable = true;

  return v_invoice_id;
end $$;
revoke all on function accounting.create_invoice_from_time_entries(uuid,uuid,uuid,uuid,uuid[],text) from public, anon;
grant execute on function accounting.create_invoice_from_time_entries(uuid,uuid,uuid,uuid,uuid[],text) to authenticated;

create table accounting.credit_notes (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  company_id         uuid not null references accounting.companies(id),
  customer_id        uuid not null references accounting.customers(id),
  original_invoice_id uuid references accounting.sales_invoices(id),
  credit_note_number text not null,
  credit_date        date not null default current_date,
  amount             numeric(20,4) not null,
  reason             text,
  status             text not null default 'draft' check (status in ('draft','submitted','cancelled')),
  record_status      core.record_status not null default 'active',
  created_at         timestamptz not null default now(),
  created_by         uuid, updated_at timestamptz not null default now(),
  updated_by         uuid, row_version integer not null default 1,
  unique (company_id, credit_note_number)
);

-- ============================================================================
-- AP — Purchase Invoices
-- ============================================================================

create table accounting.purchase_invoices (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  company_id       uuid not null references accounting.companies(id),
  supplier_id      uuid not null references accounting.suppliers(id),
  matter_id        uuid references core.matters(id),   -- e.g. an expert-witness bill charged to a matter
  bill_number      text not null,
  bill_date        date not null default current_date,
  due_date         date,
  currency         char(3) not null default 'USD',
  subtotal         numeric(20,4) not null default 0,
  tax_total        numeric(20,4) not null default 0,
  grand_total      numeric(20,4) not null default 0,
  outstanding_amount numeric(20,4) not null default 0,
  status           text not null default 'draft' check (status in
                      ('draft','submitted','partially_paid','paid','overdue','cancelled')),
  payment_terms_id uuid references accounting.payment_terms(id),
  payable_account_id uuid references accounting.chart_of_accounts(id),
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1,
  unique (company_id, supplier_id, bill_number)
);
create index on accounting.purchase_invoices(company_id, status);
create index on accounting.purchase_invoices(matter_id);

create table accounting.purchase_invoice_lines (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  invoice_id        uuid not null references accounting.purchase_invoices(id),
  item_description  text not null,
  quantity          numeric(12,2) not null default 1,
  rate              numeric(20,4) not null default 0,
  amount            numeric(20,4) not null,
  expense_account_id uuid not null references accounting.chart_of_accounts(id),
  cost_center_id    uuid references accounting.cost_centers(id),
  sort_order        int not null default 0
);
create index on accounting.purchase_invoice_lines(invoice_id);

create or replace function accounting.submit_purchase_invoice(p_invoice_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, accounting, app
as $$
declare v_inv accounting.purchase_invoices%rowtype; v_lines jsonb;
begin
  select * into v_inv from accounting.purchase_invoices where id = p_invoice_id;
  if not found or v_inv.status <> 'draft' then
    raise exception 'Invoice not found or not in draft status' using errcode = '22023';
  end if;
  if v_inv.payable_account_id is null then
    raise exception 'Invoice has no payable account set' using errcode = '22023';
  end if;

  select jsonb_agg(jsonb_build_object(
    'tenant_id', v_inv.tenant_id, 'company_id', v_inv.company_id, 'posting_date', v_inv.bill_date,
    'account_id', pil.expense_account_id, 'debit_amount', pil.amount, 'credit_amount', 0,
    'currency', v_inv.currency, 'cost_center_id', pil.cost_center_id,
    'voucher_type', 'purchase_invoice', 'voucher_id', v_inv.id, 'remarks', v_inv.bill_number
  ))
  into v_lines
  from accounting.purchase_invoice_lines pil where pil.invoice_id = p_invoice_id;

  v_lines := v_lines || jsonb_build_array(jsonb_build_object(
    'tenant_id', v_inv.tenant_id, 'company_id', v_inv.company_id, 'posting_date', v_inv.bill_date,
    'account_id', v_inv.payable_account_id, 'debit_amount', 0, 'credit_amount', v_inv.grand_total,
    'currency', v_inv.currency, 'party_type', 'supplier', 'party_id', v_inv.supplier_id,
    'voucher_type', 'purchase_invoice', 'voucher_id', v_inv.id, 'remarks', v_inv.bill_number
  ));

  perform accounting.post_gl_lines(v_lines);
  update accounting.purchase_invoices
     set status = 'submitted', outstanding_amount = grand_total, due_date = coalesce(due_date, bill_date)
   where id = p_invoice_id;
end $$;
revoke all on function accounting.submit_purchase_invoice(uuid) from public, anon;
grant execute on function accounting.submit_purchase_invoice(uuid) to authenticated;

-- ============================================================================
-- PAYMENTS
-- ============================================================================

create table accounting.payment_entries (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  company_id       uuid not null references accounting.companies(id),
  payment_type     text not null check (payment_type in ('receive','pay','internal_transfer')),
  party_type       text check (party_type in ('customer','supplier')),
  party_id         uuid,
  mode_of_payment_id uuid references accounting.modes_of_payment(id),
  bank_account_id  uuid,   -- FK added below once accounting.bank_accounts exists
  paid_amount      numeric(20,4) not null,
  currency         char(3) not null default 'USD',
  exchange_rate    numeric(18,6) not null default 1,
  reference_number text,
  reference_date   date,
  posting_date     date not null default current_date,
  status           text not null default 'draft' check (status in ('draft','submitted','cancelled')),
  record_status    core.record_status not null default 'active',
  created_at       timestamptz not null default now(),
  created_by       uuid, updated_at timestamptz not null default now(),
  updated_by       uuid, row_version integer not null default 1
);
create index on accounting.payment_entries(company_id, status);

create table accounting.payment_entry_references (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  payment_entry_id  uuid not null references accounting.payment_entries(id),
  reference_type    text not null check (reference_type in ('sales_invoice','purchase_invoice')),
  reference_id      uuid not null,
  allocated_amount  numeric(20,4) not null
);
create index on accounting.payment_entry_references(payment_entry_id);
create index on accounting.payment_entry_references(reference_type, reference_id);

create or replace function accounting.submit_payment_entry(
  p_payment_id uuid, p_receivable_or_payable_account_id uuid, p_cash_or_bank_account_id uuid
)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, accounting, app
as $$
declare v_pmt accounting.payment_entries%rowtype; v_ref record;
begin
  select * into v_pmt from accounting.payment_entries where id = p_payment_id;
  if not found or v_pmt.status <> 'draft' then
    raise exception 'Payment not found or not in draft status' using errcode = '22023';
  end if;

  if v_pmt.payment_type = 'receive' then
    perform accounting.post_gl_lines(jsonb_build_array(
      jsonb_build_object('tenant_id', v_pmt.tenant_id, 'company_id', v_pmt.company_id,
        'posting_date', v_pmt.posting_date, 'account_id', p_cash_or_bank_account_id,
        'debit_amount', v_pmt.paid_amount, 'credit_amount', 0, 'currency', v_pmt.currency,
        'voucher_type', 'payment_entry', 'voucher_id', v_pmt.id, 'remarks', v_pmt.reference_number),
      jsonb_build_object('tenant_id', v_pmt.tenant_id, 'company_id', v_pmt.company_id,
        'posting_date', v_pmt.posting_date, 'account_id', p_receivable_or_payable_account_id,
        'debit_amount', 0, 'credit_amount', v_pmt.paid_amount, 'currency', v_pmt.currency,
        'party_type', v_pmt.party_type, 'party_id', v_pmt.party_id,
        'voucher_type', 'payment_entry', 'voucher_id', v_pmt.id, 'remarks', v_pmt.reference_number)
    ));
  else
    perform accounting.post_gl_lines(jsonb_build_array(
      jsonb_build_object('tenant_id', v_pmt.tenant_id, 'company_id', v_pmt.company_id,
        'posting_date', v_pmt.posting_date, 'account_id', p_receivable_or_payable_account_id,
        'debit_amount', v_pmt.paid_amount, 'credit_amount', 0, 'currency', v_pmt.currency,
        'party_type', v_pmt.party_type, 'party_id', v_pmt.party_id,
        'voucher_type', 'payment_entry', 'voucher_id', v_pmt.id, 'remarks', v_pmt.reference_number),
      jsonb_build_object('tenant_id', v_pmt.tenant_id, 'company_id', v_pmt.company_id,
        'posting_date', v_pmt.posting_date, 'account_id', p_cash_or_bank_account_id,
        'debit_amount', 0, 'credit_amount', v_pmt.paid_amount, 'currency', v_pmt.currency,
        'voucher_type', 'payment_entry', 'voucher_id', v_pmt.id, 'remarks', v_pmt.reference_number)
    ));
  end if;

  for v_ref in select * from accounting.payment_entry_references where payment_entry_id = p_payment_id loop
    if v_ref.reference_type = 'sales_invoice' then
      update accounting.sales_invoices
         set outstanding_amount = greatest(outstanding_amount - v_ref.allocated_amount, 0),
             status = case when outstanding_amount - v_ref.allocated_amount <= 0 then 'paid' else 'partially_paid' end
       where id = v_ref.reference_id;
    else
      update accounting.purchase_invoices
         set outstanding_amount = greatest(outstanding_amount - v_ref.allocated_amount, 0),
             status = case when outstanding_amount - v_ref.allocated_amount <= 0 then 'paid' else 'partially_paid' end
       where id = v_ref.reference_id;
    end if;
  end loop;

  update accounting.payment_entries set status = 'submitted' where id = p_payment_id;
end $$;
revoke all on function accounting.submit_payment_entry(uuid, uuid, uuid) from public, anon;
grant execute on function accounting.submit_payment_entry(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- JOURNAL ENTRIES (firm's own manual GL adjustments)
-- ============================================================================

create table accounting.journal_entries (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  company_id     uuid not null references accounting.companies(id),
  entry_number   text,
  posting_date   date not null default current_date,
  entry_type     text not null default 'journal_entry' check (entry_type in
                    ('journal_entry','bank_entry','cash_entry','depreciation','opening_entry','write_off')),
  reference      text,
  status         text not null default 'draft' check (status in ('draft','submitted','cancelled')),
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);

create table accounting.journal_entry_lines (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  journal_entry_id uuid not null references accounting.journal_entries(id),
  account_id     uuid not null references accounting.chart_of_accounts(id),
  debit_amount   numeric(20,4) not null default 0,
  credit_amount  numeric(20,4) not null default 0,
  party_type     text check (party_type in ('customer','supplier')),
  party_id       uuid,
  cost_center_id uuid references accounting.cost_centers(id),
  remarks        text,
  sort_order     int not null default 0,
  check (not (debit_amount <> 0 and credit_amount <> 0))
);
create index on accounting.journal_entry_lines(journal_entry_id);

create or replace function accounting.submit_journal_entry(p_je_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, accounting, app
as $$
declare v_je accounting.journal_entries%rowtype; v_lines jsonb;
begin
  select * into v_je from accounting.journal_entries where id = p_je_id;
  if not found or v_je.status <> 'draft' then
    raise exception 'Journal entry not found or not in draft status' using errcode = '22023';
  end if;

  select jsonb_agg(jsonb_build_object(
    'tenant_id', v_je.tenant_id, 'company_id', v_je.company_id, 'posting_date', v_je.posting_date,
    'account_id', jel.account_id, 'debit_amount', jel.debit_amount, 'credit_amount', jel.credit_amount,
    'party_type', jel.party_type, 'party_id', jel.party_id, 'cost_center_id', jel.cost_center_id,
    'voucher_type', 'journal_entry', 'voucher_id', v_je.id, 'remarks', coalesce(jel.remarks, v_je.reference)
  )) into v_lines
  from accounting.journal_entry_lines jel where jel.journal_entry_id = p_je_id;

  perform accounting.post_gl_lines(v_lines);
  update accounting.journal_entries set status = 'submitted' where id = p_je_id;
end $$;
revoke all on function accounting.submit_journal_entry(uuid) from public, anon;
grant execute on function accounting.submit_journal_entry(uuid) to authenticated;

-- ============================================================================
-- BANKING
-- ============================================================================

create table accounting.bank_accounts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  company_id     uuid not null references accounting.companies(id),
  account_name   text not null,
  bank_name      text,
  account_number_masked text,     -- last 4 only; never store full account numbers per platform policy
  currency       char(3) not null default 'USD',
  gl_account_id  uuid not null references accounting.chart_of_accounts(id),
  is_default     boolean not null default false,
  is_active      boolean not null default true,
  record_status  core.record_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid, updated_at timestamptz not null default now(),
  updated_by     uuid, row_version integer not null default 1
);
alter table accounting.payment_entries
  add constraint payment_entries_bank_account_fk foreign key (bank_account_id) references accounting.bank_accounts(id);

create table accounting.bank_transactions (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  bank_account_id    uuid not null references accounting.bank_accounts(id),
  transaction_date   date not null,
  description        text,
  deposit_amount     numeric(20,4) not null default 0,
  withdrawal_amount  numeric(20,4) not null default 0,
  currency           char(3) not null default 'USD',
  status             text not null default 'unreconciled' check (status in ('unreconciled','reconciled','ignored')),
  matched_payment_entry_id uuid references accounting.payment_entries(id),
  matched_journal_entry_id uuid references accounting.journal_entries(id),
  import_batch_id    uuid,
  created_at         timestamptz not null default now(),
  created_by         uuid
);
create index on accounting.bank_transactions(bank_account_id, status);

create table accounting.bank_reconciliations (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null,
  bank_account_id          uuid not null references accounting.bank_accounts(id),
  statement_from_date      date not null,
  statement_to_date        date not null,
  opening_balance          numeric(20,4) not null default 0,
  closing_balance_per_statement numeric(20,4) not null default 0,
  closing_balance_per_books numeric(20,4) not null default 0,
  status                   text not null default 'in_progress' check (status in ('in_progress','completed')),
  reconciled_by            uuid,
  reconciled_at            timestamptz,
  created_at               timestamptz not null default now(),
  created_by               uuid
);

-- ============================================================================
-- BUDGET
-- ============================================================================

create table accounting.budgets (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  company_id     uuid not null references accounting.companies(id),
  fiscal_year_id uuid not null references accounting.fiscal_years(id),
  cost_center_id uuid references accounting.cost_centers(id),
  account_id     uuid not null references accounting.chart_of_accounts(id),
  budget_amount  numeric(20,4) not null default 0,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  unique (fiscal_year_id, cost_center_id, account_id)
);

-- ============================================================================
-- REPORTING VIEWS
-- ============================================================================

create or replace view accounting.v_general_ledger with (security_invoker = true) as
select g.id, g.company_id, g.posting_date, g.account_id, coa.account_name, coa.root_type,
       g.debit_amount, g.credit_amount, g.voucher_type, g.voucher_id, g.party_type, g.party_id, g.remarks
from accounting.gl_entries g
join accounting.chart_of_accounts coa on coa.id = g.account_id;

create or replace view accounting.v_trial_balance with (security_invoker = true) as
select g.company_id, g.account_id, coa.account_name, coa.root_type,
       sum(g.debit_amount) as total_debit, sum(g.credit_amount) as total_credit,
       sum(g.debit_amount) - sum(g.credit_amount) as balance
from accounting.gl_entries g
join accounting.chart_of_accounts coa on coa.id = g.account_id
group by g.company_id, g.account_id, coa.account_name, coa.root_type;

create or replace view accounting.v_ar_aging with (security_invoker = true) as
select si.id, si.company_id, si.customer_id, c.customer_name, si.invoice_number, si.due_date,
       si.outstanding_amount,
       (current_date - si.due_date) as days_overdue
from accounting.sales_invoices si
join accounting.customers c on c.id = si.customer_id
where si.status in ('submitted','partially_paid','overdue') and si.outstanding_amount > 0;

create or replace view accounting.v_ap_aging with (security_invoker = true) as
select pi.id, pi.company_id, pi.supplier_id, s.supplier_name, pi.bill_number, pi.due_date,
       pi.outstanding_amount,
       (current_date - pi.due_date) as days_overdue
from accounting.purchase_invoices pi
join accounting.suppliers s on s.id = pi.supplier_id
where pi.status in ('submitted','partially_paid','overdue') and pi.outstanding_amount > 0;

grant select on accounting.v_general_ledger, accounting.v_trial_balance,
  accounting.v_ar_aging, accounting.v_ap_aging to authenticated, service_role;

-- ============================================================================
-- STAMP TRIGGERS + RLS (tenant-scoped throughout — the firm's books are not
-- matter-scoped; matter_id on invoices is informational/billing-reference
-- only, access is governed at the tenant level like CRM)
-- ============================================================================

do $$
declare t text; tables text[] := array[
  'accounting.companies','accounting.chart_of_accounts','accounting.customers',
  'accounting.suppliers','accounting.sales_invoices','accounting.credit_notes',
  'accounting.purchase_invoices','accounting.payment_entries',
  'accounting.journal_entries','accounting.bank_accounts'
];
begin
  foreach t in array tables loop
    execute format('create trigger tg_stamp before insert or update on %s
      for each row execute function app.tg_stamp_row()', t);
  end loop;
end $$;

do $$
declare t text; tables text[] := array[
  'accounting.companies','accounting.fiscal_years','accounting.chart_of_accounts',
  'accounting.cost_centers','accounting.payment_terms','accounting.modes_of_payment',
  'accounting.customers','accounting.suppliers',
  'accounting.sales_invoices','accounting.sales_invoice_lines','accounting.credit_notes',
  'accounting.purchase_invoices','accounting.purchase_invoice_lines',
  'accounting.payment_entries','accounting.payment_entry_references',
  'accounting.journal_entries','accounting.journal_entry_lines',
  'accounting.bank_accounts','accounting.bank_transactions','accounting.bank_reconciliations',
  'accounting.budgets'
];
begin
  foreach t in array tables loop
    execute format('alter table %s enable row level security', t);
    execute format('alter table %s force row level security', t);
    execute format($p$create policy sel on %s for select to authenticated
        using (app.has_tenant_access(tenant_id, 'read'));$p$, t);
    execute format($p$create policy ins on %s for insert to authenticated
        with check (app.has_tenant_access(tenant_id, 'contribute'));$p$, t);
  end loop;
  -- update allowed on mutable header tables only (gl_entries is append-only
  -- by design — corrections are reversing entries, not edits)
  foreach t in array array[
    'accounting.companies','accounting.chart_of_accounts','accounting.customers',
    'accounting.suppliers','accounting.sales_invoices','accounting.credit_notes',
    'accounting.purchase_invoices','accounting.payment_entries',
    'accounting.journal_entries','accounting.bank_accounts','accounting.bank_transactions',
    'accounting.bank_reconciliations'
  ] loop
    execute format($p$create policy upd on %s for update to authenticated
        using (app.has_tenant_access(tenant_id, 'contribute'))
        with check (app.has_tenant_access(tenant_id, 'contribute'));$p$, t);
  end loop;
end $$;

-- accounting.gl_entries is deliberately EXCLUDED from the loop above: every
-- write must go through accounting.post_gl_lines(), called only by the
-- security-definer submit_*() functions, never inserted into directly — the
-- same posture the platform already takes with operations.jobs writes and
-- audit.write(). Direct table INSERT/UPDATE/DELETE grants to `authenticated`
-- (picked up automatically by the schema's ALTER DEFAULT PRIVILEGES at the
-- top of this file) are revoked here; SELECT stays tenant-scoped as normal.
revoke insert, update, delete on accounting.gl_entries from authenticated;
alter table accounting.gl_entries enable row level security;
alter table accounting.gl_entries force row level security;
create policy sel on accounting.gl_entries for select to authenticated
  using (app.has_tenant_access(tenant_id, 'read'));

commit;
