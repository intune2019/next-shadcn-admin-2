-- Normalize operational identifiers to the Forens_iQ brand.
begin;
select cron.unschedule(jobid) from cron.job
where command='select app.run_scheduled_anchoring()' and jobname<>'forensiq-anchor-runs';
select cron.schedule('forensiq-anchor-runs','*/15 * * * *',$$select app.run_scheduled_anchoring()$$)
where not exists(select 1 from cron.job where jobname='forensiq-anchor-runs');
commit;
