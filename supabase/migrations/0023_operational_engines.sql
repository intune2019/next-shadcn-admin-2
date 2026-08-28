-- ============================================================================
-- Migration 0023: operational analytical and practitioner engines
-- Calculation execution, identity scoring, funds tracing, reconciliation,
-- document processing/editable working copies, court/claims, report assembly.
-- ============================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Calculation execution library
-- --------------------------------------------------------------------------

insert into calculations.model_definitions
  (model_code, model_name, domain, category, description, business_purpose,
   methodology_type, unit_of_measure, required_reviewer_role, approval_status,
   effective_from, approved_at)
values
  ('LIT_DMG_LOST_PROFITS_V1', 'Lost Profits', 'litigation', 'damages',
   'But-for revenue less actual revenue, avoided costs, and mitigation.',
   'Produces a transparent lost-profits calculation without hidden spreadsheet logic.',
   'economic', 'currency', 'damages_reviewer', 'approved', now(), now()),
  ('LIT_DMG_DISGORGEMENT_V1', 'Disgorgement', 'litigation', 'damages',
   'Wrongful revenue less directly attributable costs and approved offsets.',
   'Produces a governed net-wrongful-gain schedule for legal review.',
   'economic', 'currency', 'damages_reviewer', 'approved', now(), now())
on conflict (model_code) do nothing;

insert into calculations.model_versions
  (model_id, version_number, formula_language, formula_definition,
   input_contract, output_contract, assumption_schema, validation_rules,
   methodology_note, approval_status, approved_at)
select md.id, '1.0.0', 'calculation_dsl', v.formula_definition,
       v.input_contract, v.output_contract, v.assumption_schema,
       '{"currency_required":true,"no_floating_point":true}'::jsonb,
       v.methodology_note, 'approved', now()
from calculations.model_definitions md
join (values
  ('LIT_DMG_LOST_PROFITS_V1',
   'net_lost_profits = but_for_revenue - actual_revenue - avoided_costs + incremental_adjustments',
   '{"required":["but_for_revenue","actual_revenue","avoided_costs","incremental_adjustments"]}'::jsonb,
   '{"outputs":["revenue_differential","net_lost_profits"]}'::jsonb,
   '{"controlled":["projection_method","growth_rate","mitigation_treatment"]}'::jsonb,
   'Lost profits are an economic model, not a determination of causation, liability, or recoverability.'),
  ('LIT_DMG_DISGORGEMENT_V1',
   'net_wrongful_gain = wrongful_revenue - directly_attributable_costs - approved_offsets',
   '{"required":["wrongful_revenue","directly_attributable_costs","approved_offsets"]}'::jsonb,
   '{"outputs":["gross_wrongful_revenue","net_wrongful_gain"]}'::jsonb,
   '{"controlled":["cost_deductibility_standard","offset_treatment"]}'::jsonb,
   'Disgorgement methodology and deductible costs require legal review; the engine only applies approved inputs.')
) as v(model_code, formula_definition, input_contract, output_contract, assumption_schema, methodology_note)
  on v.model_code = md.model_code
on conflict (model_id, version_number) do nothing;

update calculations.model_definitions md
set current_version_id = mv.id
from calculations.model_versions mv
where mv.model_id = md.id and mv.version_number = '1.0.0'
  and md.model_code in ('LIT_DMG_LOST_PROFITS_V1','LIT_DMG_DISGORGEMENT_V1')
  and md.current_version_id is distinct from mv.id;

create or replace function calculations.execute_model(
  p_model_version_id uuid,
  p_matter_id uuid,
  p_inputs jsonb,
  p_assumptions jsonb default '{}'::jsonb,
  p_run_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp, calculations, core, app, extensions
as $$
declare
  v_tenant_id uuid;
  v_model_code text;
  v_formula_checksum bytea;
  v_run_id uuid;
  v_currency char(3) := upper(coalesce(p_inputs->>'currency','USD'))::char(3);
  v_output numeric(20,4);
  v_secondary numeric(20,4);
  v_tertiary numeric(20,4);
  v_days integer;
  v_rate numeric;
  v_method text;
  v_n numeric;
  v_narrative text;
  v_warnings int := 0;
  v_item jsonb;
  v_row int := 0;
  kv record;
begin
  if not app.has_matter_access(p_matter_id, 'contribute') then
    raise exception 'contribute access is required to run calculations' using errcode='42501';
  end if;

  select m.tenant_id into v_tenant_id from core.matters m where m.id=p_matter_id;
  select md.model_code, mv.formula_checksum
    into v_model_code, v_formula_checksum
  from calculations.model_versions mv
  join calculations.model_definitions md on md.id=mv.model_id
  where mv.id=p_model_version_id and mv.approval_status='approved'
    and md.approval_status='approved';
  if v_model_code is null then
    raise exception 'approved calculation model version not found' using errcode='22023';
  end if;

  insert into calculations.calculation_runs
    (tenant_id,matter_id,model_version_id,formula_checksum_at_run,run_name,
     parameter_values,reporting_currency,status,created_by)
  values
    (v_tenant_id,p_matter_id,p_model_version_id,v_formula_checksum,
     coalesce(nullif(btrim(p_run_name),''),v_model_code),
     jsonb_build_object('inputs',p_inputs,'assumptions',p_assumptions),
     v_currency,'running',app.current_user_id())
  returning id into v_run_id;

  for kv in select * from jsonb_each(p_inputs) loop
    insert into calculations.calculation_inputs
      (tenant_id,matter_id,calculation_run_id,input_name,input_type,source_type,
       original_value,normalized_value,unit,entered_by,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,kv.key,jsonb_typeof(kv.value),'user_supplied',
       kv.value,kv.value,case when kv.key='currency' then 'ISO-4217' else null end,
       app.current_user_id(),app.current_user_id());
  end loop;
  for kv in select * from jsonb_each(p_assumptions) loop
    insert into calculations.calculation_assumptions
      (tenant_id,matter_id,calculation_run_id,assumption_code,assumption_name,
       value,basis,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,kv.key,replace(initcap(kv.key),'_',' '),
       kv.value,'Practitioner-supplied controlled assumption',app.current_user_id());
  end loop;

  if v_model_code in ('FX_LOSS_KNOWN_UNAUTHORIZED_DISBURSEMENTS_V1','FX_LOSS_NET_V1') then
    v_secondary := coalesce((p_inputs->>'verified_recoveries')::numeric,0)
                 + coalesce((p_inputs->>'approved_offsets')::numeric,0);
    v_output := coalesce((p_inputs->>'gross_loss')::numeric,0) - v_secondary;
    v_narrative := format('Gross known loss %s %s less verified recoveries and approved offsets %s equals net known loss %s.',
      v_currency, coalesce(p_inputs->>'gross_loss','0'), v_secondary, v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,methodology_status,report_order,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,'gross_known_loss','Gross known loss',coalesce((p_inputs->>'gross_loss')::numeric,0),v_currency,'actual',1,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'verified_recoveries_and_offsets','Verified recoveries and approved offsets',v_secondary,v_currency,'actual',2,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'net_known_loss','Net known loss',v_output,v_currency,'actual',3,app.current_user_id());

  elsif v_model_code='FX_RESTITUTION_CANDIDATE_V1' then
    v_secondary := coalesce((p_inputs->>'returned_property_value')::numeric,0)
                 + coalesce((p_inputs->>'verified_recovery')::numeric,0)
                 + coalesce((p_inputs->>'approved_credit_or_offset')::numeric,0);
    v_output := coalesce((p_inputs->>'gross_actual_loss')::numeric,0)-v_secondary;
    v_narrative := format('Gross actual loss less documented returns, recoveries, and approved offsets yields a restitution candidate of %s %s.',v_currency,v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,methodology_status,report_order,created_by)
    values (v_tenant_id,p_matter_id,v_run_id,'restitution_candidate','Restitution candidate',v_output,v_currency,'actual',1,app.current_user_id());

  elsif v_model_code='LIT_DMG_LOST_PROFITS_V1' then
    v_secondary := coalesce((p_inputs->>'but_for_revenue')::numeric,0)-coalesce((p_inputs->>'actual_revenue')::numeric,0);
    v_output := v_secondary-coalesce((p_inputs->>'avoided_costs')::numeric,0)
      +coalesce((p_inputs->>'incremental_adjustments')::numeric,0)
      -coalesce((p_inputs->>'incremental_mitigation_costs')::numeric,0);
    v_narrative := format('But-for revenue less actual revenue and avoided costs, plus approved incremental adjustments and less mitigation costs, yields modeled net lost profits of %s %s.',v_currency,v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,methodology_status,report_order,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,'revenue_differential','Revenue differential',v_secondary,v_currency,'modeled',1,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'net_lost_profits','Net lost profits',v_output,v_currency,'modeled',2,app.current_user_id());

  elsif v_model_code='LIT_DMG_DISGORGEMENT_V1' then
    v_output := coalesce((p_inputs->>'wrongful_revenue')::numeric,0)
      -coalesce((p_inputs->>'directly_attributable_costs')::numeric,0)
      -coalesce((p_inputs->>'approved_offsets')::numeric,0);
    v_narrative := format('Wrongful revenue less directly attributable costs and approved offsets yields modeled net wrongful gain of %s %s.',v_currency,v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,methodology_status,report_order,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,'gross_wrongful_revenue','Gross wrongful revenue',coalesce((p_inputs->>'wrongful_revenue')::numeric,0),v_currency,'actual',1,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'net_wrongful_gain','Net wrongful gain',v_output,v_currency,'modeled',2,app.current_user_id());

  elsif v_model_code='ECON_PREJUDGMENT_INTEREST_V1' then
    v_days := (p_inputs->>'end_date')::date-(p_inputs->>'start_date')::date;
    if v_days < 0 then raise exception 'end_date must not precede start_date' using errcode='22023'; end if;
    v_rate := (p_inputs->>'annual_rate')::numeric;
    v_method := lower(coalesce(p_inputs->>'interest_method','simple'));
    v_n := coalesce((p_inputs->>'compounding_periods_per_year')::numeric,12);
    if v_method='simple' then
      v_output := round((p_inputs->>'principal')::numeric*v_rate*(v_days/coalesce((p_inputs->>'day_count_basis')::numeric,365)),4);
    elsif v_method='compound' then
      v_output := round((p_inputs->>'principal')::numeric*(power(1+v_rate/v_n,v_n*v_days/365.0)-1),4);
    else
      raise exception 'unsupported interest_method: %',v_method using errcode='22023';
    end if;
    v_narrative := format('%s interest on %s %s at annual rate %s for %s days equals %s.',initcap(v_method),v_currency,p_inputs->>'principal',v_rate,v_days,v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,quantity,methodology_status,report_order,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,'principal','Principal',(p_inputs->>'principal')::numeric,v_currency,v_days,'actual',1,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'prejudgment_interest','Prejudgment interest',v_output,v_currency,v_days,'modeled',2,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'total_with_interest','Total with interest',(p_inputs->>'principal')::numeric+v_output,v_currency,v_days,'modeled',3,app.current_user_id());

  elsif v_model_code='ECON_PRESENT_VALUE_V1' then
    v_rate := (p_inputs->>'discount_rate')::numeric;
    v_output := 0;
    if jsonb_typeof(p_inputs->'cash_flows') <> 'array' then raise exception 'cash_flows must be an array' using errcode='22023'; end if;
    for v_item in select * from jsonb_array_elements(p_inputs->'cash_flows') loop
      v_row := v_row+1;
      v_secondary := round((v_item->>'amount')::numeric/power(1+v_rate,(v_item->>'period')::numeric),4);
      v_output := v_output+v_secondary;
      insert into calculations.calculation_schedule_rows
        (tenant_id,matter_id,calculation_run_id,schedule_code,row_number,row_date,description,net_amount,currency,created_by)
      values (v_tenant_id,p_matter_id,v_run_id,'present_value',v_row,null,
        format('Cash flow period %s; undiscounted %s',v_item->>'period',v_item->>'amount'),v_secondary,v_currency,app.current_user_id());
    end loop;
    v_narrative := format('The present value of %s cash-flow periods at discount rate %s is %s %s.',v_row,v_rate,v_currency,v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,methodology_status,report_order,created_by)
    values (v_tenant_id,p_matter_id,v_run_id,'present_value','Present value',v_output,v_currency,'modeled',1,app.current_user_id());

  elsif v_model_code='TREASURY_BANK_RECONCILIATION_V1' then
    v_secondary := coalesce((p_inputs->>'ledger_ending_balance')::numeric,0)
      +coalesce((p_inputs->>'outstanding_checks')::numeric,0)
      -coalesce((p_inputs->>'deposits_in_transit')::numeric,0)
      +coalesce((p_inputs->>'approved_adjustments')::numeric,0);
    v_output := coalesce((p_inputs->>'bank_ending_balance')::numeric,0)-v_secondary;
    v_narrative := format('Bank ending balance less reconciled ledger balance yields an unexplained difference of %s %s.',v_currency,v_output);
    insert into calculations.calculation_outputs
      (tenant_id,matter_id,calculation_run_id,output_code,output_name,amount,currency,methodology_status,report_order,created_by)
    values
      (v_tenant_id,p_matter_id,v_run_id,'reconciled_balance','Reconciled ledger balance',v_secondary,v_currency,'actual',1,app.current_user_id()),
      (v_tenant_id,p_matter_id,v_run_id,'unexplained_difference','Unexplained difference',v_output,v_currency,'actual',2,app.current_user_id());
  else
    raise exception 'model % is cataloged but has no executable adapter',v_model_code using errcode='0A000';
  end if;

  if v_output < 0 then v_warnings:=v_warnings+1; end if;
  update calculations.calculation_runs
  set status='completed', output_total=v_output, output_currency=v_currency,
      warning_count=v_warnings, completed_at=clock_timestamp(), narrative=v_narrative,
      run_hash=extensions.digest(convert_to(
        coalesce(encode(v_formula_checksum,'hex'),'')||p_inputs::text||p_assumptions::text||v_output::text,
        'UTF8'),'sha256')
  where id=v_run_id;
  return v_run_id;
exception when others then
  if v_run_id is not null then
    update calculations.calculation_runs set status='failed',exception_count=1 where id=v_run_id;
  end if;
  raise;
end;
$$;
revoke all on function calculations.execute_model(uuid,uuid,jsonb,jsonb,text) from public,anon;
grant execute on function calculations.execute_model(uuid,uuid,jsonb,jsonb,text) to authenticated;

-- --------------------------------------------------------------------------
-- 2. Weighted entity resolution
-- --------------------------------------------------------------------------

create or replace function identity.generate_match_candidates(
  p_matter_id uuid,
  p_min_score numeric default 35
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, pg_temp, identity, canonical, core, app, extensions
as $$
declare v_count int;
begin
  if not app.has_matter_access(p_matter_id,'contribute') then
    raise exception 'contribute access is required to generate entity candidates' using errcode='42501';
  end if;
  with pairs as (
    select a.tenant_id,a.matter_id,a.id entity_id_a,b.id entity_id_b,
      coalesce(extensions.similarity(coalesce(a.name_normalized,a.display_name,''),coalesce(b.name_normalized,b.display_name,'')),0) name_similarity,
      exists(select 1 from identity.entity_aliases aa join identity.entity_aliases ab
        on ab.matter_id=aa.matter_id and ab.alias_value_normalized=aa.alias_value_normalized
        where aa.entity_id=a.id and ab.entity_id=b.id and aa.alias_value_normalized is not null) alias_match,
      exists(select 1 from canonical.addresses aa join canonical.addresses ab
        on ab.matter_id=aa.matter_id and ab.address_hash=aa.address_hash
        where aa.entity_id=a.id and ab.entity_id=b.id and aa.address_hash is not null) address_match,
      exists(select 1 from canonical.contact_points ca join canonical.contact_points cb
        on cb.matter_id=ca.matter_id and cb.kind=ca.kind and cb.value_normalized=ca.value_normalized
        where ca.entity_id=a.id and cb.entity_id=b.id and ca.value_normalized is not null) contact_match,
      exists(select 1 from canonical.bank_accounts ba join canonical.bank_accounts bb
        on bb.matter_id=ba.matter_id and bb.account_token=ba.account_token
        where ba.owner_entity_id=a.id and bb.owner_entity_id=b.id and ba.account_token is not null) bank_match
    from canonical.entities a join canonical.entities b
      on b.matter_id=a.matter_id and b.entity_type=a.entity_type and b.id>a.id
    where a.matter_id=p_matter_id and a.record_status='active' and b.record_status='active'
  ), scored as (
    select *,round((45*name_similarity + 15*alias_match::int + 15*address_match::int
      + 10*contact_match::int + 15*bank_match::int)::numeric,2) score
    from pairs
  ), upserted as (
    insert into identity.entity_match_candidates
      (tenant_id,matter_id,entity_id_a,entity_id_b,match_score,score_breakdown,
       match_basis,candidate_type,generated_by,review_status,created_by)
    select tenant_id,matter_id,entity_id_a,entity_id_b,score,
      jsonb_build_object('name_similarity',name_similarity,'name_weight',0.45,
        'alias_match',alias_match,'alias_weight',0.15,'address_match',address_match,'address_weight',0.15,
        'contact_match',contact_match,'contact_weight',0.10,'bank_match',bank_match,'bank_weight',0.15),
      array_remove(array[
        case when name_similarity>=0.6 then 'name_similarity' end,
        case when alias_match then 'shared_alias' end,case when address_match then 'shared_address' end,
        case when contact_match then 'shared_contact' end,case when bank_match then 'shared_bank_account' end],null),
      case when score>=85 then 'exact_identity' when score>=65 then 'probable_identity'
           else 'possible_relationship' end,'weighted_v1',
      case when score>=85 then 'high_priority_review' else 'pending' end,app.current_user_id()
    from scored where score>=p_min_score
    on conflict (matter_id,entity_id_a,entity_id_b,generated_by) do update
      set match_score=excluded.match_score,score_breakdown=excluded.score_breakdown,
          match_basis=excluded.match_basis,candidate_type=excluded.candidate_type
    returning 1
  ) select count(*) into v_count from upserted;
  return v_count;
end;
$$;
revoke all on function identity.generate_match_candidates(uuid,numeric) from public,anon;
grant execute on function identity.generate_match_candidates(uuid,numeric) to authenticated;

-- --------------------------------------------------------------------------
-- 3. Funds-flow graph and tracing allocation ledger
-- --------------------------------------------------------------------------

create or replace view analytics.v_funds_flow
with (security_invoker=true) as
select l.tenant_id,l.matter_id,l.id leg_id,l.transaction_id,t.transaction_date,
  l.leg_sequence,l.from_entity_id,l.to_entity_id,l.from_account_id,l.to_account_id,
  l.amount,l.currency,l.role,l.source_evidence_id,l.confidence_score,
  coalesce(fe.display_name,fa.institution_name,l.from_account_id::text) source_label,
  coalesce(te.display_name,ta.institution_name,l.to_account_id::text) destination_label
from canonical.transaction_legs l
join canonical.transactions t on t.id=l.transaction_id
left join canonical.entities fe on fe.id=l.from_entity_id
left join canonical.entities te on te.id=l.to_entity_id
left join canonical.bank_accounts fa on fa.id=l.from_account_id
left join canonical.bank_accounts ta on ta.id=l.to_account_id;
grant select on analytics.v_funds_flow to authenticated,service_role;

create table calculations.funds_trace_runs (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null,
  matter_id uuid not null references core.matters(id), account_id uuid not null references canonical.bank_accounts(id),
  source_transaction_id uuid not null references canonical.transactions(id), tracing_method text not null
    check (tracing_method in ('LIBR','FIFO','LIFO','NETTING')),
  opening_balance numeric(20,4) not null default 0, source_amount numeric(20,4) not null,
  traceable_amount numeric(20,4), as_of_date date not null, status text not null default 'completed',
  methodology_note text, run_hash bytea, created_at timestamptz not null default now(), created_by uuid
);
create table calculations.funds_trace_allocations (
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
  trace_run_id uuid not null references calculations.funds_trace_runs(id),transaction_id uuid references canonical.transactions(id),
  allocation_sequence int not null,transaction_date date,flow_direction text not null,
  flow_amount numeric(20,4) not null,traceable_before numeric(20,4) not null,
  traced_amount_applied numeric(20,4) not null,traceable_after numeric(20,4) not null,
  evidence_id uuid references evidence.evidence_items(id),created_at timestamptz not null default now(),created_by uuid
);
create index on calculations.funds_trace_runs(matter_id,created_at);
create index on calculations.funds_trace_allocations(trace_run_id,allocation_sequence);

alter table calculations.funds_trace_runs enable row level security;
alter table calculations.funds_trace_runs force row level security;
alter table calculations.funds_trace_allocations enable row level security;
alter table calculations.funds_trace_allocations force row level security;
create policy sel on calculations.funds_trace_runs for select to authenticated using(app.has_matter_access(matter_id,'read'));
create policy sel on calculations.funds_trace_allocations for select to authenticated using(app.has_matter_access(matter_id,'read'));
grant select on calculations.funds_trace_runs,calculations.funds_trace_allocations to authenticated;
grant select,insert,update,delete on calculations.funds_trace_runs,calculations.funds_trace_allocations to service_role;

create or replace function calculations.execute_funds_trace(
  p_matter_id uuid,p_account_id uuid,p_source_transaction_id uuid,p_method text,
  p_opening_balance numeric default 0,p_as_of_date date default current_date
)
returns uuid language plpgsql security definer
set search_path=pg_catalog,pg_temp,calculations,canonical,core,app,extensions
as $$
declare v_tenant uuid;v_run uuid;v_source numeric;v_source_date date;v_remaining numeric;v_running numeric;
  v_withdrawals numeric:=0;v_applied numeric;v_before numeric;v_seq int:=0;r record;v_method text:=upper(p_method);
begin
  if not app.has_matter_access(p_matter_id,'contribute') then raise exception 'contribute access required' using errcode='42501'; end if;
  if v_method not in ('LIBR','FIFO','LIFO','NETTING') then raise exception 'unsupported tracing method' using errcode='22023'; end if;
  select m.tenant_id into v_tenant from core.matters m where m.id=p_matter_id;
  select l.amount,t.transaction_date into v_source,v_source_date
  from canonical.transaction_legs l join canonical.transactions t on t.id=l.transaction_id
  where l.matter_id=p_matter_id and l.transaction_id=p_source_transaction_id and l.to_account_id=p_account_id
  order by l.leg_sequence limit 1;
  if v_source is null then raise exception 'source transaction is not an inflow to the selected account' using errcode='22023'; end if;
  v_remaining:=v_source;v_running:=p_opening_balance+v_source;
  insert into calculations.funds_trace_runs(tenant_id,matter_id,account_id,source_transaction_id,tracing_method,
    opening_balance,source_amount,as_of_date,methodology_note,created_by)
  values(v_tenant,p_matter_id,p_account_id,p_source_transaction_id,v_method,p_opening_balance,v_source,p_as_of_date,
    case v_method when 'LIBR' then 'Lowest intermediate balance; later deposits do not replenish depleted traced proceeds.'
      when 'FIFO' then 'Withdrawals consume opening/older funds before identified proceeds.'
      when 'LIFO' then 'Withdrawals consume identified/recent proceeds first.'
      else 'Net inflows and outflows capped at identified proceeds.' end,app.current_user_id()) returning id into v_run;
  for r in
    select t.id,t.transaction_date,l.amount,
      case when l.to_account_id=p_account_id then 'inflow' else 'outflow' end direction,l.source_evidence_id
    from canonical.transaction_legs l join canonical.transactions t on t.id=l.transaction_id
    where l.matter_id=p_matter_id and (l.from_account_id=p_account_id or l.to_account_id=p_account_id)
      and t.transaction_date>=v_source_date and t.transaction_date<=p_as_of_date and t.id<>p_source_transaction_id
    order by t.transaction_date,t.id,l.leg_sequence
  loop
    v_seq:=v_seq+1;v_before:=v_remaining;v_applied:=0;
    if r.direction='inflow' then
      v_running:=v_running+r.amount;
      if v_method='NETTING' then v_remaining:=least(v_source,v_remaining+r.amount); end if;
    else
      v_running:=v_running-r.amount;v_withdrawals:=v_withdrawals+r.amount;
      if v_method='FIFO' then
        v_remaining:=greatest(v_source-greatest(v_withdrawals-p_opening_balance,0),0);
      elsif v_method in ('LIFO','NETTING') then
        v_remaining:=greatest(v_remaining-r.amount,0);
      else
        v_remaining:=least(v_remaining,greatest(v_running,0));
      end if;
      v_applied:=greatest(v_before-v_remaining,0);
    end if;
    insert into calculations.funds_trace_allocations(tenant_id,matter_id,trace_run_id,transaction_id,
      allocation_sequence,transaction_date,flow_direction,flow_amount,traceable_before,traced_amount_applied,
      traceable_after,evidence_id,created_by)
    values(v_tenant,p_matter_id,v_run,r.id,v_seq,r.transaction_date,r.direction,r.amount,v_before,v_applied,
      v_remaining,r.source_evidence_id,app.current_user_id());
  end loop;
  update calculations.funds_trace_runs set traceable_amount=v_remaining,
    run_hash=extensions.digest(convert_to(v_method||p_account_id::text||p_source_transaction_id::text||p_opening_balance::text||p_as_of_date::text||v_remaining::text,'UTF8'),'sha256')
  where id=v_run;
  return v_run;
end;
$$;
revoke all on function calculations.execute_funds_trace(uuid,uuid,uuid,text,numeric,date) from public,anon;
grant execute on function calculations.execute_funds_trace(uuid,uuid,uuid,text,numeric,date) to authenticated;

-- --------------------------------------------------------------------------
-- 4. Invoice-to-payment reconciliation
-- --------------------------------------------------------------------------

alter table quality.reconciliations alter column dataset_version_id drop not null;
alter table quality.reconciliations drop constraint if exists reconciliations_reconciliation_type_check;
alter table quality.reconciliations add constraint reconciliations_reconciliation_type_check check (reconciliation_type in
  ('row_count','amount','balanced_journal','payment_linkage','account_continuity',
   'mapping_completeness','schema_drift','bank_to_ledger','invoice_to_payment'));
alter table quality.reconciliations drop constraint if exists reconciliations_result_check;
alter table quality.reconciliations add constraint reconciliations_result_check check (result in
  ('balanced','out_of_balance','not_evaluated','passed','failed'));
alter table quality.reconciling_items drop constraint if exists reconciling_items_disposition_check;
alter table quality.reconciling_items add constraint reconciling_items_disposition_check check (disposition in
  ('unresolved','open','explained','adjusted','written_off'));
alter table quality.reconciling_items add column if not exists owner_user_id uuid;
alter table quality.reconciling_items add column if not exists originating_date date;
alter table quality.reconciling_items add column if not exists aging_days integer;
alter table quality.reconciling_items add column if not exists explanation text;
alter table quality.reconciling_items add column if not exists source_evidence_id uuid references evidence.evidence_items(id);
alter table quality.reconciling_items add column if not exists escalation_band text;

create or replace function quality.run_invoice_payment_reconciliation(p_matter_id uuid,p_tolerance numeric default 0.01)
returns uuid language plpgsql security definer
set search_path=pg_catalog,pg_temp,quality,canonical,core,app
as $$
declare v_tenant uuid;v_id uuid;v_invoice_total numeric;v_applied_total numeric;v_difference numeric;
begin
  if not app.has_matter_access(p_matter_id,'contribute') then raise exception 'contribute access required' using errcode='42501'; end if;
  select tenant_id into v_tenant from core.matters where id=p_matter_id;
  select coalesce(sum(case when invoice_status='credit_memo' then -abs(amount_original) else amount_original end),0)
    into v_invoice_total from canonical.invoices where matter_id=p_matter_id and record_status='active';
  select coalesce(sum(applied_amount),0) into v_applied_total from canonical.payment_invoice_links where matter_id=p_matter_id and record_status='active';
  v_difference:=v_invoice_total-v_applied_total;
  insert into quality.reconciliations(tenant_id,matter_id,reconciliation_type,source_value,canonical_value,
    rejected_value,documented_adjustments,tolerance,result,created_by)
  values(v_tenant,p_matter_id,'invoice_to_payment',v_invoice_total,v_applied_total,0,0,p_tolerance,
    case when abs(v_difference)<=p_tolerance then 'passed' else 'failed' end,app.current_user_id()) returning id into v_id;
  insert into quality.reconciling_items(tenant_id,matter_id,reconciliation_id,description,amount,disposition,created_by)
  select v_tenant,p_matter_id,v_id,
    format('Invoice %s: invoice/credit %s; applied %s',coalesce(i.invoice_number_raw,i.id::text),
      case when i.invoice_status='credit_memo' then -abs(coalesce(i.amount_original,0)) else coalesce(i.amount_original,0) end,
      coalesce(sum(l.applied_amount),0)),
    (case when i.invoice_status='credit_memo' then -abs(coalesce(i.amount_original,0)) else coalesce(i.amount_original,0) end)-coalesce(sum(l.applied_amount),0),
    'open',app.current_user_id()
  from canonical.invoices i left join canonical.payment_invoice_links l on l.invoice_id=i.id and l.record_status='active'
  where i.matter_id=p_matter_id and i.record_status='active'
  group by i.id,i.invoice_number_raw,i.amount_original
  having abs((case when i.invoice_status='credit_memo' then -abs(coalesce(i.amount_original,0)) else coalesce(i.amount_original,0) end)-coalesce(sum(l.applied_amount),0))>p_tolerance;
  return v_id;
end;
$$;
revoke all on function quality.run_invoice_payment_reconciliation(uuid,numeric) from public,anon;
grant execute on function quality.run_invoice_payment_reconciliation(uuid,numeric) to authenticated;

-- --------------------------------------------------------------------------
-- 5. Document processing, extracted entities, and editable working copies
-- --------------------------------------------------------------------------

create table evidence.document_processing_jobs(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
  evidence_file_id uuid not null references evidence.evidence_files(id),status text not null default 'queued'
    check(status in ('queued','processing','completed','failed')),
  processor text,attempt_count int not null default 0,error_message text,started_at timestamptz,completed_at timestamptz,
  created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table evidence.extracted_documents(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
  evidence_file_id uuid not null references evidence.evidence_files(id),processing_job_id uuid references evidence.document_processing_jobs(id),
  extraction_method text not null,content_text text,language text default 'eng',page_count int,metadata jsonb not null default '{}'::jsonb,
  content_sha256 bytea,created_at timestamptz not null default now(),created_by uuid
);
create table evidence.extracted_entities(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
  extracted_document_id uuid not null references evidence.extracted_documents(id),entity_type text not null,entity_text text not null,
  normalized_text text,confidence numeric(5,4),start_offset int,end_offset int,created_at timestamptz not null default now(),created_by uuid
);
create table evidence.document_working_copies(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
  evidence_file_id uuid not null references evidence.evidence_files(id),version_number int not null,content_text text not null,
  change_note text,status text not null default 'draft' check(status in ('draft','reviewed','approved','superseded')),
  source_extraction_id uuid references evidence.extracted_documents(id),content_sha256 bytea not null,
  created_at timestamptz not null default now(),created_by uuid,unique(evidence_file_id,version_number)
);
create index on evidence.document_processing_jobs(matter_id,status,created_at);
create index on evidence.extracted_documents(evidence_file_id,created_at);
create index on evidence.extracted_entities(extracted_document_id,entity_type);
create index on evidence.document_working_copies(evidence_file_id,version_number desc);

do $$ declare t text;begin foreach t in array array['document_processing_jobs','extracted_documents','extracted_entities','document_working_copies'] loop
  execute format('alter table evidence.%I enable row level security',t);execute format('alter table evidence.%I force row level security',t);
  execute format('create policy sel on evidence.%I for select to authenticated using(app.has_matter_access(matter_id,''read''))',t);
  execute format('create policy ins on evidence.%I for insert to authenticated with check(app.has_matter_access(matter_id,''contribute''))',t);
end loop;end $$;
create policy upd on evidence.document_processing_jobs for update to authenticated using(app.has_matter_access(matter_id,'contribute')) with check(app.has_matter_access(matter_id,'contribute'));
grant select,insert on evidence.document_processing_jobs,evidence.extracted_documents,evidence.extracted_entities,evidence.document_working_copies to authenticated;
grant update on evidence.document_processing_jobs to authenticated;
grant select,insert,update,delete on evidence.document_processing_jobs,evidence.extracted_documents,evidence.extracted_entities,evidence.document_working_copies to service_role;

create or replace function evidence.save_working_copy(p_evidence_file_id uuid,p_content text,p_change_note text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,evidence,core,app,extensions as $$
declare v_file evidence.evidence_files%rowtype;v_id uuid;v_version int;begin
  select * into v_file from evidence.evidence_files where id=p_evidence_file_id;
  if not found or not app.has_matter_access(v_file.matter_id,'contribute') then raise exception 'file not found or insufficient access' using errcode='42501';end if;
  if nullif(p_content,'') is null then raise exception 'working-copy content is required' using errcode='22023';end if;
  select coalesce(max(version_number),0)+1 into v_version from evidence.document_working_copies where evidence_file_id=p_evidence_file_id;
  insert into evidence.document_working_copies(tenant_id,matter_id,evidence_file_id,version_number,content_text,change_note,content_sha256,created_by)
  values(v_file.tenant_id,v_file.matter_id,p_evidence_file_id,v_version,p_content,p_change_note,
    extensions.digest(convert_to(p_content,'UTF8'),'sha256'),app.current_user_id()) returning id into v_id;
  return v_id;
end;$$;
revoke all on function evidence.save_working_copy(uuid,text,text) from public,anon;
grant execute on function evidence.save_working_copy(uuid,text,text) to authenticated;

-- --------------------------------------------------------------------------
-- 6. Court appointments and claims administration
-- --------------------------------------------------------------------------

create schema if not exists court;create schema if not exists claims;
grant usage on schema court,claims to authenticated,service_role;
alter default privileges in schema court grant select,insert,update,delete on tables to authenticated,service_role;
alter default privileges in schema claims grant select,insert,update,delete on tables to authenticated,service_role;

create table court.appointments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
 authority_instrument_id uuid references core.authority_instruments(id),appointment_type text not null,appointing_authority text,
 order_date date,effective_date date,order_text text not null,authority_limits text,reporting_cadence text,status text not null default 'active',
 record_status core.record_status not null default 'active',created_at timestamptz not null default now(),created_by uuid,
 updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table court.appointment_obligations(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),
 appointment_id uuid not null references court.appointments(id),clause_number text,clause_category text not null,
 clause_text text not null,due_date date,responsible_user_id uuid,status text not null default 'open',completion_evidence_id uuid references evidence.evidence_items(id),
 record_status core.record_status not null default 'active',created_at timestamptz not null default now(),created_by uuid,
 updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table court.hearings(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),appointment_id uuid references court.appointments(id),
 hearing_at timestamptz not null,hearing_type text,location text,agenda text,outcome text,status text not null default 'scheduled',
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table claims.claims(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),claim_number text not null,
 claimant_name text not null,claim_type text,amount_claimed numeric(20,4),currency char(3) default 'USD',filed_at timestamptz,
 eligibility_status text not null default 'pending',review_status text not null default 'new',deficiency_note text,
 record_status core.record_status not null default 'active',created_at timestamptz not null default now(),created_by uuid,
 updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,claim_number)
);
create table claims.claim_determinations(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),claim_id uuid not null references claims.claims(id),
 determination text not null,allowed_amount numeric(20,4),currency char(3) default 'USD',rationale text,determined_by uuid,determined_at timestamptz,
 appeal_deadline date,status text not null default 'draft',created_at timestamptz not null default now(),created_by uuid,
 updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table claims.distributions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,matter_id uuid not null references core.matters(id),claim_id uuid not null references claims.claims(id),
 determination_id uuid references claims.claim_determinations(id),amount numeric(20,4) not null,currency char(3) default 'USD',scheduled_date date,paid_date date,
 payment_reference text,status text not null default 'scheduled',created_at timestamptz not null default now(),created_by uuid,
 updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);

do $$ declare s text;t text;tables text[];begin
  foreach s in array array['court','claims'] loop
    tables := case when s='court' then array['appointments','appointment_obligations','hearings'] else array['claims','claim_determinations','distributions'] end;
    foreach t in array tables loop
    execute format('create trigger tg_stamp before insert or update on %I.%I for each row execute function app.tg_stamp_row()',s,t);
    execute format('alter table %I.%I enable row level security',s,t);execute format('alter table %I.%I force row level security',s,t);
    execute format('create policy sel on %I.%I for select to authenticated using(app.has_matter_access(matter_id,''read''))',s,t);
    execute format('create policy ins on %I.%I for insert to authenticated with check(app.has_matter_access(matter_id,''contribute''))',s,t);
    execute format('create policy upd on %I.%I for update to authenticated using(app.has_matter_access(matter_id,''contribute'')) with check(app.has_matter_access(matter_id,''contribute''))',s,t);
    end loop;
  end loop;
end $$;

create or replace function court.parse_appointment_order(p_appointment_id uuid)
returns integer language plpgsql security definer set search_path=pg_catalog,pg_temp,court,core,app as $$
declare v_a court.appointments%rowtype;v_line text;v_count int:=0;begin
  select * into v_a from court.appointments where id=p_appointment_id;
  if not found or not app.has_matter_access(v_a.matter_id,'contribute') then raise exception 'appointment not found or insufficient access' using errcode='42501';end if;
  delete from court.appointment_obligations where appointment_id=p_appointment_id and created_by=app.current_user_id() and status='open';
  for v_line in select btrim(x) from regexp_split_to_table(v_a.order_text,E'[\\n\\r]+') x where length(btrim(x))>15 loop
    insert into court.appointment_obligations(tenant_id,matter_id,appointment_id,clause_number,clause_category,clause_text,created_by)
    values(v_a.tenant_id,v_a.matter_id,v_a.id,(v_count+1)::text,
      case when v_line~*'report|file|submit' then 'reporting' when v_line~*'shall not|may not|limited|prohibit' then 'limitation'
           when v_line~*'compensation|fee|invoice' then 'compensation' when v_line~*'confidential|sealed|privilege' then 'confidentiality'
           when v_line~*'access|inspect|obtain' then 'access' else 'duty' end,v_line,app.current_user_id());
    v_count:=v_count+1;
  end loop;return v_count;
end;$$;
revoke all on function court.parse_appointment_order(uuid) from public,anon;
grant execute on function court.parse_appointment_order(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- 7. Deterministic report assembly with claim lineage
-- --------------------------------------------------------------------------

alter table reporting.report_sections add column if not exists generation_source text not null default 'manual';

create or replace function reporting.assemble_report(p_report_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,pg_temp,reporting,investigation,evidence,calculations,core,app as $$
declare v_r reporting.reports%rowtype;v_m core.matters%rowtype;v_section uuid;v_count int:=0;begin
  select * into v_r from reporting.reports where id=p_report_id;
  if not found or not app.has_matter_access(v_r.matter_id,'contribute') then raise exception 'report not found or insufficient access' using errcode='42501';end if;
  select * into v_m from core.matters where id=v_r.matter_id;
  delete from reporting.report_claim_links where report_section_id in(select id from reporting.report_sections where report_id=p_report_id and generation_source='assembled_v1');
  delete from reporting.report_sections where report_id=p_report_id and generation_source='assembled_v1';

  insert into reporting.report_sections(tenant_id,matter_id,report_id,section_number,heading,body,sort_order,generation_source,created_by)
  values(v_r.tenant_id,v_r.matter_id,p_report_id,'1','Executive summary',
    format('%s (%s) is an active %s matter. This generated working draft contains record-backed findings and calculations and requires professional review before issuance.',v_m.matter_name,v_m.matter_number,v_m.matter_type),1,'assembled_v1',app.current_user_id());v_count:=v_count+1;
  insert into reporting.report_sections(tenant_id,matter_id,report_id,section_number,heading,body,sort_order,generation_source,created_by)
  values(v_r.tenant_id,v_r.matter_id,p_report_id,'2','Authority, scope, and methodology',
    format('Jurisdiction: %s. Confidentiality: %s. Report evidence cutoff: %s. Calculation cutoff: %s.',coalesce(v_m.jurisdiction,'not specified'),v_r.confidentiality,coalesce(v_r.evidence_cutoff::text,'not specified'),coalesce(v_r.calculation_cutoff::text,'not specified')),2,'assembled_v1',app.current_user_id());v_count:=v_count+1;
  insert into reporting.report_sections(tenant_id,matter_id,report_id,section_number,heading,body,sort_order,generation_source,created_by)
  select v_r.tenant_id,v_r.matter_id,p_report_id,'3','Evidence reviewed',coalesce(string_agg(format('%s — %s (%s)',e.human_evidence_no,e.title,e.evidence_type),E'\n' order by e.human_evidence_no),'No evidence items are recorded.'),3,'assembled_v1',app.current_user_id()
  from evidence.evidence_items e where e.matter_id=v_r.matter_id;v_count:=v_count+1;
  insert into reporting.report_sections(tenant_id,matter_id,report_id,section_number,heading,body,sort_order,generation_source,created_by)
  select v_r.tenant_id,v_r.matter_id,p_report_id,'4','Findings',coalesce(string_agg(format('%s [%s] — %s',f.title,f.conclusion_status,coalesce(f.methodology,'Methodology not recorded')),E'\n\n' order by f.created_at),'No findings are recorded.'),4,'assembled_v1',app.current_user_id()
  from investigation.findings f where f.matter_id=v_r.matter_id returning id into v_section;v_count:=v_count+1;
  insert into reporting.report_claim_links(tenant_id,matter_id,report_section_id,claim_text,statement_type,finding_id,created_by)
  select v_r.tenant_id,v_r.matter_id,v_section,f.title,'finding',f.id,app.current_user_id() from investigation.findings f where f.matter_id=v_r.matter_id;
  insert into reporting.report_sections(tenant_id,matter_id,report_id,section_number,heading,body,sort_order,generation_source,created_by)
  select v_r.tenant_id,v_r.matter_id,p_report_id,'5','Financial impact and calculations',coalesce(string_agg(format('%s %s — %s',coalesce(cr.output_currency,'USD'),coalesce(cr.output_total,0),coalesce(cr.narrative,cr.run_name)),E'\n\n' order by cr.created_at),'No completed calculations are recorded.'),5,'assembled_v1',app.current_user_id()
  from calculations.calculation_runs cr where cr.matter_id=v_r.matter_id and cr.status in('completed','reviewed','approved') returning id into v_section;v_count:=v_count+1;
  insert into reporting.report_claim_links(tenant_id,matter_id,report_section_id,claim_text,statement_type,calculation_run_ref,created_by)
  select v_r.tenant_id,v_r.matter_id,v_section,coalesce(cr.narrative,cr.run_name),'calculation',cr.id,app.current_user_id() from calculations.calculation_runs cr where cr.matter_id=v_r.matter_id and cr.status in('completed','reviewed','approved');
  insert into reporting.report_sections(tenant_id,matter_id,report_id,section_number,heading,body,sort_order,generation_source,created_by)
  values(v_r.tenant_id,v_r.matter_id,p_report_id,'6','Limitations and required review','This is an automatically assembled working draft. Every statement, methodology, legal characterization, calculation assumption, and cited source must be independently reviewed before approval or issuance.',6,'assembled_v1',app.current_user_id());v_count:=v_count+1;
  update reporting.reports set status='drafting',updated_by=app.current_user_id() where id=p_report_id and status='outline';
  return v_count;
end;$$;
revoke all on function reporting.assemble_report(uuid) from public,anon;
grant execute on function reporting.assemble_report(uuid) to authenticated;

commit;
