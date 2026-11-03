do $fix$
declare definition text;
begin
 select pg_get_functiondef('private.hub_kpi_prepared_distance_v1(uuid,uuid,date,date)'::regprocedure) into definition;
 definition:=replace(definition,'private.hub_kpi_prepared_distance_v1(p_tenant uuid, p_vehicle uuid, p_from date, p_to date)','private.hub_foreman_meter_span_v1(p_tenant uuid, p_generation uuid, p_vehicle uuid, p_from date, p_to date)');
 if strpos(definition,'private.hub_foreman_meter_span_v1')=0 then raise exception 'Unexpected distance function signature';end if;
 definition:=replace(definition,'report_generation uuid:=private.hub_kpi_active_report_generation_v1(p_tenant);','report_generation uuid:=p_generation;');
 if strpos(definition,'hub_kpi_active_report_generation_v1')>0 then raise exception 'Unexpected generation initializer';end if;
 execute definition;
end $fix$;
revoke all on function private.hub_foreman_meter_span_v1(uuid,uuid,uuid,date,date) from public,anon,authenticated;

create or replace function private.hub_foreman_mileage_v1(p_tenant uuid,p_report jsonb,p_user uuid,p_months integer[],p_group text)
returns jsonb language plpgsql stable set search_path='' set jit='off' as $fn$
declare g uuid:=(p_report->>'generation')::uuid; df date:=(p_report->>'from')::date; dt date:=(p_report->>'to')::date;
 result jsonb; centers text[]; all_transport boolean;
begin
 if auth.uid() is null then raise exception 'Access denied' using errcode='42501';end if;
 select p.cost_centers into centers from private.hub_foreman_access_plans p
 where p.tenant_id=p_tenant and p.auth_user_id=coalesce(p_user,auth.uid()) and p.status='active';
 select p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') into all_transport;
 with report_units as materialized(select u,(u->>'unit_id')::uuid id from jsonb_array_elements(p_report->'units')u where u->>'unit_id' is not null),
 days as materialized(select d::date d from generate_series(df,dt,interval '1 day')d where p_months is null or extract(month from d)::int=any(p_months)),
 versions as materialized(
 select u.id,v.valid_from,v.valid_to,coalesce((v.payload->>'enabled')::boolean,u.enabled) enabled,
 nullif(trim(v.payload->>'main_vehicle'),'') registration,v.payload->>'business_group_id' group_id
 from private.hub_kpi_prepared_kpi_units u join private.hub_kpi_prepared_kpi_unit_periods v on v.tenant_id=u.tenant_id and v.generation_id=u.generation_id and v.unit_id=u.id
 where u.tenant_id=p_tenant and u.generation_id=g and u.id in(select id from report_units)
 union all
 select u.id,u.valid_from,u.valid_to,u.enabled,case when u.unit_type='vehicle' and cardinality(u.registrations)=1 then u.registrations[1] end,null
 from private.hub_kpi_prepared_kpi_units u where u.tenant_id=p_tenant and u.generation_id=g and u.id in(select id from report_units)
 and not exists(select 1 from private.hub_kpi_prepared_kpi_unit_periods v where v.tenant_id=p_tenant and v.generation_id=g and v.unit_id=u.id)
 ),
 configured as materialized(select r.id,d.d,min(v.registration) registration,min(v.group_id) group_id
 from report_units r cross join days d join versions v on v.id=r.id and v.valid_from<=d.d and(v.valid_to is null or v.valid_to>=d.d)
 group by r.id,d.d having count(*)=1 and bool_and(v.enabled) and min(v.registration)is not null),
 assets as materialized(select public.hub_normalize_vehicle_registration(o.data->>'registration_number') registration,(array_agg(o.id))[1] asset_id
 from private.hub_kpi_prepared_hub_objects o where o.tenant_id=p_tenant and o.generation_id=g and o.object_type='Vehicle' group by 1 having count(*)=1),
 bounds as materialized(select vehicle_id,min(recorded_at) lo,max(recorded_at) hi from private.hub_kpi_prepared_hub_vehicle_meter_readings
 where tenant_id=p_tenant and generation_id=g and reading_type='odometer_km' group by vehicle_id),
 scoped_days as materialized(select c.*,a.asset_id
 from configured c join assets a on a.registration=c.registration
 where (case when all_transport or centers is not null then exists(
 select 1 from private.hub_kpi_prepared_kpi_project_classification_periods p where p.tenant_id=p_tenant and p.generation_id=g and c.registration=any(p.registrations)
 and p.valid_from<=c.d and(p.valid_to is null or p.valid_to>=c.d)
 group by c.registration having count(distinct p.cost_center)=1 and bool_and(case when all_transport then p.cost_center='30' else p.cost_center=any(centers) end))
 else exists(select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,auth.uid()) and a.unit_id=c.id and a.valid_from<=c.d and(a.valid_to is null or a.valid_to>=c.d))end)
 and (p_group is null or exists(select 1 from private.hub_kpi_prepared_kpi_business_groups b where b.tenant_id=p_tenant and b.generation_id=g and b.id::text=c.group_id and b.name=p_group))),
 covered_days as materialized(select s.*,s.d-row_number()over(partition by s.id,s.asset_id order by s.d)::int island
 from scoped_days s join bounds b on b.vehicle_id=s.asset_id where b.lo<=s.d::timestamp at time zone 'Europe/Stockholm' and b.hi>=(s.d+1)::timestamp at time zone 'Europe/Stockholm'),
 spans as materialized(select id,asset_id,min(registration) registration,min(d) date_from,max(d) date_to,count(*) n
 from covered_days group by id,asset_id,island),
 estimates as materialized(select s.*,private.hub_foreman_meter_span_v1(p_tenant,g,s.asset_id,s.date_from,s.date_to) evidence from spans s),
 good as materialized(select * from estimates where (evidence->>'distance_km')::numeric>=0),
 financial as materialized(select f.unit_id,f.occurred_on,f.kind,f.category,f.amount
 from private.hub_transport_leader_facts_v2(p_tenant,df,dt,p_user) f
 where (p_months is null or extract(month from f.occurred_on)::int=any(p_months)) and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)),
 amounts as(select s.id,sum(f.amount)filter(where f.kind='cost') cost,sum(f.amount)filter(where f.kind='cost'and f.category='fuel') fuel
 from good s left join financial f on f.unit_id=s.id and f.occurred_on between s.date_from and s.date_to group by s.id),
 distance as(select id,sum((evidence->>'distance_km')::numeric)/10 mil,sum(n) covered_days,min(date_from) date_from,max(date_to) date_to,
 bool_or(evidence->>'basis'='interpolated') estimated,
 jsonb_agg(jsonb_build_object('from',date_from,'to',date_to,'vehicle',registration,'mil',round((evidence->>'distance_km')::numeric/10,2),'basis',evidence->>'basis')order by date_from) segments from good group by id),
 published as(select r.id,jsonb_build_object(
 'source','Fordonskontrollen','generation',g,'distance_mil',round(d.mil,2),
 'cost_per_mil',round(a.cost/nullif(d.mil,0),2),'fuel_cost_per_mil',round(a.fuel/nullif(d.mil,0),2),
 'matched_cost',round(a.cost,2),'matched_fuel_cost',round(a.fuel,2),
 'from',d.date_from,'to',d.date_to,'covered_days',coalesce(d.covered_days,0),'selected_days',(select count(*)from days),
 'complete',coalesce(d.covered_days=(select count(*)from days),false),'estimated',coalesce(d.estimated,false),
 'status',case when d.mil=0 then 'zero_distance' when d.mil is null then 'missing' when d.covered_days<(select count(*)from days)then 'partial' else 'complete'end,
 'segments',coalesce(d.segments,'[]'::jsonb),
 'reason',case when d.mil is null then 'Mätningar eller säker huvudbilskoppling saknas för perioden.' when d.mil=0 then 'Ingen körsträcka i mätunderlaget; kr/mil kan inte beräknas.'end) mileage
 from report_units r left join distance d on d.id=r.id left join amounts a on a.id=r.id)
 select jsonb_set(p_report,'{units}',coalesce((select jsonb_agg(case when p.id is not null then u||jsonb_build_object('mileage',p.mileage)else u end order by ord)
 from jsonb_array_elements(p_report->'units')with ordinality r(u,ord) left join published p on p.id=(u->>'unit_id')::uuid),'[]'))into result;
 return result;
end $fn$;
revoke all on function private.hub_foreman_mileage_v1(uuid,jsonb,uuid,integer[],text) from public,anon,authenticated;

do $change$
declare definition text;
begin
 select pg_get_functiondef('public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)'::regprocedure)into definition;
 if strpos(definition,'private.hub_foreman_mileage_v1')=0 then
  if strpos(definition,' return output;')=0 then raise exception 'Unexpected scorecard definition; no change applied';end if;
  execute replace(definition,' return output;',' return private.hub_foreman_mileage_v1(p_tenant,output,p_user,p_months,p_group);');
 end if;
end $change$;
notify pgrst,'reload schema';