-- One time basis for report, units, vehicle capacity and hourly figures.
create function private.hub_kpi_worked_time_projection_v1(p_snapshot jsonb,p_next jsonb,p_capacity numeric)
returns jsonb language plpgsql immutable set search_path='' as $$
#variable_conflict use_column
declare answer jsonb:=p_snapshot;fleet jsonb;units jsonb;vehicle_rows jsonb;hourly_categories jsonb;hours numeric;capacity numeric;cost numeric;revenue numeric;worked numeric;
begin
 with native as(select v->>'vehicle' vehicle,max((v->>'hours')::numeric)hours,max((v->>'available_hours')::numeric)capacity
  from jsonb_array_elements(coalesce(p_snapshot#>'{transpa_vehicle_time,vehicles}','[]'))v group by 1),
 extra as(select v->>'vehicle' vehicle,sum((v->>'hours')::numeric)hours from jsonb_array_elements(coalesce(p_next->'vehicles','[]'))v group by 1),
 combined as(select coalesce(n.vehicle,e.vehicle)vehicle,coalesce(n.hours,0)+coalesce(e.hours,0)hours,
  coalesce(nullif(n.capacity,0),p_capacity)capacity,coalesce(n.hours,0)transpa_hours,coalesce(e.hours,0)next_hours
  from native n full join extra e using(vehicle))
 select coalesce(jsonb_agg(jsonb_build_object('vehicle',vehicle,'hours',hours,'occupied_hours',hours,'available_hours',capacity,
  'transpa_hours',transpa_hours,'next_hours',next_hours,'utilization',round(hours/nullif(capacity,0)*100,1))order by vehicle),'[]'),sum(hours),sum(capacity)
 into fleet,hours,capacity from combined where hours>0;
 with source as(select v from jsonb_array_elements(coalesce(p_snapshot->'vehicles','[]'))v),eligible as(
  select s.v,f from source s left join jsonb_array_elements(fleet)f on f->>'vehicle'=s.v->>'vehicle')
 select coalesce(jsonb_agg(v||jsonb_build_object('worked_hours',(f->>'hours')::numeric,'occupied_hours',(f->>'hours')::numeric,
  'available_hours',(f->>'available_hours')::numeric,'utilization',(f->>'utilization')::numeric,
  'cost_per_hour',round((v->>'cost')::numeric/nullif((f->>'hours')::numeric,0),2),
  'revenue_per_hour',round((v->>'revenue')::numeric/nullif((f->>'hours')::numeric,0),2))),'[]'),
  sum((v->>'cost')::numeric)filter(where f is not null),sum((v->>'revenue')::numeric)filter(where f is not null)
 into vehicle_rows,cost,revenue from eligible;
 with source as(select u,n,
  case when u->>'worked_hours'is not null or n->>'net_project_hours'is not null then coalesce((u->>'worked_hours')::numeric,0)+coalesce((n->>'net_project_hours')::numeric,0)end h,
  coalesce((u->>'occupied_hours')::numeric,0)+coalesce((select sum((v->>'hours')::numeric)from jsonb_array_elements(coalesce(p_next->'vehicles','[]'))v where v->>'unit_key'=u->>'key'),0) occupied,
  (select sum((f->>'available_hours')::numeric)from jsonb_array_elements(fleet)f where f->>'vehicle'in(
   select c->>'vehicle'from jsonb_array_elements(coalesce(u->'children','[]'))c
   union select v->>'vehicle'from jsonb_array_elements(coalesce(p_next->'vehicles','[]'))v where v->>'unit_key'=u->>'key'))available
  from jsonb_array_elements(coalesce(p_snapshot->'economic_units','[]'))u
  left join jsonb_array_elements(coalesce(p_next->'units','[]'))n on n->>'key'=u->>'key')
 select coalesce(jsonb_agg(u||jsonb_build_object('transpa_worked_hours',u->'worked_hours','next_project_hours',n->'project_hours',
  'next_workshop_hours',n->'workshop_hours','worked_hours',round(h,2),'occupied_hours',case when occupied>0 then round(occupied,2)end,
  'available_hours',case when occupied>0 then available end,'utilization',case when occupied>0 then round(occupied/nullif(available,0)*100,1)end,
  'cost_per_hour',round((u->>'cost')::numeric/nullif(h,0),2),'revenue_per_hour',round((u->>'revenue')::numeric/nullif(h,0),2))),'[]')into units from source;
 worked:=case when coalesce((p_snapshot#>>'{driver_productivity,total_hours}')::numeric,0)>0 or coalesce((p_next->>'available')::boolean,false)
  then coalesce((p_snapshot#>>'{driver_productivity,total_hours}')::numeric,0)+coalesce((p_next->>'net_project_hours')::numeric,0)end;
 answer:=answer||jsonb_build_object('economic_units',units,'vehicles',vehicle_rows,'next_time',p_next,
  'worked_time',jsonb_build_object('worked_hours',round(worked,2),'transpa_hours',p_snapshot#>'{driver_productivity,total_hours}',
   'next_project_hours',p_next->'project_hours','next_added_hours',p_next->'net_project_hours','overlap_hours',p_next->'overlap_hours',
   'vehicle_hours',hours,'available_vehicle_hours',capacity,'eligible_vehicle_count',jsonb_array_length(fleet),'vehicles',fleet,
   'basis','TransPA + godkänd NEXT-projekttid efter person/dag-avräkning. Frånvaro, OB-tillägg och verkstadstid ingår inte. Endast fordon med positiva timmar i valt urval ingår i fordonskapacitet och aggregerade fordonskostnader per timme.'),
  'transpa_vehicle_time',coalesce(answer->'transpa_vehicle_time','{}')||jsonb_build_object('reported_hours',hours,'available_hours',capacity,
   'vehicle_count',jsonb_array_length(fleet),'utilization',round(hours/nullif(capacity,0)*100,1),'vehicles',fleet));
 answer:=jsonb_set(answer,'{metrics,vehicle_utilization}',coalesce(to_jsonb(round(hours/nullif(capacity,0)*100,1)),'null'));
 select coalesce(jsonb_object_agg(category||'_cost_per_hour',round(amount/nullif(hours,0),2)),'{}')into hourly_categories
 from(select c.key category,sum(c.value::numeric)amount from jsonb_array_elements(vehicle_rows)v,
  jsonb_each_text(coalesce(v->'cost_categories','{}'))c where (v->>'worked_hours')::numeric>0 group by c.key)s;
 answer:=jsonb_set(answer,'{cost_efficiency}',coalesce(answer->'cost_efficiency','{}')||
  coalesce((select jsonb_object_agg(k,'null'::jsonb)from jsonb_object_keys(coalesce(answer->'cost_efficiency','{}'))k where k like '%_cost_per_hour'),'{}')||
  hourly_categories||jsonb_build_object('worked_hours',hours,
  'total_cost_per_hour',round(cost/nullif(hours,0),2),'result_per_hour',round((revenue-cost)/nullif(hours,0),2)));
 answer:=jsonb_set(answer,'{efficiency}',coalesce(answer->'efficiency','{}')||jsonb_build_object('worked_hours',hours,'revenue_per_worked_hour',round(revenue/nullif(hours,0),2)));
 return answer;
end$$;
revoke all on function private.hub_kpi_worked_time_projection_v1(jsonb,jsonb,numeric)from public,anon,authenticated;

do $patch$
declare d text;
begin
 d:=pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 if position('hub_kpi_worked_time_projection_v1' in d)>0 then raise exception 'Projection already applied';end if;
 d:=replace(d,'''occupied_hours'',vt.hours,', $categories$'cost_categories',coalesce((select jsonb_object_agg(category,amount)from(
  select f.category,sum(f.amount)amount from facts f where f.kind='cost'and f.vehicle=v.vehicle group by f.category)c),'{}'::jsonb),'occupied_hours',vt.hours,$categories$);
 d:=replace(d,' return output;', $insert$
 output:=private.hub_kpi_worked_time_projection_v1(output,
  private.hub_kpi_next_time_period_v1(p_tenant_id,p_fiscal_year,months,p_filters),
  (select count(*)*coalesce((select vehicle_capacity_hours_per_day from private.hub_kpi_prepared_kpi_settings where tenant_id=p_tenant_id and generation_id=report_generation),8)
   from generate_series(fy_from,fy_to,interval '1 day')d where extract(month from d)::int=any(months)
    and extract(isodow from d)between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)));
 return output;$insert$);
 execute d;
end $patch$;
