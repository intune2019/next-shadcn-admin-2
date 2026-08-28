-- ============================================================================
-- Migration 0021: rule execution engine
--
-- 0008 built the full explainable-alert schema (rule_definitions ->
-- rule_versions.logic_sql -> rule_runs -> analytics.rule_hits ->
-- investigation.alerts) and 0012 seeded 25 production rules, several with
-- real, tested logic_sql already written (e.g. AP_DUPLICATE_PAYMENT_V1
-- against canonical.payments/invoices). None of it ever ran — there was no
-- function that actually executes a rule_version's stored SQL. This is that
-- function: it substitutes the rule's named (:param) placeholders with
-- literal-safe values, runs the frozen SELECT, records one analytics.rule_hit
-- per result row (full row captured as feature_snapshot — reproducible by
-- construction, per the "no analytics result should overwrite source data /
-- every alert must be explainable" principle), and groups hits from one run
-- into a single reviewable investigation.alert.
-- ============================================================================

create or replace function rules.execute_rule_version(
  p_rule_version_id uuid,
  p_matter_id uuid,
  p_parameters jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp, rules, analytics, investigation, canonical, core, app
as $$
declare
  v_tenant_id uuid;
  v_rule_id uuid;
  v_rule_code text;
  v_rule_name text;
  v_risk_category text;
  v_logic text;
  v_default_params jsonb;
  v_params jsonb;
  v_sql text;
  v_run_id uuid;
  v_alert_id uuid;
  v_hits_count bigint := 0;
  v_started timestamptz := clock_timestamp();
  v_started_at timestamptz := now();
  kv record;
  hit record;
  v_hit_id uuid;
begin
  if not app.has_matter_access(p_matter_id, 'contribute') then
    raise exception 'insufficient matter access to run detection rules' using errcode = 'insufficient_privilege';
  end if;

  select tenant_id into v_tenant_id from core.matters where id = p_matter_id;
  if v_tenant_id is null then
    raise exception 'matter % not found', p_matter_id;
  end if;

  select rv.logic_sql, rv.default_parameters, rd.id, rd.rule_code, rd.rule_name, rd.risk_category
    into v_logic, v_default_params, v_rule_id, v_rule_code, v_rule_name, v_risk_category
  from rules.rule_versions rv
  join rules.rule_definitions rd on rd.id = rv.rule_id
  where rv.id = p_rule_version_id;

  if v_logic is null then
    raise exception 'rule version % not found', p_rule_version_id;
  end if;

  v_params := coalesce(v_default_params, '{}'::jsonb) || coalesce(p_parameters, '{}'::jsonb);

  insert into rules.rule_runs
    (tenant_id, matter_id, rule_version_id, parameter_values, run_type, status, started_at, created_by)
  values
    (v_tenant_id, p_matter_id, p_rule_version_id, v_params, 'manual', 'running', v_started_at, app.current_user_id())
  returning id into v_run_id;

  -- Substitute :tenant_id / :matter_id / every key in v_params as a literal.
  -- The rule library is authored and approved internally (rule_versions.logic_sql
  -- is checksummed on write — see 0008's tg_version_checksum), so this is
  -- trusted content getting *parameterized*, not untrusted input getting
  -- concatenated; quote_literal/quote_ident still guard every substitution.
  v_sql := v_logic;
  v_sql := replace(v_sql, ':tenant_id', quote_literal(v_tenant_id::text) || '::uuid');
  v_sql := replace(v_sql, ':matter_id', quote_literal(p_matter_id::text) || '::uuid');
  for kv in select * from jsonb_each_text(v_params) loop
    v_sql := replace(v_sql, ':' || kv.key,
      case jsonb_typeof(v_params -> kv.key)
        when 'number' then kv.value
        else quote_literal(kv.value)
      end);
  end loop;

  -- logic_sql conventionally opens with `-- comment` lines; strip those before
  -- validating that the statement itself is a single read-only SELECT.
  if regexp_replace(v_sql, '^(\s*--[^\n]*\n)+', '') !~* '^\s*select' or v_sql ~* ';\s*\S' then
    update rules.rule_runs set status = 'failed', finished_at = clock_timestamp() where id = v_run_id;
    raise exception 'rule logic_sql must be exactly one read-only SELECT statement';
  end if;

  for hit in execute v_sql loop
    v_hits_count := v_hits_count + 1;
    insert into analytics.rule_hits
      (tenant_id, matter_id, rule_run_id, rule_version_id, primary_object_type,
       severity, reason_codes, explanation, feature_snapshot, created_by)
    values
      (v_tenant_id, p_matter_id, v_run_id, p_rule_version_id, coalesce(v_rule_code, 'unspecified'),
       coalesce(v_risk_category, 'medium'),
       jsonb_build_array(v_rule_code),
       coalesce(v_rule_name, v_rule_code) || ' matched.',
       to_jsonb(hit), app.current_user_id());
  end loop;

  update rules.rule_runs
    set status = 'completed', finished_at = clock_timestamp(), hits_created = v_hits_count,
        records_tested = v_hits_count
    where id = v_run_id;

  if v_hits_count > 0 then
    insert into investigation.alerts
      (tenant_id, matter_id, alert_title, alert_type, aggregate_severity, review_status, created_by)
    values
      (v_tenant_id, p_matter_id, format('%s — %s hit(s)', coalesce(v_rule_name, v_rule_code), v_hits_count),
       'transaction', coalesce(v_risk_category, 'medium'), 'new', app.current_user_id())
    returning id into v_alert_id;

    insert into investigation.alert_hits (tenant_id, matter_id, alert_id, rule_hit_id)
    select v_tenant_id, p_matter_id, v_alert_id, rh.id
    from analytics.rule_hits rh
    where rh.rule_run_id = v_run_id;
  end if;

  return v_run_id;
end;
$$;

comment on function rules.execute_rule_version(uuid, uuid, jsonb) is
  'Executes a rule_version''s frozen logic_sql against live matter data,
   records one analytics.rule_hit per result row (full row = feature_snapshot,
   so every hit is independently reproducible), and groups the run''s hits
   into a single investigation.alert when any are found. Caller needs
   "contribute" access on the matter — same bar as any other analyst write.';

grant execute on function rules.execute_rule_version(uuid, uuid, jsonb) to authenticated;
