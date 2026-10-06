-- PIUSI: nightly source import before the 03:20 Dashboard snapshot.
-- Hourly UTC ticks use the worker's Stockholm guard for DST.
DO $migration$
BEGIN
 PERFORM cron.alter_job(jobid, schedule := '0 * * * *',
 command := $command$select net.http_post(
 url:='https://vuurtaafxvevbhdzgttq.supabase.co/functions/v1/piusi-live-worker',
 headers:=jsonb_build_object('Content-Type','application/json','x-humla-worker-key',
 (select decrypted_secret from vault.decrypted_secrets where name='humla_worker_key' limit 1)),
 body:='{"nightly":true}'::jsonb,timeout_milliseconds:=60000);$command$)
 FROM cron.job WHERE jobname='humla-piusi-live-every-15-min';
END
$migration$;
