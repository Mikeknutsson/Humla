CREATE OR REPLACE FUNCTION private.hub_transport_leader_facts_v2(p_tenant uuid, p_from date, p_to date, p_user uuid)
 RETURNS SETOF private.hub_kpi_prepared_display_facts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare caller uuid:=auth.uid();owner_access boolean;generation uuid;authorized_centers text[]; combined_transport boolean:=coalesce(p_user='00000000-0000-0000-0000-000000000030'::uuid,false);
begin
 if caller is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid scope or period' using errcode='22023';end if;
 select m.role='owner' into owner_access from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=caller and m.status='active';
 if owner_access is null or (p_user is not null and p_user<>caller and not owner_access) then raise exception 'Access denied' using errcode='42501';end if;
 if p_user is not null and not combined_transport and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active') then raise exception 'Access denied' using errcode='42501';end if;
 select s.active_generation into generation from private.hub_kpi_report_state s where s.tenant_id=p_tenant;
 if generation is null then raise exception 'Published report unavailable';end if;
 select p.cost_centers into authorized_centers from private.hub_foreman_access_plans p where p.tenant_id=p_tenant and p.auth_user_id=coalesce(p_user,caller) and p.status='active';
 return query
 with transport_profiles as materialized (
  select m.user_id,p.cost_centers
  from public.hub_tenant_members m
  left join private.hub_foreman_access_plans p on p.tenant_id=m.tenant_id and p.auth_user_id=m.user_id and p.status='active'
  where combined_transport and m.tenant_id=p_tenant and m.status='active'
   and trim(m.display_name) ~* '^(marcus|ola|pierre)([[:space:]]|$)'
 ), recurring as materialized(
  select f as fact,coalesce(b.original,f.original) evidence
  from private.hub_kpi_prepared_display_facts f
  left join private.hub_kpi_prepared_facts b on b.tenant_id=f.tenant_id and b.generation_id=f.generation_id and b.fact_id=f.fact_id
   and f.source='Avskrivningsregister'
  where f.tenant_id=p_tenant and f.generation_id=generation
   and f.kind='cost' and (f.source='Avskrivningsregister' or (f.source='Preliminär arbetskostnad' and f.original?'_humla_provisional_cost'))
   and f.occurred_on between date_trunc('month',p_from)::date and (date_trunc('month',p_to)+interval '1 month -1 day')::date
 ), scoped as(
  select f.* from private.hub_kpi_prepared_display_facts f
  where f.tenant_id=p_tenant and f.generation_id=generation and f.occurred_on between p_from and p_to
   and not coalesce(f.kind='cost' and (f.source='Avskrivningsregister' or (f.source='Preliminär arbetskostnad' and f.original?'_humla_provisional_cost')),false)
  union all
  select f.* from recurring r cross join lateral private.hub_foreman_recurring_fact_v1(r.fact,r.evidence,p_from,p_to) f
 )
 select f.generation_id,f.tenant_id,f.fiscal_year,f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,
 case when extra.include then ('00000000-0000-0000-0000-0000000000'||b.bucket)::uuid else f.unit_id end,
 case when extra.include then case b.bucket when 31 then 'Tippavgifter – Återvinning' when 32 then 'Tippavgifter – Trading Material' when 33 then 'Ej klassificerat – Workify' else 'Övriga poster' end else f.unit_name end,
 case when extra.include then 'Ej tilldelat – Transport' else f.business_group end,
 f.source,f.cost_center,f.original from scoped f
 cross join lateral (
  select combined_transport and owner_access and exists (
   select 1 from transport_profiles p
   where case when p.cost_centers is not null then f.cost_center=any(p.cost_centers) else exists (
    select 1 from public.hub_transport_leader_units a
    where a.tenant_id=p_tenant and a.user_id=p.user_id and a.unit_id=f.unit_id
     and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
   ) end
  ) as assigned
 ) a
 cross join lateral (
  select case
   when f.category='tipp_deponi' and f.business_group='Återvinning' then 31
   when f.category='tipp_deponi' and f.business_group='Trading Material' then 32
   when f.business_group='Ej klassificerat' and f.source='Workify' then 33
   else 34
  end as bucket
 ) b
 cross join lateral (select combined_transport and owner_access and not a.assigned and f.cost_center='30' as include) extra
 where not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and (case when combined_transport then owner_access and (a.assigned or f.cost_center='30') else ((owner_access and p_user is null and f.cost_center='30') or (not(owner_access and p_user is null) and (case when authorized_centers is not null then f.cost_center=any(authorized_centers) else exists(
 select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,caller)
 and a.unit_id=f.unit_id and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)) end))) end);
end $function$;