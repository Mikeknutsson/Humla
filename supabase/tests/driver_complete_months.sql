begin;
set local jit=off;
do $$
declare t uuid;g uuid;u uuid:=gen_random_uuid();m date:=(date_trunc('month',current_date)-interval '2 months')::date;e date;
begin
 select tenant_id,active_generation into t,g from private.hub_kpi_report_state where active_generation is not null limit 1;
 if t is null then raise exception 'Test requires an active generation';end if;
 e:=(m+interval '1 month -1 day')::date;
 if private.hub_driver_month_complete_v1(t,u,m,e) then raise exception 'Unverified month accepted';end if;
 begin
 insert into private.hub_driver_closed_months_v1 values(t,u,g,m,'{"revenue":"fixture"}',now());
 raise exception 'Missing component evidence accepted';
 exception when check_violation then null;end;
 insert into private.hub_driver_closed_months_v1 values(t,u,g,m,'{"revenue":"fixture","cost":"fixture","work_time":"fixture","personnel":"fixture","fuel":"fixture","overhead":"fixture"}',now());
 if not private.hub_driver_month_complete_v1(t,u,m,e) then raise exception 'Reconciled month rejected';end if;
 if private.hub_driver_month_complete_v1(t,u,m+7,e) then raise exception 'Partial month accepted';end if;
 update private.hub_driver_closed_months_v1 set generation_id=gen_random_uuid() where tenant_id=t and unit_id=u;
 if private.hub_driver_month_complete_v1(t,u,m,e) then raise exception 'Stale generation accepted';end if;
 if has_function_privilege('authenticated','private.hub_driver_month_complete_v1(uuid,uuid,date,date)','execute') then raise exception 'Private helper exposed';end if;
 if has_table_privilege('authenticated','private.hub_driver_closed_months_v1','insert') then raise exception 'Driver can certify completeness';end if;
 if has_function_privilege('anon','public.hub_driver_goal_periods_v1(uuid,uuid)','execute') then raise exception 'Anonymous periods exposed';end if;
 begin
 perform public.hub_driver_goal_periods_v1(t,null);raise exception 'Anonymous caller accepted';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
