do $migration$
declare d text;
begin
select pg_get_functiondef('public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)'::regprocedure)into d;
d:=replace(d,'declare output jsonb;','declare output jsonb; time_basis jsonb; hours numeric; time_to date; time_revenue numeric; time_cost numeric; covered int;');
d:=replace(d,$old$output:=output||jsonb_build_object('area_kpis',private.hub_foreman_area_kpis_v1(output,p_months is null));$old$,$new$
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,p_to,p_user,p_unit,p_months,p_group);
time_to:=least((time_basis->>'transpa_through')::date,(time_basis->>'next_through')::date);
if time_to is not null and time_to<p_to then
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,time_to,p_user,p_unit,p_months,p_group);
end if;
hours:=(time_basis->>'worked_hours')::numeric;
select coalesce(sum(f.amount)filter(where f.kind='revenue'),0),coalesce(sum(f.amount)filter(where f.kind='cost'),0)into time_revenue,time_cost
from private.hub_transport_leader_facts_v2(p_tenant,p_from,coalesce(time_to,p_to),p_user)f
where(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
and(p_months is null or extract(month from f.occurred_on)::int=any(p_months));
select count(*)into covered from jsonb_to_recordset(coalesce(time_basis->'units','[]'))u(unit_id uuid,hours numeric)
where u.hours>0 and exists(select 1 from jsonb_to_recordset(output->'units')r(unit_id uuid)where r.unit_id=u.unit_id);
output:=output||jsonb_build_object('area_kpis',private.hub_foreman_area_kpis_v1(output,true)||jsonb_build_object(
'worked_hours',hours,'verified_hours',hours,'covered_units',covered,'hours_complete',false,
'revenue_per_hour',case when hours>0 then time_revenue/hours end,
'cost_per_hour',case when hours>0 then time_cost/hours end,
'result_per_hour',case when hours>0 then(time_revenue-time_cost)/hours end,
'time_from',p_from,'time_to',time_to,'time_sources',time_basis-'units',
'time_revenue',time_revenue,'time_cost',time_cost,'time_result',time_revenue-time_cost));
$new$);
if position('time_basis:=private.hub_foreman_hours_v1'in d)=0 then raise exception 'Area KPI anchor missing';end if;
execute d;
end $migration$;