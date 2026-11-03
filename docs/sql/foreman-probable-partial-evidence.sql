-- Apply after hub-multi-source-mileage.sql and hub-foreman-transpa-time-cards.sql.
-- Derived evidence only. Raw measurements, identities, financial facts and access grants remain unchanged.
-- High supplemental spikes require strictly bracketing readings and a > max(1000 km, 1500 km/day) jump.
-- Split hours follow globally normalized published TransPA personnel cost shares. This is an allocation estimate, not a calibrated probability.
create or replace function private.hub_meter_quality_series_v1(p_points jsonb,p_from date,p_to date)
returns jsonb language sql immutable set search_path='' as $$
with points as materialized(select *from jsonb_to_recordset(p_points)p(source text,source_id text,at timestamptz,km numeric,quality text)),
times as(select at,min(km)lo,max(km)hi from points group by at),
neighbors as(select *,lag(hi)over(order by at)prev,lead(lo)over(order by at)nxt,lag(at)over(order by at)prev_at,lead(at)over(order by at)next_at from times),
outliers as materialized(select p.*from points p join neighbors n using(at)
 where p.source<>'Fordonskontrollen'and n.lo=n.hi and n.prev<=n.nxt and n.lo>n.nxt and n.lo>n.prev
 and n.lo-n.prev>greatest(1000,extract(epoch from(n.next_at-n.prev_at))/86400*1500)),
clean as materialized(select p.*from points p where not exists(select 1 from outliers o where o.source=p.source and o.source_id=p.source_id)),
limits as(select coalesce(max(at)filter(where at<=p_from::timestamp at time zone 'Europe/Stockholm'),min(at))lo,
 coalesce(min(at)filter(where at>=(p_to+1)::timestamp at time zone 'Europe/Stockholm'),max(at))hi from clean),
window_points as materialized(select p.*from clean p cross join limits l where p.at between l.lo and l.hi),
checked as(select *,lag(hi)over(order by at)prev from(select at,min(km)lo,max(km)hi from window_points group by at)t),
conflicts as(select count(*)filter(where lo<>hi or lo<prev)n from checked),
fallback as materialized(select p.*from clean p cross join conflicts c where c.n=0 or p.source='Fordonskontrollen'),
final_limits as(select coalesce(max(at)filter(where at<=p_from::timestamp at time zone 'Europe/Stockholm'),min(at))lo,
 coalesce(min(at)filter(where at>=(p_to+1)::timestamp at time zone 'Europe/Stockholm'),max(at))hi from fallback),
chosen as materialized(select p.*from fallback p cross join final_limits l where p.at between l.lo and l.hi),
removed as(select o.*from outliers o cross join limits l where o.at between l.lo and l.hi)
select jsonb_build_object('points',coalesce((select jsonb_agg(to_jsonb(p)order by at,source,source_id)from chosen p),'[]'),
 'sources',coalesce((select jsonb_agg(source order by source)from(select distinct source from chosen)s),'[]'),
 'conflicts',c.n,'excluded_readings',coalesce((select jsonb_agg(jsonb_build_object('source',source,'source_id',source_id,'at',at,'km',km,'reason','isolated_high_spike'))from removed),'[]'),
 'selection',case when c.n>0 then 'fordonskontrollen_after_conflict' when exists(select 1 from removed)then 'probable_consistent_series'else 'consistent_meter_series'end,
 'note',case when c.n>0 then 'Motstridiga mätarställningar. Fordonskontrollen används med egna gränsmätningar.'
 when exists(select 1 from removed)then 'Sannolikt milunderlag. Antal undantagna extrema mätarställningar: '||(select count(*)from removed)||'. Bedömningen stöds av mätningarna före och efter. Originalvärdena finns kvar.'end)from conflicts c;
$$;
revoke all on function private.hub_meter_quality_series_v1(jsonb,date,date) from public,anon,authenticated;
create or replace function private.hub_meter_series_v1(p_tenant uuid,p_generation uuid,p_vehicle uuid,p_from date,p_to date)
returns jsonb language sql stable set search_path='' as $$
select private.hub_meter_quality_series_v1(coalesce(jsonb_agg(jsonb_build_object('source',source,'source_id',source_id,'at',recorded_at,'km',reading_km,'quality',quality)),'[]'),p_from,p_to)
from private.hub_kpi_meter_points_v1 where tenant_id=p_tenant and generation_id=p_generation and vehicle_id=p_vehicle;
$$;
CREATE OR REPLACE FUNCTION private.hub_foreman_time_cards_v1(p_tenant uuid, p_report jsonb, p_user uuid, p_months integer[], p_group text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare g uuid:=(p_report->>'generation')::uuid;df date:=(p_report->>'from')::date;dt date:=(p_report->>'to')::date;answer jsonb;
begin
 if auth.uid()is null then raise exception 'Access denied'using errcode='42501';end if;
 with finance as materialized(select f.*from private.hub_transport_leader_facts_v2(p_tenant,df,dt,p_user)f
 where(p_months is null or extract(month from occurred_on)::int=any(p_months))and(p_group is null or coalesce(nullif(business_group,''),'Ej klassificerat')=p_group)),
 refs as materialized(select distinct f.unit_id,f.original->>'time_report_id' id from finance f where f.source='TransPA'and f.category='personnel'and f.original->>'time_report_id'is not null),
 links as materialized(select f.original->>'time_report_id' id,
 count(distinct f.unit_id)=1 and bool_and(f.unit_id is not null)unambiguous,
 count(distinct f.unit_id)>1 and bool_and(f.unit_id is not null and f.amount>0)can_weight,
 sum(f.amount)total_cost
 from private.hub_kpi_prepared_display_facts f where f.tenant_id=p_tenant and f.generation_id=g and f.source='TransPA'and f.category='personnel'
 and f.original->>'time_report_id'in(select id from refs)group by 1),
 unit_weights as materialized(select f.unit_id,f.original->>'time_report_id'id,sum(f.amount)unit_cost
 from private.hub_kpi_prepared_display_facts f where f.tenant_id=p_tenant and f.generation_id=g and f.source='TransPA'and f.category='personnel'
 and f.original->>'time_report_id'in(select id from refs)group by 1,2),
 time_rows as materialized(select r.unit_id,r.id,min(t.work_date)work_date,
 min(t.work_hours)*case when bool_and(l.unambiguous)then 1 else min(w.unit_cost/nullif(l.total_cost,0))end hours,
 bool_and(l.unambiguous)confirmed,
 bool_and(l.unambiguous or l.can_weight)and min(t.work_hours)=max(t.work_hours)and min(t.work_hours)>=0
 and min(t.work_date)=max(t.work_date)valid
 from refs r join links l using(id)join unit_weights w on w.id=r.id and w.unit_id=r.unit_id
 left join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant and t.generation_id=g and t.time_report_id=r.id
 and t.work_date between df and dt and(p_months is null or extract(month from t.work_date)::int=any(p_months))group by r.unit_id,r.id),
 unit_time as(select unit_id,sum(hours)filter(where coalesce(valid,false))hours,
 sum(hours)filter(where coalesce(valid,false)and confirmed)confirmed_hours,
 sum(hours)filter(where coalesce(valid,false)and not confirmed)estimated_hours,
 count(*)filter(where coalesce(valid,false)and not confirmed)estimated_reports,
 count(*)filter(where not coalesce(valid,false))excluded_reports,
 min(work_date)first_time_date,max(work_date)through,count(*)reports,
 count(*)filter(where not coalesce(valid,false)or not confirmed)uncertain_reports,
 count(distinct work_date)registered_days from time_rows group by unit_id),
 amounts as(select t.unit_id,sum(f.amount)filter(where f.kind='revenue')revenue,sum(f.amount)filter(where f.kind='cost')cost
 from unit_time t left join finance f on f.unit_id=t.unit_id and f.occurred_on between df and t.through group by t.unit_id),
 projected as(select t.unit_id,jsonb_build_object('source','TransPA','generation',g,'from',df,'to',t.through,'first_time_date',t.first_time_date,
 'worked_hours',round(t.hours,2),'confirmed_hours',round(coalesce(t.confirmed_hours,0),2),'estimated_hours',round(coalesce(t.estimated_hours,0),2),'estimated_reports',t.estimated_reports,'excluded_reports',t.excluded_reports,'estimated',t.estimated_reports>0,'revenue_per_hour',case when t.excluded_reports=0 then round(a.revenue/nullif(t.hours,0),2)end,'cost_per_hour',case when t.excluded_reports=0 then round(a.cost/nullif(t.hours,0),2)end,
 'matched_revenue',round(a.revenue,2),'matched_cost',round(a.cost,2),'reports',t.reports,'registered_days',t.registered_days,
 'uncertain_reports',t.uncertain_reports,'complete',t.through>=dt and t.excluded_reports=0,
 'basis','TransPA-tid: entydiga rapporter räknas direkt. Delade rapporter fördelas sannolikt enligt Hubs publicerade andel av personalkostnaden; detta är ett fördelningsantagande, inte verifierad körtid. Otillräckligt underbyggda rapporter undantas. Belopp avser samma datumurval.')value
 from unit_time t left join amounts a on a.unit_id=t.unit_id)
 select jsonb_set(p_report,'{units}',coalesce((select jsonb_agg(u||jsonb_build_object('time_metrics',coalesce(p.value,jsonb_build_object('source','TransPA','worked_hours',null,'revenue_per_hour',null,'cost_per_hour',null,'reason','Entydigt kopplad TransPA-arbetstid saknas i urvalet.')))order by ord)
 from jsonb_array_elements(p_report->'units')with ordinality r(u,ord)left join projected p on p.unit_id=(u->>'unit_id')::uuid),'[]'))into answer;
 return answer;
end $function$

;