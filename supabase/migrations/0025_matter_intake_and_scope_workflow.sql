-- Matter intake, module activation, authority extraction, and scope approval.
begin;

create table core.engagements (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references core.tenants(id),
  matter_id uuid not null references core.matters(id), engagement_type text not null,
  risk_level text not null default 'standard' check(risk_level in('low','standard','high','critical')),
  status text not null default 'intake' check(status in('intake','scope_review','active','suspended','closed')),
  retention_category text not null default 'matter_standard', legal_hold_default boolean not null default true,
  activated_at timestamptz, closed_at timestamptz, created_at timestamptz not null default now(),created_by uuid,
  updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id)
);
create table core.matter_modules (
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),
  module_code text not null check(module_code in('fraud_examination','treasury','grc_audit','litigation','court_receivership','claims')),
  enabled boolean not null default true,activated_at timestamptz,created_at timestamptz not null default now(),created_by uuid,
  updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,module_code)
);
create table core.conflict_attestations (
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),
  attestation text not null,conflict_identified boolean not null default false,resolution text,attested_by uuid not null,attested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),created_by uuid
);
create table core.scope_approvals (
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),
  scope_version int not null,decision text not null check(decision in('approved','rejected','revision_requested')),
  scope_snapshot jsonb not null,authority_snapshot jsonb not null,decision_note text,decided_by uuid not null,decided_at timestamptz not null default now(),
  snapshot_hash bytea not null,created_at timestamptz not null default now(),created_by uuid,unique(matter_id,scope_version)
);
alter table core.authority_instruments add column if not exists extraction_status text not null default 'not_processed';
alter table core.authority_instruments add column if not exists extraction_metadata jsonb not null default '{}'::jsonb;
alter table core.scope_items add column if not exists source_type text not null default 'manual';
alter table core.reporting_obligations add column if not exists source_type text not null default 'manual';
alter table core.deadlines add column if not exists source_authority_id uuid references core.authority_instruments(id);
create unique index if not exists deadlines_authority_expiration_uniq
  on core.deadlines(source_authority_id,deadline_type) where source_authority_id is not null;

do $$ declare t text;begin foreach t in array array['engagements','matter_modules','conflict_attestations','scope_approvals'] loop
  execute format('alter table core.%I enable row level security',t);execute format('alter table core.%I force row level security',t);
  execute format('create policy sel on core.%I for select to authenticated using(app.has_matter_access(matter_id,''read''))',t);
  execute format('create policy ins on core.%I for insert to authenticated with check(app.has_matter_access(matter_id,''contribute''))',t);
end loop;end $$;
create policy upd on core.engagements for update to authenticated using(app.has_matter_access(matter_id,'matter_admin')) with check(app.has_matter_access(matter_id,'matter_admin'));
create policy upd on core.matter_modules for update to authenticated using(app.has_matter_access(matter_id,'matter_admin')) with check(app.has_matter_access(matter_id,'matter_admin'));
create trigger tg_stamp before insert or update on core.engagements for each row execute function app.tg_stamp_row();
create trigger tg_stamp before insert or update on core.matter_modules for each row execute function app.tg_stamp_row();
create trigger tg_deny_mutation before update or delete on core.conflict_attestations for each row execute function app.tg_deny_mutation();
create trigger tg_deny_mutation before update or delete on core.scope_approvals for each row execute function app.tg_deny_mutation();

create or replace function core.provision_matter_intake(
  p_tenant_id uuid,p_matter_name text,p_matter_type text,p_jurisdiction text,
  p_confidentiality core.confidentiality_level,p_risk_level text,p_modules jsonb,
  p_parties jsonb default '[]'::jsonb,p_authority jsonb default '{}'::jsonb,
  p_deadlines jsonb default '[]'::jsonb,p_conflict_attestation text default null,
  p_conflict_identified boolean default false,p_retention_category text default 'matter_standard'
)
returns table(id uuid,matter_number text) language plpgsql security definer
set search_path=pg_catalog,pg_temp,core,app as $$
declare v_m record;v_user uuid:=app.current_user_id();v_item jsonb;v_authority uuid;v_module text;
begin
  if jsonb_typeof(p_modules)<>'array' or jsonb_array_length(p_modules)=0 then raise exception 'At least one service module is required' using errcode='22023';end if;
  if p_risk_level not in('low','standard','high','critical') then raise exception 'Invalid risk level' using errcode='22023';end if;
  select * into v_m from core.provision_matter(p_tenant_id,p_matter_name,p_matter_type,p_confidentiality,null);
  update core.matters set jurisdiction=nullif(btrim(p_jurisdiction),''),status='intake',lead_user_id=v_user where core.matters.id=v_m.id;
  insert into core.engagements(tenant_id,matter_id,engagement_type,risk_level,status,retention_category,created_by)
  values(p_tenant_id,v_m.id,p_matter_type,p_risk_level,'intake',coalesce(nullif(p_retention_category,''),'matter_standard'),v_user);
  for v_module in select jsonb_array_elements_text(p_modules) loop
    insert into core.matter_modules(tenant_id,matter_id,module_code,created_by) values(p_tenant_id,v_m.id,v_module,v_user);
  end loop;
  if jsonb_typeof(p_parties)='array' then for v_item in select * from jsonb_array_elements(p_parties) loop
    if nullif(btrim(v_item->>'party_name'),'') is not null then insert into core.matter_parties(tenant_id,matter_id,party_name,party_role,counsel,created_by)
      values(p_tenant_id,v_m.id,btrim(v_item->>'party_name'),coalesce(nullif(v_item->>'party_role',''),'other'),nullif(v_item->>'counsel',''),v_user);end if;
  end loop;end if;
  if nullif(btrim(p_authority->>'authority_type'),'') is not null then
    insert into core.authority_instruments(tenant_id,matter_id,authority_type,issuing_party,effective_date,expiration_date,mandate,created_by)
    values(p_tenant_id,v_m.id,p_authority->>'authority_type',nullif(p_authority->>'issuing_party',''),nullif(p_authority->>'effective_date','')::date,
      nullif(p_authority->>'expiration_date','')::date,nullif(p_authority->>'mandate',''),v_user) returning core.authority_instruments.id into v_authority;
  end if;
  if jsonb_typeof(p_deadlines)='array' then for v_item in select * from jsonb_array_elements(p_deadlines) loop
    if nullif(v_item->>'due_at','') is not null then insert into core.deadlines(tenant_id,matter_id,deadline_type,due_at,owner_user_id,created_by)
      values(p_tenant_id,v_m.id,coalesce(nullif(v_item->>'deadline_type',''),'reporting'),(v_item->>'due_at')::timestamptz,v_user,v_user);end if;
  end loop;end if;
  insert into core.conflict_attestations(tenant_id,matter_id,attestation,conflict_identified,resolution,attested_by,created_by)
  values(p_tenant_id,v_m.id,coalesce(nullif(btrim(p_conflict_attestation),''),'No known conflict identified at intake.'),p_conflict_identified,
    case when p_conflict_identified then 'Pending documented resolution before scope approval.' end,v_user,v_user);
  return query select v_m.id,v_m.matter_number;
end;$$;
revoke all on function core.provision_matter_intake(uuid,text,text,text,core.confidentiality_level,text,jsonb,jsonb,jsonb,jsonb,text,boolean,text) from public,anon;
grant execute on function core.provision_matter_intake(uuid,text,text,text,core.confidentiality_level,text,jsonb,jsonb,jsonb,jsonb,text,boolean,text) to authenticated;

create or replace function core.parse_authority_instrument(p_authority_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp,core,app,extensions as $$
declare v_a core.authority_instruments%rowtype;v_line text;v_scope int:=0;v_reports int:=0;v_deadlines int:=0;v_category text;
begin
  select * into v_a from core.authority_instruments where id=p_authority_id;
  if not found or not app.has_matter_access(v_a.matter_id,'contribute') then raise exception 'authority not found or insufficient access' using errcode='42501';end if;
  if nullif(btrim(v_a.mandate),'') is null then raise exception 'Authority mandate text is required for extraction' using errcode='22023';end if;
  delete from core.scope_items where authority_id=v_a.id and source_type='authority_parser_v1';
  delete from core.reporting_obligations where authority_id=v_a.id and source_type='authority_parser_v1';
  for v_line in select btrim(x) from regexp_split_to_table(v_a.mandate,E'[\\n\\r;]+') x where length(btrim(x))>12 loop
    v_category:=case when v_line~*'shall not|may not|prohibit|limit|except' then 'limitation' when v_line~*'report|file|submit' then 'report'
      when v_line~*'deadline|due|within [0-9]+ days' then 'deadline' when v_line~*'fee|compensation|expense' then 'compensation'
      when v_line~*'access|inspect|obtain|records' then 'access' else 'duty' end;
    insert into core.scope_items(tenant_id,matter_id,authority_id,clause_category,clause_text,normalized_requirement,source_type,created_by)
    values(v_a.tenant_id,v_a.matter_id,v_a.id,v_category,v_line,lower(regexp_replace(v_line,'\\s+',' ','g')),'authority_parser_v1',app.current_user_id());v_scope:=v_scope+1;
    if v_category='report' then insert into core.reporting_obligations(tenant_id,matter_id,authority_id,recipient,report_type,frequency,source_type,created_by)
      values(v_a.tenant_id,v_a.matter_id,v_a.id,coalesce(v_a.issuing_party,'Appointing authority'),'authority report',
        case when v_line~*'monthly|30 days' then 'monthly' when v_line~*'quarter' then 'quarterly' else 'as ordered' end,'authority_parser_v1',app.current_user_id());v_reports:=v_reports+1;end if;
  end loop;
  if v_a.expiration_date is not null then
    insert into core.deadlines(tenant_id,matter_id,deadline_type,due_at,owner_user_id,source_authority_id,created_by)
    values(v_a.tenant_id,v_a.matter_id,'authority_expiration',v_a.expiration_date::timestamptz,app.current_user_id(),v_a.id,app.current_user_id())
    on conflict do nothing;
    get diagnostics v_deadlines=row_count;
  end if;
  update core.authority_instruments set extraction_status='completed',extraction_metadata=jsonb_build_object('parser','authority_parser_v1','scope_items',v_scope,'reporting_obligations',v_reports,'deadlines',v_deadlines,'processed_at',now()) where id=v_a.id;
  update core.engagements set status='scope_review' where matter_id=v_a.matter_id and status='intake';
  return jsonb_build_object('scope_items',v_scope,'reporting_obligations',v_reports,'deadlines',v_deadlines);
end;$$;
revoke all on function core.parse_authority_instrument(uuid) from public,anon;grant execute on function core.parse_authority_instrument(uuid) to authenticated;

create or replace function core.decide_scope(p_matter_id uuid,p_decision text,p_note text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,core,app,extensions as $$
declare v_tenant uuid;v_version int;v_scope jsonb;v_authority jsonb;v_id uuid;v_user uuid:=app.current_user_id();
begin
  if not app.has_matter_access(p_matter_id,'approve') then raise exception 'Approve access is required' using errcode='42501';end if;
  if p_decision not in('approved','rejected','revision_requested') then raise exception 'Invalid scope decision' using errcode='22023';end if;
  select tenant_id into v_tenant from core.matters where id=p_matter_id;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at),'[]'::jsonb) into v_scope from core.scope_items s where s.matter_id=p_matter_id and s.record_status='active';
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at),'[]'::jsonb) into v_authority from core.authority_instruments a where a.matter_id=p_matter_id and a.record_status='active';
  if p_decision='approved' and (jsonb_array_length(v_scope)=0 or jsonb_array_length(v_authority)=0) then raise exception 'An authority instrument and at least one scope item are required for approval' using errcode='23514';end if;
  select coalesce(max(scope_version),0)+1 into v_version from core.scope_approvals where matter_id=p_matter_id;
  insert into core.scope_approvals(tenant_id,matter_id,scope_version,decision,scope_snapshot,authority_snapshot,decision_note,decided_by,snapshot_hash,created_by)
  values(v_tenant,p_matter_id,v_version,p_decision,v_scope,v_authority,p_note,v_user,extensions.digest(convert_to(v_scope::text||v_authority::text||p_decision,'UTF8'),'sha256'),v_user) returning id into v_id;
  if p_decision='approved' then update core.matters set status='active' where id=p_matter_id;update core.engagements set status='active',activated_at=now() where matter_id=p_matter_id;
    update core.matter_modules set activated_at=coalesce(activated_at,now()) where matter_id=p_matter_id and enabled;end if;
  return v_id;
end;$$;
revoke all on function core.decide_scope(uuid,text,text) from public,anon;grant execute on function core.decide_scope(uuid,text,text) to authenticated;

create or replace view analytics.v_matter_readiness with(security_invoker=true) as
select m.id matter_id,m.tenant_id,m.status,
  exists(select 1 from core.authority_instruments a where a.matter_id=m.id and a.record_status='active') has_authority,
  exists(select 1 from core.scope_approvals sa where sa.matter_id=m.id and sa.decision='approved') scope_approved,
  (select count(*) from core.matter_modules mm where mm.matter_id=m.id and mm.enabled) enabled_modules,
  (select count(*) from evidence.dataset_versions dv where dv.matter_id=m.id and dv.record_status='active') datasets,
  (select count(*) from evidence.dataset_versions dv where dv.matter_id=m.id and dv.readiness_status='approved') approved_datasets,
  (select count(*) from quality.mapping_exceptions me where me.matter_id=m.id and me.exception_status in('open','in_review')) open_data_exceptions,
  (select count(*) from investigation.alerts al where al.matter_id=m.id and al.review_status<>'closed') open_alerts,
  (select count(*) from core.deadlines d where d.matter_id=m.id and not d.completed and d.due_at<now()) overdue_deadlines,
  (select count(*) from calculations.calculation_runs cr where cr.matter_id=m.id and cr.status='completed') calculations_awaiting_review,
  (select count(*) from reporting.reports r where r.matter_id=m.id and r.status not in('approved','issued','superseded')) draft_reports
from core.matters m;
grant select on analytics.v_matter_readiness to authenticated,service_role;

commit;
