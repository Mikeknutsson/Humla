create or replace function private.hub_foreman_recurring_fact_v1(
 p_fact private.hub_kpi_prepared_display_facts,p_evidence jsonb,p_from date,p_to date)
returns setof private.hub_kpi_prepared_display_facts
language plpgsql immutable set search_path='' as $fn$
declare result private.hub_kpi_prepared_display_facts; month_start date;month_end date;first_day date;last_day date;day_date date;month_days integer;
begin
 if p_fact.kind='cost' and (p_fact.source='Avskrivningsregister' or (p_fact.source='Preliminär arbetskostnad' and p_evidence#>>'{_humla_provisional_cost,month}' is not null)) then
  month_start:=date_trunc('month',case when p_fact.source='Preliminär arbetskostnad' then (p_evidence#>>'{_humla_provisional_cost,month}')::date else p_fact.occurred_on end)::date;
  month_end:=(month_start+interval '1 month - 1 day')::date;
  month_days:=month_end-month_start+1;
  first_day:=greatest(month_start,p_from,case when p_fact.source='Avskrivningsregister' then coalesce((p_evidence->>'valid_from')::date,p_fact.occurred_on) else month_start end);
  last_day:=least(month_end,p_to,case when p_fact.source='Avskrivningsregister' then coalesce((p_evidence->>'valid_to')::date,month_end) else month_end end);
  for day_date in select d::date from generate_series(first_day::timestamp,last_day::timestamp,interval '1 day') d loop
   result:=p_fact;
   result.fact_id:=p_fact.fact_id||':period-day:'||day_date;
   result.occurred_on:=day_date;
   -- Cumulative cent differences preserve exact full-month totals, including credits.
   result.amount:=round(p_fact.amount*(day_date-month_start+1)/month_days,2)-round(p_fact.amount*(day_date-month_start)/month_days,2);
   result.original:=coalesce(p_fact.original,'{}'::jsonb)||jsonb_build_object('_humla_recurring_period',jsonb_build_object(
    'source_fact_id',p_fact.fact_id,'monthly_amount',p_fact.amount,'month',month_start,'days_in_month',month_days,'day',day_date,
    'method','calendar_day','valid_from',first_day,'valid_to',last_day));
   return next result;
  end loop;
 elsif p_fact.occurred_on between p_from and p_to then return next p_fact;
 end if;
 return;
end $fn$;
revoke all on function private.hub_foreman_recurring_fact_v1(private.hub_kpi_prepared_display_facts,jsonb,date,date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.hub_transport_leader_facts_v2(p_tenant uuid, p_from date, p_to date, p_user uuid)
 RETURNS SETOF private.hub_kpi_prepared_display_facts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare caller uuid:=auth.uid();owner_access boolean;generation uuid;authorized_centers text[];
begin
 if caller is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid scope or period' using errcode='22023';end if;
 select m.role='owner' into owner_access from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=caller and m.status='active';
 if owner_access is null or (p_user is not null and p_user<>caller and not owner_access) then raise exception 'Access denied' using errcode='42501';end if;
 if p_user is not null and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active') then raise exception 'Access denied' using errcode='42501';end if;
 select s.active_generation into generation from private.hub_kpi_report_state s where s.tenant_id=p_tenant;
 if generation is null then raise exception 'Published report unavailable';end if;
 select p.cost_centers into authorized_centers from private.hub_foreman_access_plans p where p.tenant_id=p_tenant and p.auth_user_id=coalesce(p_user,caller) and p.status='active';
 return query
 with candidates as materialized(
  select f as fact,coalesce(b.original,f.original) evidence
  from private.hub_kpi_prepared_display_facts f
  left join private.hub_kpi_prepared_facts b on b.tenant_id=f.tenant_id and b.generation_id=f.generation_id and b.fact_id=f.fact_id
   and f.kind='cost' and f.source='Avskrivningsregister'
  where f.tenant_id=p_tenant and f.generation_id=generation
  and (f.occurred_on between p_from and p_to or
   (f.kind='cost' and (f.source='Avskrivningsregister' or (f.source='Preliminär arbetskostnad' and f.original?'_humla_provisional_cost'))
    and f.occurred_on between date_trunc('month',p_from)::date and (date_trunc('month',p_to)+interval '1 month -1 day')::date))
 )
 select f.* from candidates c
 cross join lateral private.hub_foreman_recurring_fact_v1(c.fact,c.evidence,p_from,p_to) f
 where true
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and ((owner_access and p_user is null and f.cost_center='30') or (not(owner_access and p_user is null) and (case when authorized_centers is not null then f.cost_center=any(authorized_centers) else exists(
 select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,caller)
 and a.unit_id=f.unit_id and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)) end)));
end $function$;
