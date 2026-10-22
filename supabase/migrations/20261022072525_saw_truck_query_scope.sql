-- Read-only activity projection; no extra financial postings or permanent inferred links.
create or replace function public.hub_saw_truck_followup_v1(p_tenant uuid,p_from date,p_to date,p_user uuid default null,p_unit uuid default null,p_months integer[] default null,p_group text default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare answer jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and(p_user is null or p_user=auth.uid() or m.role='owner'))then raise exception 'Access denied'using errcode='42501';end if;
 if p_user is not null and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active')then raise exception 'Access denied'using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period';end if;
 if p_months is not null and (cardinality(p_months)=0 or not p_months<@array[1,2,3,4,5,6,7,8,9,10,11,12])then raise exception 'Invalid months';end if;
 -- Full month cost pools retain the existing authorization and dated assignment scope.
 -- This includes monthly fixed costs even when the requested date range starts mid-month.
 with bounds as(select date_trunc('month',p_from)::date first_day,(date_trunc('month',p_to)+interval '1 month'-interval '1 day')::date last_day),
 date_scope as(select first_day,least(last_day,first_day+366)last_day from bounds
 union all select first_day+367,last_day from bounds where last_day>first_day+366),
 candidate_units as materialized(select distinct f.unit_id from private.hub_kpi_prepared_facts f
 join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 where f.tenant_id=p_tenant and f.source='Workify'and f.kind='revenue'and f.original->>'Artikelnummer'='12-04'
 and f.occurred_on between p_from and p_to and(p_unit is null or f.unit_id=p_unit)),
 authorized as materialized(select f.* from date_scope m cross join lateral private.hub_transport_leader_facts_v2(p_tenant,m.first_day,m.last_day,p_user)f
 where (p_unit is null or f.unit_id=p_unit)and(p_months is null or extract(month from f.occurred_on)::int=any(p_months))
 and exists(select 1 from candidate_units c where c.unit_id is not distinct from f.unit_id)),
 full_facts as materialized(select f.*,p.original evidence,date_trunc('month',f.occurred_on)::date month_start,
 nullif(trim(p.original->>'Artikelnummer'),'')article,
 nullif(trim(p.original->>'Ordernummer'),'')order_number,
 case when lower(trim(p.original->>'Enhet'))in('tim','h','timme','timmar') and trim(p.original->>'Kvantitet')~'^-?[0-9]+([.,][0-9]+)?$'
 then replace(trim(p.original->>'Kvantitet'),',','.')::numeric end billed_hours
 from authorized f join private.hub_kpi_prepared_facts p on p.tenant_id=f.tenant_id and p.generation_id=f.generation_id and p.fact_id=f.fact_id),
 saw as materialized(select *,coalesce(order_number,'Saknar order: '||fact_id)order_key from full_facts
 where kind='revenue' and source='Workify' and article='12-04' and occurred_on between p_from and p_to
 and(p_group is null or coalesce(nullif(business_group,''),'Ej klassificerat')=p_group)),
 unit_months as(select unit_id,month_start,sum(billed_hours)filter(where billed_hours>0) all_billed_hours,
 count(*)filter(where kind='cost') cost_rows,coalesce(sum(amount)filter(where kind='cost'),0) cost
 from full_facts where kind='cost' or (kind='revenue'and source='Workify') group by unit_id,month_start),
 estimated as materialized(select s.*,case when s.unit_id is not null and s.billed_hours>0 and m.all_billed_hours>0 and m.cost_rows>0 then m.cost*s.billed_hours/m.all_billed_hours end estimated_cost
 from saw s left join unit_months m on m.unit_id=s.unit_id and m.month_start=s.month_start),
 saw_months as(select unit_id,month_start,sum(billed_hours)filter(where billed_hours>0) saw_hours from saw group by unit_id,month_start),
 cost_categories as(select f.category,sum(f.amount*s.saw_hours/m.all_billed_hours)estimated_cost
 from full_facts f join saw_months s on s.unit_id=f.unit_id and s.month_start=f.month_start
 join unit_months m on m.unit_id=f.unit_id and m.month_start=f.month_start
 where f.kind='cost' and s.saw_hours>0 and m.all_billed_hours>0 group by f.category),
 saw_days as(select unit_id,min(unit_name)unit_name,occurred_on,sum(billed_hours)filter(where billed_hours>0)saw_hours,count(distinct order_key)orders from saw group by unit_id,occurred_on),
 time_rows as(select f.unit_id,f.occurred_on,f.source,
 coalesce(f.evidence->>'time_report_id',f.evidence#>>'{_humla_approved_time,row_id}',f.fact_id)time_key,
 max(case when f.source='TransPA' and f.evidence->>'work_hours'~'^[0-9]+([.][0-9]+)?$' then (f.evidence->>'work_hours')::numeric
 when f.evidence#>>'{_humla_approved_time,hours}'~'^[0-9]+([.][0-9]+)?$' then (f.evidence#>>'{_humla_approved_time,hours}')::numeric end)hours
 from full_facts f join saw_days s on s.unit_id=f.unit_id and s.occurred_on=f.occurred_on
 where f.kind='cost' and f.category='personnel' and not(f.evidence?'_humla_cost_rule')
 group by f.unit_id,f.occurred_on,f.source,coalesce(f.evidence->>'time_report_id',f.evidence#>>'{_humla_approved_time,row_id}',f.fact_id)),
 days as(select s.*,sum(t.hours)recorded_day_hours,string_agg(distinct t.source,', ')time_sources from saw_days s
 left join time_rows t on t.unit_id=s.unit_id and t.occurred_on=s.occurred_on group by s.unit_id,s.unit_name,s.occurred_on,s.saw_hours,s.orders),
 orders as(select order_key,order_number,unit_id,min(unit_name)unit_name,min(occurred_on)first_date,max(occurred_on)last_date,
 min(evidence->>'Kundnamn')customer,min(evidence->>'Rubrik')description,sum(amount)revenue,sum(billed_hours)hours,
 sum(estimated_cost)estimated_cost,count(*)filter(where estimated_cost is null)unestimated_rows,
 case when count(*)filter(where estimated_cost is null)=0 then sum(amount)-sum(estimated_cost)end estimated_result
 from estimated group by order_key,order_number,unit_id),
 units as(select unit_id,min(unit_name)unit_name,sum(amount)revenue,sum(billed_hours)hours,sum(estimated_cost)estimated_cost,
 count(*)filter(where estimated_cost is null)unestimated_rows,count(distinct order_key)orders from estimated group by unit_id)
 select jsonb_build_object('summary',(select jsonb_build_object('revenue',sum(amount),'hours',sum(billed_hours),'orders',count(distinct order_key),'rows',count(*),
 'estimated_cost',sum(estimated_cost),'unestimated_rows',count(*)filter(where estimated_cost is null),
 'missing_hour_rows',count(*)filter(where billed_hours is null),
 'estimated_result',case when count(*)>0 and count(*)filter(where estimated_cost is null)=0 then sum(amount)-sum(estimated_cost)end,
 'recorded_day_hours',(select sum(recorded_day_hours)from days),'days_without_time',(select count(*)from days where recorded_day_hours is null))from estimated),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o)order by last_date desc,order_key),'[]')from orders o),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)order by unit_name),'[]')from units u),
 'days',(select coalesce(jsonb_agg(to_jsonb(d)order by occurred_on desc,unit_name),'[]')from days d),
 'cost_categories',(select coalesce(jsonb_agg(to_jsonb(c)order by category),'[]')from cost_categories c),
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant))into answer;
 return answer;
end $$;
revoke all on function public.hub_saw_truck_followup_v1(uuid,date,date,uuid,uuid,integer[],text)from public,anon;
grant execute on function public.hub_saw_truck_followup_v1(uuid,date,date,uuid,uuid,integer[],text)to authenticated;
