-- Final approval gates, signatures, report issuance, and durable job leasing.
begin;

create or replace function reporting.decide_report(p_report_id uuid,p_decision text,p_role text,p_note text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,reporting,calculations,app,extensions as $$
declare v reporting.reports%rowtype;v_snapshot text;v_hash bytea;v_id uuid;
begin
 select * into v from reporting.reports where id=p_report_id;
 if not found or not app.has_matter_access(v.matter_id,'approve') then raise exception 'Approve access required' using errcode='42501';end if;
 if p_decision not in('approved','rejected','revision_requested') then raise exception 'Invalid decision' using errcode='22023';end if;
 if p_decision='approved' then
  if not exists(select 1 from reporting.report_sections where report_id=v.id and record_status='active') then raise exception 'Report has no sections' using errcode='23514';end if;
  if exists(select 1 from reporting.report_comments where report_id=v.id and status='open') then raise exception 'Open report comments must be resolved' using errcode='23514';end if;
  if exists(select 1 from reporting.report_claim_links l join calculations.calculation_runs c on c.id=l.calculation_run_ref where l.report_section_id in(select id from reporting.report_sections where report_id=v.id) and c.status<>'approved') then raise exception 'Report contains a calculation that is not approved' using errcode='23514';end if;
 end if;
 select coalesce(string_agg(coalesce(section_number,'')||coalesce(heading,'')||coalesce(body,''),E'\n' order by sort_order,id),'') into v_snapshot from reporting.report_sections where report_id=v.id and record_status='active';
 v_hash:=extensions.digest(convert_to(v_snapshot||v.version||p_decision,'UTF8'),'sha256');
 insert into reporting.report_approvals(tenant_id,matter_id,report_id,approval_role,decision,decision_note,decided_by,report_snapshot_hash,created_by)
 values(v.tenant_id,v.matter_id,v.id,p_role,p_decision,p_note,app.current_user_id(),v_hash,app.current_user_id()) returning id into v_id;
 update reporting.reports set status=case when p_decision='approved' then 'approved' else 'drafting' end where id=v.id;
 return v_id;
end;$$;

create or replace function reporting.sign_report(p_report_id uuid,p_signer_role text)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,reporting,app,extensions as $$
declare v reporting.reports%rowtype;v_hash bytea;v_id uuid;
begin select * into v from reporting.reports where id=p_report_id;
 if not found or not app.has_matter_access(v.matter_id,'approve') then raise exception 'Approve access required' using errcode='42501';end if;
 if v.status not in('approved','issued') then raise exception 'Only approved reports may be signed' using errcode='23514';end if;
 select extensions.digest(convert_to(v.id::text||v.version||coalesce(string_agg(coalesce(s.body,''),'' order by s.sort_order),''),'UTF8'),'sha256') into v_hash from reporting.report_sections s where s.report_id=v.id;
 insert into reporting.signatures(tenant_id,matter_id,report_id,signer_user_id,signer_role,signed_hash,created_by) values(v.tenant_id,v.matter_id,v.id,app.current_user_id(),p_signer_role,v_hash,app.current_user_id()) returning id into v_id;return v_id;
end;$$;

create or replace function reporting.issue_distribution(p_distribution_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp,reporting,app,extensions as $$
declare d reporting.distribution_log%rowtype;r reporting.reports%rowtype;v_sig int;v_hash bytea;
begin select * into d from reporting.distribution_log where id=p_distribution_id;select * into r from reporting.reports where id=d.report_id;
 if not found or not app.has_matter_access(d.matter_id,'approve') then raise exception 'Approve access required' using errcode='42501';end if;
 if r.status not in('approved','issued') then raise exception 'Report must be approved before distribution' using errcode='23514';end if;
 select count(*) into v_sig from reporting.signatures where report_id=r.id;if v_sig=0 then raise exception 'At least one authenticated signature is required' using errcode='23514';end if;
 select signed_hash into v_hash from reporting.signatures where report_id=r.id order by signed_at desc limit 1;
 -- append-only distribution rows cannot be updated: preserve issuance as a new ledger event.
 insert into reporting.distribution_log(tenant_id,matter_id,report_id,report_edition_id,recipient_name,recipient_address,delivery_method,delivery_status,authorized_by,distributed_by,distributed_at,output_hash,created_by)
 values(d.tenant_id,d.matter_id,d.report_id,d.report_edition_id,d.recipient_name,d.recipient_address,d.delivery_method,'distributed',app.current_user_id(),app.current_user_id(),now(),v_hash,app.current_user_id()) returning id into p_distribution_id;
 update reporting.reports set status='issued',issued_at=coalesce(issued_at,now()) where id=r.id;return p_distribution_id;
end;$$;

create or replace function operations.lease_jobs(p_worker_ref text,p_limit int default 5,p_lease_seconds int default 300)
returns setof operations.jobs language plpgsql security definer set search_path=pg_catalog,pg_temp,operations as $$
begin
 if current_user not in('service_role','supabase_admin','postgres') then raise exception 'Service role required' using errcode='42501';end if;
 return query with picked as(select id from operations.jobs where status='queued' and available_at<=now() order by priority,created_at for update skip locked limit greatest(1,least(p_limit,50)))
 update operations.jobs j set status='leased',leased_until=now()+make_interval(secs=>greatest(30,p_lease_seconds)),worker_ref=p_worker_ref,attempt_count=attempt_count+1,started_at=coalesce(started_at,now()) from picked where j.id=picked.id returning j.*;
end;$$;
create or replace function operations.finish_job(p_job_id uuid,p_succeeded boolean,p_result jsonb default null,p_error text default null)
returns void language plpgsql security definer set search_path=pg_catalog,pg_temp,operations as $$
begin if current_user not in('service_role','supabase_admin','postgres') then raise exception 'Service role required' using errcode='42501';end if;
 update operations.jobs set status=case when p_succeeded then 'succeeded' when attempt_count>=max_attempts then 'dead_letter' else 'queued' end,result=p_result,last_error=p_error,finished_at=case when p_succeeded or attempt_count>=max_attempts then now() end,available_at=case when not p_succeeded then now()+make_interval(secs=>least(3600,30*(2^attempt_count)::int)) else available_at end,leased_until=null where id=p_job_id;
end;$$;

revoke all on function reporting.decide_report(uuid,text,text,text),reporting.sign_report(uuid,text),reporting.issue_distribution(uuid) from public,anon;
grant execute on function reporting.decide_report(uuid,text,text,text),reporting.sign_report(uuid,text),reporting.issue_distribution(uuid) to authenticated;
revoke all on function operations.lease_jobs(text,int,int),operations.finish_job(uuid,boolean,jsonb,text) from public,anon,authenticated;
grant execute on function operations.lease_jobs(text,int,int),operations.finish_job(uuid,boolean,jsonb,text) to service_role;

commit;
