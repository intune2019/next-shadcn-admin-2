-- Practitioner casework: interviews, workpapers, timeline, exhibits, and tasks.
begin;
create schema if not exists workflow;
grant usage on schema workflow to authenticated,service_role;
alter default privileges in schema workflow grant select,insert,update,delete on tables to authenticated,service_role;

create table investigation.interviews(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),
 interview_date timestamptz,interviewee_name text not null,interviewee_role text,participants text,location_method text,purpose text,memorandum text,
 status text not null default 'planned' check(status in('planned','scheduled','completed','memorandum_draft','reviewed','approved','cancelled')),
 privilege_status text,recording_evidence_id uuid references evidence.evidence_items(id),approved_by uuid,approved_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table investigation.workpapers(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),workpaper_number text not null,title text not null,objective text,procedure_text text,analysis text,conclusion text,
 status text not null default 'draft' check(status in('draft','prepared','in_review','reviewed','approved','superseded')),prepared_by uuid,reviewed_by uuid,reviewed_at timestamptz,approved_by uuid,approved_at timestamptz,
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,workpaper_number)
);
create table investigation.workpaper_links(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),workpaper_id uuid not null references investigation.workpapers(id),
 evidence_id uuid references evidence.evidence_items(id),alert_id uuid references investigation.alerts(id),finding_id uuid references investigation.findings(id),calculation_run_id uuid references calculations.calculation_runs(id),interview_id uuid references investigation.interviews(id),link_note text,
 created_at timestamptz not null default now(),created_by uuid,
 check(num_nonnulls(evidence_id,alert_id,finding_id,calculation_run_id,interview_id)=1)
);
create table investigation.timeline_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),occurred_at timestamptz not null,event_type text not null,title text not null,description text,
 source_evidence_id uuid references evidence.evidence_items(id),transaction_id uuid references canonical.transactions(id),entity_id uuid references canonical.entities(id),confidence text not null default 'corroborated',
 created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create table reporting.exhibits(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),report_id uuid references reporting.reports(id),exhibit_number text not null,title text not null,description text,
 evidence_id uuid references evidence.evidence_items(id),calculation_run_id uuid references calculations.calculation_runs(id),status text not null default 'proposed' check(status in('proposed','prepared','reviewed','approved','issued')),
 output_hash bytea,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1,unique(matter_id,exhibit_number)
);
create table workflow.tasks(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),matter_id uuid not null references core.matters(id),title text not null,description text,task_type text not null default 'casework',priority text not null default 'medium',
 assigned_to uuid,due_at timestamptz,status text not null default 'open' check(status in('open','in_progress','blocked','submitted','completed','cancelled')),related_record_type text,related_record_id uuid,
 completed_at timestamptz,created_at timestamptz not null default now(),created_by uuid,updated_at timestamptz not null default now(),updated_by uuid,row_version int not null default 1
);
create index on workflow.tasks(matter_id,status,due_at);

do $$ declare s text;t text;begin for s,t in select * from(values('investigation','interviews'),('investigation','workpapers'),('investigation','workpaper_links'),('investigation','timeline_events'),('reporting','exhibits'),('workflow','tasks'))v(s,t) loop
 execute format('alter table %I.%I enable row level security',s,t);execute format('alter table %I.%I force row level security',s,t);
 execute format('create policy case_select on %I.%I for select to authenticated using(app.has_matter_access(matter_id,''read''))',s,t);
 execute format('create policy case_insert on %I.%I for insert to authenticated with check(app.has_matter_access(matter_id,''contribute''))',s,t);
 execute format('create policy case_update on %I.%I for update to authenticated using(app.has_matter_access(matter_id,''contribute'')) with check(app.has_matter_access(matter_id,''contribute''))',s,t);
 if t<>'workpaper_links' then execute format('create trigger tg_stamp before insert or update on %I.%I for each row execute function app.tg_stamp_row()',s,t);end if;
end loop;end $$;

create or replace function investigation.approve_workpaper(p_workpaper_id uuid,p_note text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,investigation,workflow,app as $$
declare w investigation.workpapers%rowtype;
begin select * into w from investigation.workpapers where id=p_workpaper_id;if not found or not app.has_matter_access(w.matter_id,'approve') then raise exception 'Approve access required' using errcode='42501';end if;
 if nullif(w.conclusion,'') is null then raise exception 'A conclusion is required' using errcode='23514';end if;
 if not exists(select 1 from investigation.workpaper_links where workpaper_id=w.id) then raise exception 'At least one evidence, alert, finding, calculation, or interview link is required' using errcode='23514';end if;
 update investigation.workpapers set status='approved',approved_by=app.current_user_id(),approved_at=now() where id=w.id;
 return w.id;end;$$;

grant select,insert,update on investigation.interviews,investigation.workpapers,investigation.workpaper_links,investigation.timeline_events,reporting.exhibits,workflow.tasks to authenticated,service_role;
grant execute on function investigation.approve_workpaper(uuid,text) to authenticated;
commit;
