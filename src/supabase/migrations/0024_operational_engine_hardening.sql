-- Follow-up hardening found during authenticated end-to-end validation.
begin;

-- Serialize version allocation so two editors cannot claim the same version.
create or replace function evidence.save_working_copy(p_evidence_file_id uuid,p_content text,p_change_note text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,evidence,core,app,extensions as $$
declare v_file evidence.evidence_files%rowtype;v_id uuid;v_version int;begin
  select * into v_file from evidence.evidence_files where id=p_evidence_file_id;
  if not found or not app.has_matter_access(v_file.matter_id,'contribute') then raise exception 'file not found or insufficient access' using errcode='42501';end if;
  if nullif(p_content,'') is null then raise exception 'working-copy content is required' using errcode='22023';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_evidence_file_id::text,0));
  select coalesce(max(version_number),0)+1 into v_version from evidence.document_working_copies where evidence_file_id=p_evidence_file_id;
  insert into evidence.document_working_copies(tenant_id,matter_id,evidence_file_id,version_number,content_text,change_note,content_sha256,created_by)
  values(v_file.tenant_id,v_file.matter_id,p_evidence_file_id,v_version,p_content,p_change_note,
    extensions.digest(convert_to(p_content,'UTF8'),'sha256'),app.current_user_id()) returning id into v_id;
  return v_id;
end;$$;

-- The third argument preserves the spec's explicit approved-adjustment term.
drop function quality.run_invoice_payment_reconciliation(uuid,numeric);
create function quality.run_invoice_payment_reconciliation(
  p_matter_id uuid,p_tolerance numeric default 0.01,p_approved_adjustments numeric default 0
)
returns uuid language plpgsql security definer
set search_path=pg_catalog,pg_temp,quality,canonical,core,app
as $$
declare v_tenant uuid;v_id uuid;v_invoice_total numeric;v_applied_total numeric;v_open_balance numeric;
begin
  if not app.has_matter_access(p_matter_id,'contribute') then raise exception 'contribute access required' using errcode='42501'; end if;
  select tenant_id into v_tenant from core.matters where id=p_matter_id;
  select coalesce(sum(case when invoice_status='credit_memo' then -abs(amount_original) else amount_original end),0)
    into v_invoice_total from canonical.invoices where matter_id=p_matter_id and record_status='active';
  select coalesce(sum(applied_amount),0) into v_applied_total from canonical.payment_invoice_links where matter_id=p_matter_id and record_status='active';
  v_open_balance:=v_invoice_total-v_applied_total+coalesce(p_approved_adjustments,0);
  insert into quality.reconciliations(tenant_id,matter_id,reconciliation_type,source_value,canonical_value,
    rejected_value,documented_adjustments,tolerance,result,created_by)
  values(v_tenant,p_matter_id,'invoice_to_payment',v_invoice_total,v_applied_total,0,coalesce(p_approved_adjustments,0),p_tolerance,
    case when abs(v_open_balance)<=p_tolerance then 'passed' else 'failed' end,app.current_user_id()) returning id into v_id;
  insert into quality.reconciling_items(tenant_id,matter_id,reconciliation_id,description,amount,disposition,
    originating_date,aging_days,escalation_band,source_evidence_id,created_by)
  select v_tenant,p_matter_id,v_id,
    format('Invoice %s: invoice/credit %s; applied %s',coalesce(i.invoice_number_raw,i.id::text),
      case when i.invoice_status='credit_memo' then -abs(coalesce(i.amount_original,0)) else coalesce(i.amount_original,0) end,
      coalesce(sum(l.applied_amount),0)),
    (case when i.invoice_status='credit_memo' then -abs(coalesce(i.amount_original,0)) else coalesce(i.amount_original,0) end)-coalesce(sum(l.applied_amount),0),
    'open',i.invoice_date,greatest(current_date-coalesce(i.invoice_date,current_date),0),
    case when current_date-coalesce(i.invoice_date,current_date)>=90 then '90+' when current_date-coalesce(i.invoice_date,current_date)>=60 then '60-89'
      when current_date-coalesce(i.invoice_date,current_date)>=30 then '30-59' when current_date-coalesce(i.invoice_date,current_date)>=7 then '7-29' else '0-6' end,
    i.source_evidence_id,app.current_user_id()
  from canonical.invoices i left join canonical.payment_invoice_links l on l.invoice_id=i.id and l.record_status='active'
  where i.matter_id=p_matter_id and i.record_status='active'
  group by i.id,i.invoice_number_raw,i.invoice_date,i.invoice_status,i.amount_original,i.source_evidence_id
  having abs((case when i.invoice_status='credit_memo' then -abs(coalesce(i.amount_original,0)) else coalesce(i.amount_original,0) end)-coalesce(sum(l.applied_amount),0))>p_tolerance;
  if coalesce(p_approved_adjustments,0)<>0 then
    insert into quality.reconciling_items(tenant_id,matter_id,reconciliation_id,description,amount,disposition,explanation,created_by)
    values(v_tenant,p_matter_id,v_id,'Practitioner-approved reconciliation adjustments',p_approved_adjustments,'explained',
      'Aggregate adjustment supplied to this governed reconciliation run; supporting evidence should be linked during review.',app.current_user_id());
  end if;
  return v_id;
end;$$;
revoke all on function quality.run_invoice_payment_reconciliation(uuid,numeric,numeric) from public,anon;
grant execute on function quality.run_invoice_payment_reconciliation(uuid,numeric,numeric) to authenticated;

-- Rebuild assembled drafts and create claim-lineage links for evidence,
-- findings, and completed calculations.
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
  from evidence.evidence_items e where e.matter_id=v_r.matter_id returning id into v_section;v_count:=v_count+1;
  insert into reporting.report_claim_links(tenant_id,matter_id,report_section_id,claim_text,statement_type,evidence_id,created_by)
  select v_r.tenant_id,v_r.matter_id,v_section,format('%s — %s',e.human_evidence_no,coalesce(e.title,'Untitled evidence')),'evidence',e.id,app.current_user_id()
  from evidence.evidence_items e where e.matter_id=v_r.matter_id;
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

commit;
