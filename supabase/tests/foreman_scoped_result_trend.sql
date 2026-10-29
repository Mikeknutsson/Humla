begin;
set local role authenticated;
set local request.jwt.claim.sub='5a6fa4c4-5427-47fa-9835-d997fe81c7d5';
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b'; u uuid; r jsonb;s jsonb;bounds record; p jsonb; prev jsonb;
begin
 foreach u in array array['7f87dae3-7055-473d-89e5-849905a65846'::uuid,'6bee2e13-a6c7-4a05-b22f-9f91f5424a31'::uuid,'bc566ca4-dc80-4d81-a7dc-1378eec7bb93'::uuid,'591d7698-bea7-46ce-a994-ddcb8d943500'::uuid] loop
  for bounds in select * from (values ('2026-09-01'::date,'2026-10-29'::date),('2026-09-01'::date,'2026-10-26'::date),('2026-10-01'::date,'2026-10-31'::date),('2026-09-01'::date,'2027-08-31'::date),('2090-01-01'::date,'2090-01-31'::date)) as b(f,z) loop
   r:=public.hub_foreman_result_trend_v1(t,bounds.f,bounds.z,u);
   s:=public.hub_transport_leader_scorecard_v4(t,bounds.f,bounds.z,u);
   if jsonb_array_length(r->'points')=0 then
    assert r->'latest'='null'::jsonb,'empty period must have null latest';
    assert (s->'summary'->>'rows')::integer=0,'empty trend inconsistent with scorecard';
   else
    assert (r->'latest'->>'result')::numeric=(s->'summary'->>'result')::numeric,'result mismatch';
    assert (r->'latest'->>'revenue')::numeric=(s->'summary'->>'revenue')::numeric,'revenue mismatch';
    assert (r->'latest'->>'cost')::numeric=(s->'summary'->>'cost')::numeric,'cost mismatch';
    if u='591d7698-bea7-46ce-a994-ddcb8d943500'::uuid then
     assert (r->>'area_target_margin_percent')::numeric=20,'Sortergarden area goal must be 20 percent';
     assert (r->'latest'->>'target_result')::numeric=(r->'latest'->>'revenue')::numeric*0.2,'area goal incorrect';
    else
     assert r->'area_target_margin_percent'='null'::jsonb,'area goal leaked to another profile';
     assert (r->'latest'->'target_margin_percent') is not distinct from (s->'summary'->'target_margin_percent'),'unit goals mismatch';
    end if;
   end if;
   prev:=null;
   for p in select value from jsonb_array_elements(r->'points') loop
    assert (p->>'date')::date between bounds.f and bounds.z,'point outside selected range';
    assert prev is null or p->>'date'>prev->>'date','points not strictly chronological';
    assert (p->>'result')::numeric=(p->>'revenue')::numeric-(p->>'cost')::numeric,'point result incorrect';
    assert (p->>'missing_targets')::integer=0 or p->'target_result'='null'::jsonb,'partial goal must remain unknown';
    prev:=p;
   end loop;
  end loop;
 end loop;
 -- Actual supervisor may read own scope, but cannot impersonate a colleague.
 perform set_config('request.jwt.claim.sub','6bee2e13-a6c7-4a05-b22f-9f91f5424a31',true);
 perform public.hub_foreman_result_trend_v1(t,'2026-09-01','2026-10-29','6bee2e13-a6c7-4a05-b22f-9f91f5424a31');
 begin
  perform public.hub_foreman_result_trend_v1(t,'2026-09-01','2026-10-29','bc566ca4-dc80-4d81-a7dc-1378eec7bb93');
  raise exception 'FAIL: impersonation allowed';
 exception when insufficient_privilege then null;end;
 begin
  perform public.hub_foreman_result_trend_v1('00000000-0000-0000-0000-000000000001','2026-09-01','2026-10-29','6bee2e13-a6c7-4a05-b22f-9f91f5424a31');
  raise exception 'FAIL: cross tenant allowed';
 exception when insufficient_privilege then null;end;
 begin
  perform public.hub_foreman_result_trend_v1(t,'2026-10-29','2026-09-01','6bee2e13-a6c7-4a05-b22f-9f91f5424a31');
  raise exception 'FAIL: reversed dates allowed';
 exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.hub_foreman_result_trend_v1(t,'2026-09-01','2026-10-29',null);
  raise exception 'FAIL: unauthenticated allowed';
 exception when invalid_parameter_value then null;end;
end $test$;
select 'PASS: 4 scopes x 5 periods, exact scorecard totals, missing goals, empty periods, chronological points, supervisor own access, denied impersonation/cross-tenant/anonymous/invalid dates' as verification,
has_function_privilege('anon','public.hub_foreman_result_trend_v1(uuid,date,date,uuid)','EXECUTE') as anon_execute;
rollback;