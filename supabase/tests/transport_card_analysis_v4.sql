-- Read-only assertions against the published tenant scope; run inside a transaction.
do $$
declare tenant uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';
 owner_id uuid:='5a6fa4c4-5427-47fa-9835-d997fe81c7d5';
 a jsonb;b jsonb; unit_id uuid; old_sub text:=current_setting('request.jwt.claim.sub',true);
begin
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 a:=public.hub_transport_leader_scorecard_v3(tenant,'2026-09-01','2026-10-28');
 b:=public.hub_transport_leader_scorecard_v4(tenant,'2026-09-01','2026-10-28');
 if a is distinct from b-'analysis_inputs' then raise exception 'Financial report changed';end if;
 unit_id:=(b#>>'{units,0,unit_id}')::uuid;
 a:=public.hub_transport_leader_scorecard_v3(tenant,'2026-09-01','2026-10-28',null,unit_id,0,array[9],null);
 b:=public.hub_transport_leader_scorecard_v4(tenant,'2026-09-01','2026-10-28',null,unit_id,0,array[9],null);
 if a is distinct from b-'analysis_inputs' then raise exception 'Unit/month filter changed';end if;
 if jsonb_array_length(b->'analysis_inputs')<=1 then raise exception 'Peer scope was lost on unit drilldown';end if;
 a:=public.hub_transport_leader_scorecard_v3(tenant,'2026-09-01','2026-10-28',null,null,0,null,'Stena');
 b:=public.hub_transport_leader_scorecard_v4(tenant,'2026-09-01','2026-10-28',null,null,0,null,'Stena');
 if a is distinct from b-'analysis_inputs' then raise exception 'Group filter changed';end if;
 if has_function_privilege('anon','public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)','execute') then raise exception 'Anonymous execution allowed';end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.hub_transport_leader_scorecard_v4(tenant,'2026-09-01','2026-10-28');
  raise exception 'Unauthenticated report allowed';
 exception when sqlstate '22023' then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin
  perform public.hub_transport_leader_scorecard_v4(tenant,'2026-09-01','2026-10-28');
  raise exception 'Nonmember report allowed';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
end $$;
