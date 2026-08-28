-- ============================================================================
-- Forens_iQ demo seed + verification walkthrough.
-- OPTIONAL. Run in the Supabase SQL editor (runs as `postgres`, which bypasses
-- RLS, so seeding is straightforward). Demonstrates the golden thread and the
-- tamper-evidence / crypto-shred guarantees. Safe to run on a scratch project.
-- ============================================================================
begin;

-- fixed ids for readability
-- tenant, matter, user, evidence, payment, allegation, alert, finding, report
select set_config('demo.t','11111111-1111-1111-1111-111111111111',true);

insert into core.tenants(id, tenant_name) values
  ('11111111-1111-1111-1111-111111111111','Demo Forensics LLP');

insert into core.matters(id, tenant_id, matter_number, matter_name, matter_type, jurisdiction)
values ('22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        'MAT-001','Project Ledger — Vendor Payment Review','fraud_exam','US-CO');

-- grant a demo examiner approve-level access to the matter
insert into core.matter_access(tenant_id, matter_id, user_id, access_level)
values ('11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '99999999-9999-9999-9999-999999999999','approve');

-- evidence: a bank statement, with a file + hash
insert into evidence.evidence_items(id, tenant_id, matter_id, human_evidence_no, evidence_type, title)
values ('33333333-3333-3333-3333-333333333333',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        'MAT-001-EV-000001','bank_record','Operating acct statement 2026-07');

insert into evidence.evidence_files(id, tenant_id, matter_id, evidence_id, file_name, mime_type, byte_size)
values ('33333333-0000-0000-0000-0000000000f1',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333','stmt_2026_07.pdf','application/pdf',384512);

insert into evidence.evidence_hashes(tenant_id, matter_id, evidence_file_id, hash_value)
values ('11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '33333333-0000-0000-0000-0000000000f1',
        extensions.digest('demo-file-bytes','sha256'));

-- two custody events -> builds a hash chain for this evidence item
insert into evidence.chain_of_custody_events(tenant_id, matter_id, evidence_id, event_type, from_party, to_party, reason_code)
values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333','collected','Client Treasury','Examiner A','preservation'),
       ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333','hashed','Examiner A','Evidence Vault','integrity');

-- a suspicious payment tied to that evidence
insert into canonical.entities(id, tenant_id, matter_id, entity_type, display_name, name_normalized)
values ('44444444-4444-4444-4444-444444444444',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'organization','Nimbus Supply Co','nimbus supply');

insert into canonical.payments(id, tenant_id, matter_id, payment_reference, payment_date,
        amount_original, currency_original, beneficiary_entity_id, initiator_user_ref,
        approver_user_ref, source_evidence_id)
values ('55555555-5555-5555-5555-555555555555',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'WIRE-2026-004918','2026-07-18',175000.00,'USD',
        '44444444-4444-4444-4444-444444444444','u_jsmith','u_jsmith',  -- same person = SoD breach
        '33333333-3333-3333-3333-333333333333');

-- an allegation + alert + rule hit + finding + report claim (golden thread)
insert into investigation.allegations(id, tenant_id, matter_id, allegation_no, reported_conduct, scheme_category)
values ('66666666-6666-6666-6666-666666666666',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'ALG-001','Wire released to new beneficiary by initiator who also approved','treasury');

insert into analytics.rule_hits(id, tenant_id, matter_id, primary_object_type, primary_object_id,
        primary_business_key, severity, risk_score, confidence_score, reason_codes, explanation,
        feature_snapshot)
values ('77777777-7777-7777-7777-777777777777',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'payment','55555555-5555-5555-5555-555555555555','WIRE-2026-004918','high',82,96,
        '["INITIATOR_EQUALS_APPROVER","PAYMENT_EXCEEDS_HIGH_VALUE_THRESHOLD"]'::jsonb,
        'A $175,000 wire was initiated and approved by the same user and exceeds the high-value threshold.',
        '{"payment_amount":175000,"high_value_threshold":50000,"initiator_equals_approver":true}'::jsonb);

insert into investigation.alerts(id, tenant_id, matter_id, alert_title, alert_type,
        aggregate_severity, aggregate_risk_score, financial_exposure, related_allegation_id, disposition)
values ('88888888-8888-8888-8888-888888888888',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'SoD breach on WIRE-2026-004918','transaction','high',82,175000,
        '66666666-6666-6666-6666-666666666666','linked_to_finding');

insert into investigation.alert_hits(tenant_id, matter_id, alert_id, rule_hit_id)
values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        '88888888-8888-8888-8888-888888888888','77777777-7777-7777-7777-777777777777');

-- a supporting fact + finding (finding must have reviewer + supporting fact)
insert into investigation.facts(id, tenant_id, matter_id, statement, fact_type, confidence)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'User u_jsmith is recorded as both initiator and approver of WIRE-2026-004918.',
        'documented','high');

insert into investigation.findings(id, tenant_id, matter_id, allegation_id, title, methodology,
        financial_impact, currency, classification, reviewed_by, reviewed_at, conclusion_status)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        '66666666-6666-6666-6666-666666666666','Segregation-of-duties breach on high-value wire',
        'Payment-authority test against workflow events',175000,'USD','control_deficiency',
        '99999999-9999-9999-9999-999999999999', now(),'draft');  -- promote to 'supported' after linking a fact

insert into investigation.finding_sources(tenant_id, matter_id, finding_id, fact_id, is_contrary)
values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);

-- now the finding can legally advance (guard trigger allows it: reviewer + fact present)
update investigation.findings set conclusion_status='supported'
 where id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

commit;

-- ============================================================================
-- VERIFY THE GOLDEN THREAD
-- ============================================================================
select * from analytics.v_golden_thread
 where matter_id = '22222222-2222-2222-2222-222222222222';

-- VERIFY TAMPER-EVIDENCE: chain intact?
select audit.verify_chain('11111111-1111-1111-1111-111111111111') as audit_break_seq; -- NULL = intact

-- VERIFY APPEND-ONLY: the next line should FAIL with an exception
-- update evidence.chain_of_custody_events set event_type='tampered' where true;

-- VERIFY FINDING GUARD: this should FAIL (no reviewer)
-- update investigation.findings set conclusion_status='final', reviewed_by=null
--   where id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

-- VERIFY CRYPTO-SHRED (needs Vault):
-- select security.vault_put('11111111-1111-1111-1111-111111111111','bank_account','acct:demo','123456789');  -- returns key id
-- select security.vault_get('<key id>');            -- returns '123456789'
-- select security.shred('<key id>','court order #123');
-- select security.vault_get('<key id>');            -- now NULL, row + audit remain
