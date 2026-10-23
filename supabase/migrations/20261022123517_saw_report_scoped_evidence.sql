create or replace function public.hub_saw_activity_report_v1(p_tenant uuid,p_from date,p_to date,p_user uuid default null,p_unit uuid default null,p_months integer[] default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare answer jsonb;complete_scope boolean;begin
 if p_months is not null and(cardinality(p_months)=0 or not p_months<@array[1,2,3,4,5,6,7,8,9,10,11,12])then raise exception 'Invalid months';end if;
 complete_scope:=p_user is null and p_unit is null and exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and role='owner' and status='active');
 with scoped as materialized(select d.* from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)d where d.original?'_humla_saw_activity' or exists(select 1 from public.hub_identity_keys k join private.hub_saw_activity_rules_v1 r on r.tenant_id=k.tenant_id and r.review_project_id=public.hub_resolve_canonical_object_v1(k.tenant_id,k.object_id) where k.tenant_id=d.tenant_id and k.identity_type='next_project_number' and k.identity_value=d.project)),
 authorized as materialized(select d.*,f.original evidence from scoped d
 join private.hub_kpi_prepared_facts f on f.tenant_id=d.tenant_id and f.generation_id=d.generation_id and f.fact_id=d.fact_id
 where p_months is null or extract(month from d.occurred_on)::int=any(p_months)),
 revenue as materialized(select distinct on(evidence#>>'{_humla_saw_activity,original_fact_id}')
 evidence#>>'{_humla_saw_activity,original_fact_id}' row_id,occurred_on,
 evidence#>>'{_humla_saw_activity,original_unit_id}' unit_id,evidence#>>'{_humla_saw_activity,original_unit_name}' unit_name,
 evidence->>'Ordernummer' order_number,evidence->>'Kundnamn' customer,evidence->>'Rubrik' description,
 (evidence#>>'{_humla_saw_activity,original_amount}')::numeric gross_revenue,
 (evidence#>>'{_humla_saw_activity,hours}')::numeric hours,
 (evidence#>>'{_humla_saw_activity,hours}')::numeric*(evidence#>>'{_humla_saw_activity,truck_hour_rate}')::numeric truck_revenue,
 (evidence#>>'{_humla_saw_activity,allocated_amount}')::numeric saw_revenue
 from authorized where kind='revenue' and evidence#>>'{_humla_saw_activity,reason}'='article_hour_split'
 and(p_unit is null or unit_id=p_unit or evidence#>>'{_humla_saw_activity,original_unit_id}'=p_unit::text)
 order by evidence#>>'{_humla_saw_activity,original_fact_id}',fact_id),
 costs as materialized(select fact_id,occurred_on,project,category,amount,evidence->>'Leverantör' supplier,evidence->>'Verifikation nr' voucher,evidence->>'Verifikationstext' description,
 evidence#>>'{_humla_saw_activity,reason}' allocation_reason
 from authorized where kind='cost' and evidence#>>'{_humla_saw_activity,branch}'='saw' and(p_unit is null or unit_id=p_unit)),
 pending as(select fact_id,occurred_on,project,amount,evidence->>'Leverantör' supplier,evidence->>'Verifikation nr' voucher,evidence->>'Verifikationstext' description
 from authorized f where kind='cost' and amount<>0 and not(evidence?'_humla_saw_activity') and(p_unit is null or unit_id=p_unit)
 and exists(select 1 from public.hub_identity_keys k join private.hub_saw_activity_rules_v1 r on r.tenant_id=k.tenant_id and r.review_project_id=public.hub_resolve_canonical_object_v1(k.tenant_id,k.object_id)
 where k.tenant_id=f.tenant_id and k.identity_type='next_project_number' and k.identity_value=f.project)),
 orders as(select coalesce(order_number,row_id)order_key,order_number,unit_id,min(unit_name)unit_name,min(occurred_on)first_date,max(occurred_on)last_date,min(customer)customer,min(description)description,sum(gross_revenue)gross_revenue,sum(hours)hours,sum(truck_revenue)truck_revenue,sum(saw_revenue)saw_revenue from revenue group by coalesce(order_number,row_id),order_number,unit_id),
 units as(select unit_id,min(unit_name)unit_name,count(distinct coalesce(order_number,row_id))orders,sum(gross_revenue)gross_revenue,sum(hours)hours,sum(truck_revenue)truck_revenue,sum(saw_revenue)saw_revenue from revenue group by unit_id),
 groups as(select allocation_reason,sum(amount)amount,count(*)rows from costs group by allocation_reason)
 select jsonb_build_object('complete_scope',complete_scope,'summary',(select jsonb_build_object('gross_revenue',sum(gross_revenue),'hours',sum(hours),'truck_revenue',sum(truck_revenue),'saw_revenue',sum(saw_revenue),'orders',count(distinct coalesce(order_number,row_id)),
 'cost',case when complete_scope then coalesce((select sum(amount)from costs),0)else(select sum(amount)from costs)end,
 'result',case when complete_scope then coalesce(sum(saw_revenue),0)-coalesce((select sum(amount)from costs),0)end,
 'pending_rows',(select count(*)from pending),'pending_amount',(select sum(amount)from pending))from revenue),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)order by unit_name),'[]')from units u),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o)order by last_date desc,order_key),'[]')from orders o),
 'costs',(select coalesce(jsonb_agg(to_jsonb(c)order by occurred_on desc,fact_id),'[]')from costs c),
 'cost_groups',(select coalesce(jsonb_agg(to_jsonb(g)order by allocation_reason),'[]')from groups g),
 'pending',(select coalesce(jsonb_agg(to_jsonb(p)order by occurred_on desc,fact_id),'[]')from pending p))into answer;
 return answer;
end $$;
revoke all on function public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])from public,anon;
grant execute on function public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])to authenticated;
