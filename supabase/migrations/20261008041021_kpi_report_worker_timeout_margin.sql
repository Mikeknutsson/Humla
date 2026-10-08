-- A verified full rebuild takes about four minutes. Allow headroom for
-- growing source data and concurrent load; the advisory lock still serializes
-- workers, and the previous completed generation remains readable throughout.
do $migration$
declare report_job bigint;
begin
 select jobid into report_job from cron.job where jobname='hub-kpi-prepared-reports-v1';
 if report_job is null then raise exception 'KPI report cron job missing'; end if;
 perform cron.alter_job(job_id:=report_job,command:='begin isolation level repeatable read; set local statement_timeout=''10min''; select private.hub_kpi_run_report_jobs_v1(); commit;');
end $migration$;
