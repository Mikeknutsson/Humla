-- Canonical targets and scoped, published financial facts. No ingestion or allocation changes.
create table private.hub_transport_unit_targets_v2(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,unit_id uuid not null references public.hub_objects(id),
 valid_from date not null,valid_to date,margin_percent numeric not null check(margin_percent between -100 and 100),
 reason text not null,created_by uuid not null,created_at timestamptz not null default now(),
 check(valid_to is null or valid_to>=valid_from),unique(tenant_id,unit_id,valid_from));
alter table private.hub_transport_unit_targets_v2 enable row level security;
revoke all on private.hub_transport_unit_targets_v2 from public,anon,authenticated;

create function private.hub_transport_leader_facts_v2(p_tenant uuid,p_from date,p_to date,p_user uuid)
returns setof private.hub_kpi_prepared_display_facts language plpgsql stable security definer set search_path='' as $$
declare caller uuid:=auth.uid();owner_access boolean;generation uuid;
begin
 if caller is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid scope or period' using errcode='22023';end if;
 select m.role='owner' into owner_access from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=caller and m.status='active';
 if owner_access is null or (p_user is not null and p_user<>caller and not owner_access) then raise exception 'Access denied' using errcode='42501';end if;
 if p_user is not null and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active') then raise exception 'Access denied' using errcode='42501';end if;
 select s.active_generation into generation from private.hub_kpi_report_state s where s.tenant_id=p_tenant;
 if generation is null then raise exception 'Published report unavailable';end if;
 return query select f.* from private.hub_kpi_prepared_display_facts f
 where f.tenant_id=p_tenant and f.generation_id=generation and f.occurred_on between p_from and p_to
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and ((owner_access and p_user is null and f.cost_center='30') or (not(owner_access and p_user is null) and exists(
 select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,caller)
 and a.unit_id=f.unit_id and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on))));
end $$;
revoke all on function private.hub_transport_leader_facts_v2(uuid,date,date,uuid) from public,anon,authenticated;

create function public.hub_transport_leader_scorecard_v2(p_tenant uuid,p_from date,p_to date,p_user uuid default null,p_unit uuid default null,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare output jsonb;
begin
 if p_page is null or p_page<0 or p_page>10000 then raise exception 'Invalid page';end if;
 with facts as materialized(select f.*,case when f.category='material' then 'material' when f.category in ('tipp','tipp_deponi') then 'tipp' when f.category='transport' then 'transport' else 'other' end section
 from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user) f where p_unit is null or f.unit_id=p_unit),
 enriched as materialized(select f.*,t.margin_percent from facts f left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id and t.valid_from<=f.occurred_on and(t.valid_to is null or t.valid_to>=f.occurred_on)),
 totals as(select unit_id,min(unit_name) unit_name,count(*) rows,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,
 count(*)filter(where kind='revenue' and amount<>0 and margin_percent is null) missing_targets,
 sum(amount*margin_percent/100)filter(where kind='revenue') target_result
 from enriched group by unit_id),
 units as(select *,revenue-cost result,case when revenue<>0 then (revenue-cost)/revenue*100 end margin_percent,
 case when missing_targets=0 and revenue<>0 and target_result is not null then target_result/revenue*100 end target_margin_percent,
 case when missing_targets=0 and target_result is not null then revenue-cost-target_result end deviation_amount,
 case when missing_targets=0 and revenue<>0 and target_result is not null then ((revenue-cost)-target_result)/revenue*100 end deviation_pp from totals),
 sections as(select section,coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,count(*) rows from facts group by section),
 details as(select fact_id,occurred_on,kind,amount,category,unit_id,unit_name,project,vehicle,source,cost_center,
 original#>>'{_humla_invoice,order_number}' order_number,original#>>'{_humla_invoice,customer_name}' customer,
 original->'_humla_cost_rule' allocation_rule,original from facts order by occurred_on desc,fact_id limit 100 offset p_page*100)
 select jsonb_build_object('from',p_from,'to',p_to,
 'scope',case when p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') then 'transport' else 'assigned' end,
 'summary',(select jsonb_build_object('revenue',sum(revenue),'cost',sum(cost),'result',sum(result),'rows',sum(rows),'unassigned_rows',coalesce(sum(rows)filter(where unit_id is null),0))from units),
 'units',(select coalesce(jsonb_agg(to_jsonb(u) order by unit_name nulls last),'[]')from units u),
 'sections',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('result',case when not exists(select 1 from sections c where c.section='other' and c.cost<>0) then revenue-cost end,'margin_percent',case when revenue<>0 and not exists(select 1 from sections c where c.section='other' and c.cost<>0) then (revenue-cost)/revenue*100 end)),'[]')from sections s),
 'transactions',case when p_unit is not null then(select coalesce(jsonb_agg(to_jsonb(d)),'[]')from details d)else '[]'::jsonb end,
 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant)) into output;
 return output;
end $$;
revoke all on function public.hub_transport_leader_scorecard_v2(uuid,date,date,uuid,uuid,integer) from public,anon;
grant execute on function public.hub_transport_leader_scorecard_v2(uuid,date,date,uuid,uuid,integer) to authenticated;

create function public.hub_transport_unit_target_save_v2(p_tenant uuid,p_unit uuid,p_from date,p_margin numeric,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') then raise exception 'Owner required' using errcode='42501';end if;
 if p_from is null or p_margin is null or p_margin not between -100 and 100 or length(trim(coalesce(p_reason,''))) not between 3 and 1000 then raise exception 'Invalid target';end if;
 if not exists(select 1 from public.hub_objects o where o.id=p_unit and o.tenant_id=p_tenant and o.object_type='EconomicUnit') then raise exception 'Canonical economic unit required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||p_unit::text||':margin-target',0));
 if exists(select 1 from private.hub_transport_unit_targets_v2 t where t.tenant_id=p_tenant and t.unit_id=p_unit and t.valid_from>=p_from) then raise exception 'A target already exists on or after this date';end if;
 update private.hub_transport_unit_targets_v2 set valid_to=p_from-1 where tenant_id=p_tenant and unit_id=p_unit and(valid_to is null or valid_to>=p_from);
 insert into private.hub_transport_unit_targets_v2(tenant_id,unit_id,valid_from,margin_percent,reason,created_by) values(p_tenant,p_unit,p_from,p_margin,trim(p_reason),auth.uid())returning id into result;
 return result;
end $$;
revoke all on function public.hub_transport_unit_target_save_v2(uuid,uuid,date,numeric,text) from public,anon;
grant execute on function public.hub_transport_unit_target_save_v2(uuid,uuid,date,numeric,text) to authenticated;
