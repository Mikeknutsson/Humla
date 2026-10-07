begin; select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
DO $test$
DECLARE before_periods jsonb; after_periods jsonb; lock_before timestamptz; lock_after timestamptz; q jsonb; rev integer; refs jsonb:='{"registrations":["SPN03J"],"projects":["9057"],"employees":[]}'; rejected boolean;
BEGIN
SELECT revision INTO rev FROM public.kpi_units WHERE id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2';
SELECT jsonb_agg(to_jsonb(p) ORDER BY valid_from) INTO before_periods FROM public.kpi_unit_periods p WHERE unit_id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2';
SELECT locked_at INTO lock_before FROM public.kpi_unit_initial_setup WHERE unit_id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2';
q:=public.hub_kpi_complete_unit_history_v1('944597b6-9c46-4bef-998d-f19e23c4245b','bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2',rev,'2025-09-01','Verifiering av historisk lucka',true,null,refs);
IF NOT (q->>'can_save')::boolean THEN RAISE EXCEPTION 'Expected non-conflicting preview';END IF;
rejected:=false;
BEGIN PERFORM public.hub_kpi_complete_unit_history_v1('944597b6-9c46-4bef-998d-f19e23c4245b','bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2',rev,'2025-09-01','Verifiering av historisk lucka',false,'incorrect',refs);EXCEPTION WHEN OTHERS THEN rejected:=true;END;
IF NOT rejected THEN RAISE EXCEPTION 'Save without matching preview accepted';END IF;
PERFORM public.hub_kpi_complete_unit_history_v1('944597b6-9c46-4bef-998d-f19e23c4245b','bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2',rev,'2025-09-01','Verifiering av historisk lucka',false,q->>'signature',refs);
SELECT jsonb_agg(to_jsonb(p) ORDER BY valid_from) INTO after_periods FROM public.kpi_unit_periods p WHERE unit_id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2' AND valid_from>='2026-10-01';
SELECT locked_at INTO lock_after FROM public.kpi_unit_initial_setup WHERE unit_id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2';
IF before_periods IS DISTINCT FROM after_periods OR lock_before IS DISTINCT FROM lock_after THEN RAISE EXCEPTION 'Existing periods or lock changed';END IF;
IF NOT EXISTS(SELECT 1 FROM public.kpi_unit_periods WHERE unit_id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2' AND valid_from='2025-09-01' AND valid_to='2026-09-30' AND payload->'employees'='[]'::jsonb) THEN RAISE EXCEPTION 'Expected bounded new period';END IF;
IF NOT EXISTS(SELECT 1 FROM public.kpi_unit_initial_setup_events WHERE unit_id='bae0d4d5-4c4b-47d2-99b9-13ef6771c4e2' AND action='extend_history' AND next_payload#>>'{_humla_history_completion,reason}'='Verifiering av historisk lucka') THEN RAISE EXCEPTION 'Missing audit';END IF;
END $test$;
rollback;