-- Source import precedes the prepared Dashboard dataset.
-- Keep the UTC database timezone and existing Sweden/DST time guards.
DO $migration$
DECLARE definition text;
BEGIN
  definition := pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
  IF position('time ''03:00''' in definition)=0 AND position('time ''03:20''' in definition)=0 THEN
    RAISE EXCEPTION 'Unexpected KPI nightly scheduling definition';
  END IF;
  EXECUTE replace(definition, 'time ''03:00''', 'time ''03:20''');
  definition := pg_get_functiondef('private.hub_kpi_report_status_v1(uuid)'::regprocedure);
  IF position('03:00 Europe/Stockholm' in definition)=0 AND position('03:20 Europe/Stockholm' in definition)=0 THEN
    RAISE EXCEPTION 'Unexpected KPI status schedule';
  END IF;
  EXECUTE replace(definition,'03:00 Europe/Stockholm','03:20 Europe/Stockholm');
  PERFORM cron.alter_job(jobid, schedule := '0 * * * *')
  FROM cron.job WHERE jobname='humla-transpa-daily-sync';
END
$migration$;
