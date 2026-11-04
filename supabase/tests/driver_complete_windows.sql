begin;
set local jit=off;
do $$
declare t uuid;g uuid;u uuid:=gen_random_uuid();d date:=current_date-8;
begin
 select tenant_id,active_generation into t,g from private.hub_kpi_report_state where active_generation is not null limit 1;
 if t is null then raise exception 'Active generation fixture required';end if;
 if private.hub_driver_window_complete_v1(t,u,d-27,d) then raise exception 'Unknown coverage accepted';end if;
 begin
 insert into private.hub_driver_complete_windows_v1 values(t,u,g,d-27,d,'{"revenue":"fixture"}',now());
 raise exception 'Missing source accepted';exception when check_violation then null;end;
 insert into private.hub_driver_complete_windows_v1 values(t,u,g,d-27,d,'{"revenue":"fixture","cost":"fixture","work_time":"fixture","personnel":"fixture","fuel":"fixture","overhead":"fixture"}',now());
 if not private.hub_driver_window_complete_v1(t,u,d-27,d) then raise exception 'Complete rolling period rejected';end if;
 if not private.hub_driver_window_complete_v1(t,u,d-6,d) then raise exception 'Complete week rejected';end if;
 if not private.hub_driver_window_complete_v1(t,u,d,d) then raise exception 'Complete single day rejected';end if;
 if private.hub_driver_window_complete_v1(t,u,d-27,d+1) then raise exception 'Day after common cutoff accepted';end if;
 if private.hub_driver_window_complete_v1(t,u,d-28,d) then raise exception 'Uncovered start accepted';end if;
 if private.hub_driver_window_complete_v1(t,u,d-55,d-28) then raise exception 'Unverified previous period accepted';end if;
 update private.hub_driver_complete_windows_v1 set generation_id=gen_random_uuid() where tenant_id=t and unit_id=u;
 if private.hub_driver_window_complete_v1(t,u,d,d) then raise exception 'Stale generation accepted';end if;
 if has_table_privilege('authenticated','private.hub_driver_complete_windows_v1','insert') then raise exception 'Driver can attest source completeness';end if;
 if has_function_privilege('authenticated','private.hub_driver_window_complete_v1(uuid,uuid,date,date)','execute') then raise exception 'Private helper exposed';end if;
end $$;
select 'PASS: weekly and daily coverage, common cutoff, missing components, unverified comparison, generation invalidation and permissions' result;
rollback;
