CREATE OR REPLACE FUNCTION private.hub_foreman_mileage_v1(p_tenant uuid, p_report jsonb, p_user uuid, p_months integer[], p_group text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
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
 source_series as materialized(select a.asset_id vehicle_id,private.hub_meter_series_v1(p_tenant,g,a.asset_id,df,dt) value
 from assets a where exists(select 1 from configured c where c.registration=a.registration)),
 bounds as materialized(select s.vehicle_id,min(p.at)lo,max(p.at)hi from source_series s cross join lateral jsonb_to_recordset(s.value->'points')p(at timestamptz)group by s.vehicle_id),
 classified_vehicles as materialized(
 select r.registration,p.valid_from,p.valid_to,p.cost_center
 from private.hub_kpi_prepared_kpi_project_classification_periods p
 cross join lateral unnest(p.registrations) r(registration)
 where (all_transport or centers is not null) and p.tenant_id=p_tenant and p.generation_id=g
 and p.valid_from<=dt and (p.valid_to is null or p.valid_to>=df)
 and r.registration in (select registration from configured)
 ),
 permitted_vehicle_days as materialized(
 select c.registration,c.d
 from (select distinct registration,d from configured) c
 join classified_vehicles p on p.registration=c.registration
 and p.valid_from<=c.d and (p.valid_to is null or p.valid_to>=c.d)
 group by c.registration,c.d
 having count(distinct p.cost_center)=1
 and bool_and(case when all_transport then p.cost_center='30' else p.cost_center=any(centers) end)
 ),
 scoped_days as materialized(select c.*,a.asset_id
 from configured c join assets a on a.registration=c.registration
 where (case when all_transport or centers is not null then exists(
 select 1 from permitted_vehicle_days p where p.registration=c.registration and p.d=c.d)
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
 jsonb_agg(jsonb_build_object('from',date_from,'to',date_to,'vehicle',registration,'mil',round((evidence->>'distance_km')::numeric/10,2),'basis',evidence->>'basis','sources',evidence->'sources')order by date_from) segments from good group by id),
 published as(select r.id,jsonb_build_object(
 'source',coalesce((select string_agg(distinct src, ' + ' order by src)from jsonb_array_elements(d.segments)s cross join lateral jsonb_array_elements_text(s->'sources')src),'Humla Hub'),
 'source_conflicts',(select coalesce(max((s.value->>'conflicts')::int),0)from source_series s where exists(select 1 from scoped_days sd where sd.id=r.id and sd.asset_id=s.vehicle_id)),
 'source_note',(select max(s.value->>'note')from source_series s where exists(select 1 from scoped_days sd where sd.id=r.id and sd.asset_id=s.vehicle_id)),
 'generation',g,'distance_mil',round(d.mil,2),
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
end $function$
;
