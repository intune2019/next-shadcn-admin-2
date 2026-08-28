-- ============================================================================
-- Forens_iQ — Migration 0036: CRM firmographics + Chart of Accounts seed
--
-- Two closes from the ERPNext/Frappe CRM reference review:
--  1. crm.companies was missing Territory / Annual Revenue / No. of Employees
--     — standard firmographic fields visible on the Frappe CRM Organization
--     screen, useful for BD segmentation. Added here.
--  2. accounting.chart_of_accounts (0035) was structurally complete but
--     empty — this seeds a real COA for a forensic-accounting / litigation-
--     support firm, including trust/IOLTA-style client-funds accounts,
--     which matter for this business specifically (client retainers held
--     in trust must NEVER commingle with, or appear as, firm revenue).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. crm.companies firmographics
-- ---------------------------------------------------------------------------
alter table crm.companies
  add column if not exists territory text,
  add column if not exists annual_revenue numeric(18,2),
  add column if not exists employee_count int;

comment on column crm.companies.territory is 'Geographic/market segment, freeform (e.g. Southwest US, Federal). Admin-editable, not FK-constrained — matches this schema''s existing status-field philosophy.';

-- ---------------------------------------------------------------------------
-- 2. accounting.seed_default_chart_of_accounts — a real COA for THIS
-- business (fraud examination / litigation support / treasury governance /
-- monitorship / receivership / GRC audit fee lines; trust liability offsets
-- trust cash so client retainers never read as firm equity).
-- ---------------------------------------------------------------------------
create or replace function accounting.seed_default_chart_of_accounts(p_company_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, pg_temp, accounting, app
as $$
declare
  v_tenant_id uuid;
  v_assets uuid; v_liabilities uuid; v_equity uuid; v_income uuid; v_expenses uuid; v_fixed_assets uuid;
begin
  select tenant_id into v_tenant_id from accounting.companies where id = p_company_id;
  if v_tenant_id is null or not app.has_tenant_access(v_tenant_id, 'contribute') then
    raise exception 'Company not found or insufficient access' using errcode = '42501';
  end if;

  -- Root groups -------------------------------------------------------------
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, is_group)
  values (v_tenant_id, p_company_id, '1000', 'Assets', 'asset', true) returning id into v_assets;
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, is_group)
  values (v_tenant_id, p_company_id, '2000', 'Liabilities', 'liability', true) returning id into v_liabilities;
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, is_group)
  values (v_tenant_id, p_company_id, '3000', 'Equity', 'equity', true) returning id into v_equity;
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, is_group)
  values (v_tenant_id, p_company_id, '4000', 'Income', 'income', true) returning id into v_income;
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, is_group)
  values (v_tenant_id, p_company_id, '5000', 'Expenses', 'expense', true) returning id into v_expenses;
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, is_group, parent_account_id)
  values (v_tenant_id, p_company_id, '1500', 'Fixed Assets', 'asset', true, v_assets) returning id into v_fixed_assets;

  -- Assets --------------------------------------------------------------------
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, account_type, parent_account_id)
  values
    (v_tenant_id, p_company_id, '1010', 'Operating Cash - Bank', 'asset', 'Bank', v_assets),
    (v_tenant_id, p_company_id, '1020', 'Trust/IOLTA Cash - Client Funds', 'asset', 'Bank', v_assets),
    (v_tenant_id, p_company_id, '1100', 'Accounts Receivable', 'asset', 'Receivable', v_assets),
    (v_tenant_id, p_company_id, '1150', 'Unbilled Time and Expenses (WIP)', 'asset', null, v_assets),
    (v_tenant_id, p_company_id, '1200', 'Prepaid Expenses', 'asset', null, v_assets),
    (v_tenant_id, p_company_id, '1510', 'Computer Equipment', 'asset', 'Fixed Asset', v_fixed_assets),
    (v_tenant_id, p_company_id, '1520', 'Office Furniture', 'asset', 'Fixed Asset', v_fixed_assets),
    (v_tenant_id, p_company_id, '1590', 'Accumulated Depreciation', 'asset', 'Accumulated Depreciation', v_fixed_assets);

  -- Liabilities -----------------------------------------------------------
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, account_type, parent_account_id)
  values
    (v_tenant_id, p_company_id, '2010', 'Accounts Payable', 'liability', 'Payable', v_liabilities),
    (v_tenant_id, p_company_id, '2020', 'Trust/IOLTA Liability - Client Funds Held', 'liability', null, v_liabilities),
    (v_tenant_id, p_company_id, '2100', 'Accrued Payroll', 'liability', null, v_liabilities),
    (v_tenant_id, p_company_id, '2200', 'Deferred Revenue / Retainers Held', 'liability', null, v_liabilities),
    (v_tenant_id, p_company_id, '2300', 'Credit Card Payable', 'liability', null, v_liabilities);

  -- Equity ------------------------------------------------------------------
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, parent_account_id)
  values
    (v_tenant_id, p_company_id, '3010', 'Partner Capital', 'equity', v_equity),
    (v_tenant_id, p_company_id, '3020', 'Retained Earnings', 'equity', v_equity),
    (v_tenant_id, p_company_id, '3030', 'Owner Draws / Distributions', 'equity', v_equity);

  -- Income — one line per engagement type, so P&L shows fee mix by service line
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, parent_account_id)
  values
    (v_tenant_id, p_company_id, '4010', 'Fraud Examination Fees', 'income', v_income),
    (v_tenant_id, p_company_id, '4020', 'Litigation Support Fees', 'income', v_income),
    (v_tenant_id, p_company_id, '4030', 'Treasury Governance Fees', 'income', v_income),
    (v_tenant_id, p_company_id, '4040', 'Monitorship / Receivership Fees', 'income', v_income),
    (v_tenant_id, p_company_id, '4050', 'GRC Audit Fees', 'income', v_income),
    (v_tenant_id, p_company_id, '4090', 'Reimbursed Expense Income', 'income', v_income);

  -- Expenses ------------------------------------------------------------------
  insert into accounting.chart_of_accounts(tenant_id, company_id, account_number, account_name, root_type, parent_account_id)
  values
    (v_tenant_id, p_company_id, '5010', 'Salaries and Wages', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5020', 'Contractor / Expert Witness Fees', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5030', 'Professional Liability Insurance', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5040', 'CFE/CPA Licensing and CE', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5050', 'Software and SaaS Subscriptions', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5060', 'Office Rent', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5070', 'Travel and Court Appearance Expenses', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5080', 'Court Reporter and E-Discovery Vendor Fees', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5090', 'Bank and Merchant Fees', 'expense', v_expenses),
    (v_tenant_id, p_company_id, '5100', 'Depreciation Expense', 'expense', v_expenses);
end $$;

revoke all on function accounting.seed_default_chart_of_accounts(uuid) from public, anon;
grant execute on function accounting.seed_default_chart_of_accounts(uuid) to authenticated;

commit;

-- Usage, once you've created your accounting.companies row:
--   select accounting.seed_default_chart_of_accounts('<company_id>');
