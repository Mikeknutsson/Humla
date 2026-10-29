begin;
do $test$
declare r jsonb;v jsonb;
begin
 r:='{"summary":{"revenue":1000,"cost":700,"result":300,"unassigned_rows":0},"units":[{"unit_id":"00000000-0000-0000-0000-000000000001"}],"analysis_inputs":[{"unit_id":"00000000-0000-0000-0000-000000000001","worked_hours":10}],"breakdown":[{"kind":"cost","category":"fuel","amount":100}]}'::jsonb;
 v:=private.hub_foreman_area_kpis_v1(r);
 assert (v->>'revenue_per_hour')::numeric=100;
 assert (v->>'cost_per_hour')::numeric=70;
 assert (v->>'result_per_hour')::numeric=30;
 assert (v->>'fuel_share')::numeric=10;
 assert (v->>'hours_complete')::boolean;
 v:=private.hub_foreman_area_kpis_v1(jsonb_set(r,'{analysis_inputs,0,worked_hours}','null'));
 assert v->'revenue_per_hour'='null'::jsonb and not(v->>'hours_complete')::boolean,'missing hours must not inflate ratios';
 v:=private.hub_foreman_area_kpis_v1(r,false);
 assert v->'revenue_per_hour'='null'::jsonb,'month filtered reports must not use unfiltered hours';
 v:=private.hub_foreman_area_kpis_v1(jsonb_set(r,'{summary,revenue}','0'));
 assert v->'fuel_share'='null'::jsonb,'no divide by zero';
end $test$;
set local role authenticated;set local request.jwt.claim.sub='5a6fa4c4-5427-47fa-9835-d997fe81c7d5';
select name,public.hub_transport_leader_scorecard_v4('944597b6-9c46-4bef-998d-f19e23c4245b','2026-09-01','2026-10-29',id)->'area_kpis' kpis
from(values('Ola','7f87dae3-7055-473d-89e5-849905a65846'::uuid),('Pierre','6bee2e13-a6c7-4a05-b22f-9f91f5424a31'::uuid),('Marcus','bc566ca4-dc80-4d81-a7dc-1378eec7bb93'::uuid),('Sortergården','591d7698-bea7-46ce-a994-ddcb8d943500'::uuid))m(name,id);
rollback;