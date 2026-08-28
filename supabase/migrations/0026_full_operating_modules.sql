-- Treasury, GRC, guided ingestion, report collaboration, court operations,
-- and durable job-control records for the complete practitioner workflow.
begin;

create schema if not exists treasury;
create schema if not exists grc;
create schema if not exists operations;
grant usage on schema treasury,grc,operations to authenticated,service_role;
alter default privileges in schema treasury,grc,operations grant select,insert,update,delete on tables to authenticated,service_role;

-- Treasury governance -------------------------------------------------------
create table treasury.profiles(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),
 reporting_currency char(3) not null default 'USD',policy_summary text,status text not null default 'draft' check(status in('draft','active','suspended','closed')),
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id)
);
create table treasury.authority_limits(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),
 principal_ref text not null,role_name text not null,account_id uuid references canonical.bank_accounts(id),currency char(3) not null default 'USD',single_payment_limit numeric(20,4),daily_limit numeric(20,4),
 requires_dual_approval boolean not null default true,effective_from date,effective_to date,status text not null default 'active',created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table treasury.bank_access_reviews(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),account_id uuid not null references canonical.bank_accounts(id),
 user_ref text not null,access_role text not null,last_login_at timestamptz,review_status text not null default 'pending' check(review_status in('pending','certified','remove','suspended')),
 reviewer_note text,reviewed_by uuid,reviewed_at timestamptz,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table treasury.restricted_funds(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),account_id uuid references canonical.bank_accounts(id),
 restriction_name text not null,restriction_basis text,opening_amount numeric(20,4) not null default 0,currency char(3) not null default 'USD',effective_from date,effective_to date,
 status text not null default 'active',created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table treasury.beneficiary_changes(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),beneficiary_entity_id uuid references canonical.entities(id),
 old_account_token text,new_account_token text,changed_at timestamptz not null,changed_by_ref text,review_status text not null default 'pending' check(review_status in('pending','validated','rejected','escalated')),
 reviewer_note text,reviewed_by uuid,reviewed_at timestamptz,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table treasury.reconciliations(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),account_id uuid references canonical.bank_accounts(id),
 period_end date not null,bank_balance numeric(20,4) not null,ledger_balance numeric(20,4) not null,documented_adjustments numeric(20,4) not null default 0,tolerance numeric(20,4) not null default 0,
 variance numeric(20,4) generated always as(bank_balance-ledger_balance-documented_adjustments) stored,
 result text generated always as(case when abs(bank_balance-ledger_balance-documented_adjustments)<=tolerance then 'balanced' else 'out_of_balance' end) stored,
 status text not null default 'prepared' check(status in('prepared','reviewed','approved','rejected')),prepared_by uuid,reviewed_by uuid,reviewed_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,account_id,period_end)
);
create table treasury.exceptions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),payment_id uuid references canonical.payments(id),account_id uuid references canonical.bank_accounts(id),
 exception_type text not null,severity text not null check(severity in('low','medium','high','critical')),amount numeric(20,4),explanation text not null,
 disposition text not null default 'open' check(disposition in('open','explained','control_deficiency','suspicious','remediated','closed')),
 reviewer_note text,reviewed_by uuid,reviewed_at timestamptz,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,
 unique(matter_id,payment_id,exception_type)
);

-- GRC and audit -------------------------------------------------------------
create table grc.risks(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),risk_code text not null,title text not null,description text,
 category text,inherent_likelihood numeric(5,2) not null default 1,inherent_impact numeric(5,2) not null default 1,residual_likelihood numeric(5,2),residual_impact numeric(5,2),owner_ref text,status text not null default 'open',
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,risk_code)
);
create table grc.controls(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),control_code text not null,title text not null,description text,
 control_type text not null default 'preventive',frequency text,owner_ref text,status text not null default 'designed' check(status in('designed','implemented','inactive','retired')),
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,control_code)
);
create table grc.risk_control_links(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),risk_id uuid not null references grc.risks(id),control_id uuid not null references grc.controls(id),
 coverage_weight numeric(5,2) not null default 1 check(coverage_weight between 0 and 1),created_at timestamptz not null default now(),created_by uuid,unique(risk_id,control_id)
);
create table grc.audit_programs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),title text not null,objective text,population_definition text,
 sample_method text not null default 'full_population',sample_size int,period_start date,period_end date,materiality numeric(20,4),status text not null default 'draft' check(status in('draft','approved','in_progress','completed','archived')),
 approved_by uuid,approved_at timestamptz,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table grc.control_tests(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),audit_program_id uuid references grc.audit_programs(id),control_id uuid not null references grc.controls(id),
 procedure_text text not null,population_count int not null default 0,sample_count int not null default 0,exception_count int not null default 0,population_amount numeric(20,4) not null default 0,exception_amount numeric(20,4) not null default 0,
 exception_rate numeric(9,6),monetary_exception_rate numeric(9,6),recurrence_score numeric(5,2) not null default 0,residual_risk_score numeric(9,4),result text not null default 'in_progress' check(result in('in_progress','effective','exception','deficiency')),
 status text not null default 'draft' check(status in('draft','performed','reviewed','approved','rejected')),performed_by uuid,reviewed_by uuid,reviewed_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table grc.test_exceptions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),control_test_id uuid not null references grc.control_tests(id),description text not null,amount numeric(20,4) not null default 0,
 severity text not null default 'medium',disposition text not null default 'open',evidence_id uuid references evidence.evidence_items(id),created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table grc.remediation_actions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),risk_id uuid references grc.risks(id),control_id uuid references grc.controls(id),control_test_id uuid references grc.control_tests(id),
 title text not null,action_plan text not null,owner_ref text,due_at timestamptz not null,priority text not null default 'medium',status text not null default 'open' check(status in('open','in_progress','submitted','validated','reopened','closed','overdue')),
 management_response text,validation_note text,evidence_id uuid references evidence.evidence_items(id),validated_by uuid,validated_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);

-- Guided ingestion and approval --------------------------------------------
create table evidence.ingestion_runs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),data_source_id uuid references evidence.data_sources(id),dataset_version_id uuid references evidence.dataset_versions(id),
 source_type text not null,source_system text,mapping_version_id uuid references mapping.mapping_versions(id),reporting_period daterange,status text not null default 'registered' check(status in('registered','queued','parsing','mapping','validating','exception_review','ready_for_approval','approved','failed')),
 raw_row_count bigint not null default 0,canonical_row_count bigint not null default 0,rejected_row_count bigint not null default 0,started_at timestamptz,completed_at timestamptz,error_detail text,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);

-- Reporting collaboration and controlled distribution ----------------------
create table reporting.report_comments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),report_id uuid not null references reporting.reports(id),report_section_id uuid references reporting.report_sections(id),
 parent_comment_id uuid references reporting.report_comments(id),comment_text text not null,status text not null default 'open' check(status in('open','resolved','withdrawn')),resolved_by uuid,resolved_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table reporting.report_editions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),report_id uuid not null references reporting.reports(id),
 edition_type text not null check(edition_type in('internal','counsel','court','regulator','external')),confidentiality_ceiling core.confidentiality_level not null,redaction_rules jsonb not null default '{}'::jsonb,status text not null default 'draft',output_hash bytea,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(report_id,edition_type)
);
create table reporting.report_approvals(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),report_id uuid not null references reporting.reports(id),
 approval_role text not null,decision text not null check(decision in('approved','rejected','revision_requested')),decision_note text,decided_by uuid not null,decided_at timestamptz not null default now(),report_snapshot_hash bytea not null,
 created_at timestamptz not null default now(),created_by uuid
);
create table reporting.distribution_log(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),report_id uuid not null references reporting.reports(id),report_edition_id uuid references reporting.report_editions(id),
 recipient_name text not null,recipient_address text,delivery_method text not null,delivery_status text not null default 'prepared',authorized_by uuid,distributed_by uuid,distributed_at timestamptz,acknowledged_at timestamptz,output_hash bytea,
 created_at timestamptz not null default now(),created_by uuid
);
create table reporting.signatures(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),report_id uuid not null references reporting.reports(id),signer_user_id uuid not null,signer_role text not null,
 signature_method text not null default 'authenticated_attestation',signed_at timestamptz not null default now(),signed_hash bytea not null,created_at timestamptz not null default now(),created_by uuid
);

-- Court operations ----------------------------------------------------------
create table court.authorized_contacts(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),appointment_id uuid references court.appointments(id),name text not null,organization text,role text,
 contact_protocol text,status text not null default 'authorized',created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table court.neutrality_log(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),appointment_id uuid references court.appointments(id),contact_id uuid references court.authorized_contacts(id),
 occurred_at timestamptz not null,contact_type text not null,participants text,subject text not null,authorized_scope_basis text,protocol_status text not null default 'compliant' check(protocol_status in('compliant','review_required','breach')),review_note text,
 created_at timestamptz not null default now(),created_by uuid
);
create table court.assets(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),appointment_id uuid references court.appointments(id),asset_number text not null,asset_type text not null,description text,
 location text,custodian text,estimated_value numeric(20,4),currency char(3) not null default 'USD',status text not null default 'identified',evidence_id uuid references evidence.evidence_items(id),
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,asset_number)
);
create table court.fees_expenses(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),appointment_id uuid references court.appointments(id),professional_ref text not null,entry_date date not null,
 entry_type text not null check(entry_type in('fee','expense')),description text not null,hours numeric(9,2),rate numeric(20,4),amount numeric(20,4) not null,currency char(3) not null default 'USD',status text not null default 'submitted' check(status in('submitted','reviewed','approved','rejected','paid')),
 reviewed_by uuid,reviewed_at timestamptz,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);

-- Durable background jobs ---------------------------------------------------
create table operations.jobs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid references core.matters(id),job_type text not null,queue_name text not null,payload jsonb not null default '{}'::jsonb,
 status text not null default 'queued' check(status in('queued','leased','running','succeeded','failed','dead_letter','cancelled')),priority int not null default 100,attempt_count int not null default 0,max_attempts int not null default 5,
 available_at timestamptz not null default now(),leased_until timestamptz,worker_ref text,last_error text,result jsonb,started_at timestamptz,finished_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create index on operations.jobs(status,available_at,priority);

-- Common RLS and stamping ---------------------------------------------------
do $$ declare s text;t text;begin
 for s,t in select * from (values
 ('treasury','profiles'),('treasury','authority_limits'),('treasury','bank_access_reviews'),('treasury','restricted_funds'),('treasury','beneficiary_changes'),('treasury','reconciliations'),('treasury','exceptions'),
 ('grc','risks'),('grc','controls'),('grc','risk_control_links'),('grc','audit_programs'),('grc','control_tests'),('grc','test_exceptions'),('grc','remediation_actions'),
 ('evidence','ingestion_runs'),('reporting','report_comments'),('reporting','report_editions'),('reporting','report_approvals'),('reporting','distribution_log'),('reporting','signatures'),
 ('court','authorized_contacts'),('court','neutrality_log'),('court','assets'),('court','fees_expenses'),('operations','jobs')) v(s,t)
 loop
  execute format('alter table %I.%I enable row level security',s,t);execute format('alter table %I.%I force row level security',s,t);
  execute format('create policy matter_select on %I.%I for select to authenticated using(app.has_matter_access(matter_id,''read''))',s,t);
  execute format('create policy matter_insert on %I.%I for insert to authenticated with check(app.has_matter_access(matter_id,''contribute''))',s,t);
  execute format('create policy matter_update on %I.%I for update to authenticated using(app.has_matter_access(matter_id,''contribute'')) with check(app.has_matter_access(matter_id,''contribute''))',s,t);
  if t not in('risk_control_links','report_approvals','distribution_log','signatures','neutrality_log') then execute format('create trigger tg_stamp before insert or update on %I.%I for each row execute function app.tg_stamp_row()',s,t);end if;
 end loop;
end $$;
create trigger tg_approval_immutable before update or delete on reporting.report_approvals for each row execute function app.tg_deny_mutation();
create trigger tg_distribution_immutable before update or delete on reporting.distribution_log for each row execute function app.tg_deny_mutation();
create trigger tg_signature_immutable before update or delete on reporting.signatures for each row execute function app.tg_deny_mutation();
create trigger tg_neutrality_immutable before update or delete on court.neutrality_log for each row execute function app.tg_deny_mutation();

-- Governed workflow functions ----------------------------------------------
create or replace function treasury.run_payment_review(p_matter_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp,treasury,canonical,app as $$
declare v_tenant uuid;v_sod int:=0;v_limit int:=0;
begin
 if not app.has_matter_access(p_matter_id,'contribute') then raise exception 'Contribute access required' using errcode='42501';end if;
 select tenant_id into v_tenant from core.matters where id=p_matter_id;
 insert into treasury.exceptions(tenant_id,matter_id,payment_id,account_id,exception_type,severity,amount,explanation,created_by)
 select v_tenant,p_matter_id,p.id,p.from_account_id,'segregation_of_duties',case when coalesce(p.amount_original,0)>=100000 then 'critical' else 'high' end,p.amount_original,
 'Payment initiator and approver are the same identity.',app.current_user_id() from canonical.payments p where p.matter_id=p_matter_id and nullif(p.initiator_user_ref,'')=nullif(p.approver_user_ref,'')
 on conflict(matter_id,payment_id,exception_type) do nothing;get diagnostics v_sod=row_count;
 insert into treasury.exceptions(tenant_id,matter_id,payment_id,account_id,exception_type,severity,amount,explanation,created_by)
 select v_tenant,p_matter_id,p.id,p.from_account_id,'authority_limit_exceeded','high',p.amount_original,'Payment exceeds the active single-payment authority limit.',app.current_user_id()
 from canonical.payments p where p.matter_id=p_matter_id and exists(select 1 from treasury.authority_limits l where l.matter_id=p_matter_id and l.principal_ref=p.approver_user_ref and (l.account_id is null or l.account_id=p.from_account_id) and l.status='active' and p.amount_original>l.single_payment_limit)
 on conflict(matter_id,payment_id,exception_type) do nothing;get diagnostics v_limit=row_count;
 return jsonb_build_object('sod_exceptions_created',v_sod,'limit_exceptions_created',v_limit);
end;$$;

create or replace function grc.finalize_control_test(p_test_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp,grc,app as $$
declare v grc.control_tests%rowtype;v_er numeric;v_mer numeric;v_rr numeric;
begin select * into v from grc.control_tests where id=p_test_id;
 if not found or not app.has_matter_access(v.matter_id,'approve') then raise exception 'Approve access required' using errcode='42501';end if;
 v_er:=case when v.sample_count=0 then 0 else v.exception_count::numeric/v.sample_count end;
 v_mer:=case when v.population_amount=0 then 0 else v.exception_amount/v.population_amount end;
 v_rr:=least(25,round((v_er*40+v_mer*40+v.recurrence_score*4)::numeric,4));
 update grc.control_tests set exception_rate=v_er,monetary_exception_rate=v_mer,residual_risk_score=v_rr,
 result=case when v.exception_count=0 then 'effective' when v_rr>=15 then 'deficiency' else 'exception' end,status='reviewed',reviewed_by=app.current_user_id(),reviewed_at=now() where id=p_test_id;
 if v.exception_count>0 then insert into grc.remediation_actions(tenant_id,matter_id,control_id,control_test_id,title,action_plan,due_at,priority,created_by)
 values(v.tenant_id,v.matter_id,v.control_id,v.id,'Remediate control-test exceptions','Owner must document corrective action and submit supporting evidence.',now()+interval '30 days',case when v_rr>=15 then 'critical' else 'high' end,app.current_user_id());end if;
 return jsonb_build_object('exception_rate',v_er,'monetary_exception_rate',v_mer,'residual_risk_score',v_rr);
end;$$;

create or replace function evidence.approve_dataset_for_analytics(p_dataset_id uuid,p_note text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,evidence,quality,app as $$
declare v evidence.dataset_versions%rowtype;v_id uuid;
begin select * into v from evidence.dataset_versions where id=p_dataset_id;
 if not found or not app.has_matter_access(v.matter_id,'approve') then raise exception 'Approve access required' using errcode='42501';end if;
 if exists(select 1 from quality.mapping_exceptions e where e.dataset_version_id=v.id and e.exception_status in('open','in_review') and e.required_action in('block_approval','fail_validation','quarantine','suspend_mapping')) then raise exception 'Blocking mapping exceptions remain' using errcode='23514';end if;
 if exists(select 1 from quality.reconciliations r where r.dataset_version_id=v.id and r.result='out_of_balance') then raise exception 'Out-of-balance reconciliations remain' using errcode='23514';end if;
 insert into quality.data_quality_attestations(tenant_id,matter_id,dataset_version_id,readiness_status,attested_by,attestation_notes)
 values(v.tenant_id,v.matter_id,v.id,'approved',app.current_user_id(),coalesce(nullif(p_note,''),'Dataset reviewed and approved for analytics.')) returning id into v_id;
 update evidence.dataset_versions set readiness_status='approved' where id=v.id;
 update evidence.ingestion_runs set status='approved',completed_at=coalesce(completed_at,now()) where dataset_version_id=v.id;
 return v_id;
end;$$;

create or replace function operations.enqueue_job(p_matter_id uuid,p_job_type text,p_payload jsonb default '{}'::jsonb,p_priority int default 100)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,operations,app as $$
declare v_tenant uuid;v_id uuid;v_queue text;
begin if not app.has_matter_access(p_matter_id,'contribute') then raise exception 'Contribute access required' using errcode='42501';end if;
 select tenant_id into v_tenant from core.matters where id=p_matter_id;v_queue:=case when p_job_type in('ingestion','hashing','ocr','analytics','alerts','report_compilation','notifications','anchoring') then p_job_type else 'analytics' end;
 insert into operations.jobs(tenant_id,matter_id,job_type,queue_name,payload,priority,created_by) values(v_tenant,p_matter_id,p_job_type,v_queue,p_payload,p_priority,app.current_user_id()) returning id into v_id;
 perform app.enqueue(v_queue,v_tenant,jsonb_build_object('job_id',v_id,'job_type',p_job_type,'payload',p_payload),p_matter_id);return v_id;
end;$$;

-- Source-backed dashboard views --------------------------------------------
create or replace view analytics.v_treasury_dashboard with(security_invoker=true) as
select m.id matter_id,m.tenant_id,
 coalesce((select sum(case when t.debit_credit_indicator='debit' then -coalesce(t.amount_base,t.amount_original) else coalesce(t.amount_base,t.amount_original) end) from canonical.transactions t where t.matter_id=m.id and t.record_status='active'),0) cash_position,
 (select count(*) from canonical.bank_accounts a where a.matter_id=m.id and a.record_status='active') bank_accounts,
 (select count(*) from treasury.exceptions e where e.matter_id=m.id and e.disposition in('open','control_deficiency','suspicious')) open_exceptions,
 (select count(*) from treasury.reconciliations r where r.matter_id=m.id and r.result='out_of_balance') unreconciled_accounts,
 (select count(*) from treasury.bank_access_reviews a where a.matter_id=m.id and a.review_status='pending') access_reviews_due,
 (select coalesce(sum(abs(t.amount)),0) from treasury.exceptions t where t.matter_id=m.id and t.disposition in('open','control_deficiency','suspicious')) exception_exposure
from core.matters m;
create or replace view analytics.v_grc_dashboard with(security_invoker=true) as
select m.id matter_id,m.tenant_id,
 (select count(*) from grc.risks r where r.matter_id=m.id and r.status='open') open_risks,
 (select count(*) from grc.controls c where c.matter_id=m.id and c.status='implemented') implemented_controls,
 (select count(*) from grc.control_tests t where t.matter_id=m.id and t.result in('exception','deficiency')) failed_tests,
 (select count(*) from grc.remediation_actions a where a.matter_id=m.id and a.status not in('closed','validated') and a.due_at<now()) overdue_actions,
 (select coalesce(avg(t.residual_risk_score),0) from grc.control_tests t where t.matter_id=m.id and t.status in('reviewed','approved')) average_residual_risk
from core.matters m;

grant select on all tables in schema treasury,grc,operations to authenticated,service_role;
grant insert,update on all tables in schema treasury,grc,operations to authenticated,service_role;
grant select,insert,update on evidence.ingestion_runs,reporting.report_comments,reporting.report_editions,court.authorized_contacts,court.assets,court.fees_expenses to authenticated;
grant select,insert on reporting.report_approvals,reporting.distribution_log,reporting.signatures,court.neutrality_log to authenticated;
grant select on analytics.v_treasury_dashboard,analytics.v_grc_dashboard to authenticated,service_role;
grant execute on function treasury.run_payment_review(uuid),grc.finalize_control_test(uuid),evidence.approve_dataset_for_analytics(uuid,text),operations.enqueue_job(uuid,text,jsonb,int) to authenticated,service_role;

commit;
