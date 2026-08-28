-- ============================================================================
-- Migration 0011: reusable analytical / golden-thread views
-- These are SECURITY INVOKER (default) so RLS on the base tables still applies:
-- a user only ever sees rows for matters they can access.
-- ============================================================================

-- Payment 360 — the input contract for treasury/fraud rules.
create or replace view analytics.v_payment_360 as
select
  p.id                       as payment_id,
  p.matter_id,
  p.payment_reference,
  p.payment_date,
  p.amount_original,
  p.currency_original,
  ba.account_token           as from_account_token,
  be.display_name            as beneficiary_name,
  vba.change_event_at        as beneficiary_bank_changed_at,
  p.initiator_user_ref,
  p.approver_user_ref,
  p.releaser_user_ref,
  (p.initiator_user_ref is not distinct from p.approver_user_ref) as initiator_equals_approver,
  ba.is_restricted           as from_restricted_cash,
  p.source_evidence_id,
  p.source_dataset_version_id
from canonical.payments p
left join canonical.bank_accounts ba on ba.id = p.from_account_id
left join canonical.entities be      on be.id = p.beneficiary_entity_id
left join canonical.vendor_bank_accounts vba
       on vba.bank_account_id = p.beneficiary_account_id;

-- Evidence lineage — evidence item to its custody chain head + integrity.
create or replace view analytics.v_evidence_lineage as
select
  ei.id                      as evidence_id,
  ei.matter_id,
  ei.human_evidence_no,
  ei.evidence_type,
  ei.integrity_status,
  ei.legal_hold_status,
  coc.last_seq,
  coc.chain_head,
  eh.hash_value              as latest_file_hash
from evidence.evidence_items ei
left join lateral (
  select max(seq) as last_seq,
         (array_agg(chain_hash order by seq desc))[1] as chain_head
  from evidence.chain_of_custody_events c
  where c.evidence_id = ei.id
) coc on true
left join lateral (
  select ef.id from evidence.evidence_files ef
  where ef.evidence_id = ei.id order by ef.created_at desc limit 1
) f on true
left join lateral (
  select hash_value from evidence.evidence_hashes h
  where h.evidence_file_id = f.id order by verified_at desc limit 1
) eh on true;

-- Report traceability — every report claim back to finding/fact/evidence/calc.
create or replace view analytics.v_report_traceability as
select
  r.id                       as report_id,
  r.matter_id,
  r.title                    as report_title,
  r.version                  as report_version,
  rs.section_number,
  rcl.claim_text,
  rcl.statement_type,
  rcl.reviewer_approved,
  f.id                       as finding_id,
  f.title                    as finding_title,
  f.conclusion_status,
  fa.id                      as fact_id,
  ev.human_evidence_no       as evidence_no
from reporting.reports r
join reporting.report_sections rs      on rs.report_id = r.id
join reporting.report_claim_links rcl  on rcl.report_section_id = rs.id
left join investigation.findings f     on f.id  = rcl.finding_id
left join investigation.facts fa       on fa.id = rcl.fact_id
left join evidence.evidence_items ev   on ev.id = rcl.evidence_id;

-- The single "golden thread": from a suspicious payment out to the finding and
-- report that cite it, through the rule hit and evidence that support it.
create or replace view analytics.v_golden_thread as
select
  p.matter_id,
  p.payment_reference,
  p.amount_original,
  rh.severity,
  rh.risk_score,
  rh.explanation             as rule_explanation,
  al.alert_title,
  al.disposition             as alert_disposition,
  f.title                    as finding_title,
  f.conclusion_status,
  f.financial_impact,
  ev.human_evidence_no       as source_evidence_no
from canonical.payments p
left join analytics.rule_hits rh
       on rh.primary_object_type = 'payment' and rh.primary_object_id = p.id
left join investigation.alert_hits ah on ah.rule_hit_id = rh.id
left join investigation.alerts al     on al.id = ah.alert_id
left join investigation.findings f    on f.allegation_id = al.related_allegation_id
left join evidence.evidence_items ev  on ev.id = p.source_evidence_id;

grant select on
  analytics.v_payment_360,
  analytics.v_evidence_lineage,
  analytics.v_report_traceability,
  analytics.v_golden_thread
to authenticated, service_role;
