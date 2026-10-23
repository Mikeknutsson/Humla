create or replace function public.hub_saw_activity_report_v1(p_tenant uuid,p_from date,p_to date,p_user uuid default null,p_unit uuid default null,p_months integer[] default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare answer jsonb;complete_scope boolean;invoice_total numeric;invoice_saw numeric;invoice_extra numeric;chip_rate numeric;chip_tons numeric;chip_value numeric;chip_pending numeric;chip_rows jsonb;begin
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
 -- Confirmed invoice evidence replaces totals only in complete authorized scope.
 -- Workify remains the source for truck hours and per-order/per-unit detail.
 if complete_scope and p_from >= date '2025-09-01' and p_to <= date '2026-08-31' then
 select coalesce(sum(amount),0),coalesce(sum(amount)filter(where article='12-04'),0),coalesce(sum(amount)filter(where article='12-041'),0)
 into invoice_total,invoice_saw,invoice_extra from private.hub_saw_invoice_lines_v1
 where tenant_id=p_tenant and occurred_on between p_from and p_to
 and(p_months is null or extract(month from occurred_on)::integer=any(p_months));
 answer:=jsonb_set(answer,'{summary}',(answer->'summary')||jsonb_build_object(
 'workify_gross_revenue',answer#>'{summary,gross_revenue}',
 'gross_revenue',invoice_total,'invoice_article_revenue',invoice_saw,'invoice_extra_revenue',invoice_extra,
 'saw_revenue',invoice_total-coalesce((answer#>>'{summary,truck_revenue}')::numeric,0),
 'result',invoice_total-coalesce((answer#>>'{summary,truck_revenue}')::numeric,0)-coalesce((answer#>>'{summary,cost}')::numeric,0),
 'revenue_source','confirmed_invoice_statistics'));
 end if;
 if complete_scope then
 select chip_rate_per_ton into chip_rate from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant;
 if chip_rate is not null then
 with current_state as(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
 saw_orders as materialized(
 select distinct f.original#>>'{_humla_invoice,order_number}' order_number
 from private.hub_kpi_prepared_display_facts f join current_state s on s.active_generation=f.generation_id
 where f.tenant_id=p_tenant and f.original#>>'{_humla_saw_activity,reason}'='article_hour_split'),
 candidates as(
 select r.id,r.occurred_on,r.source_data->>'Ordernummer' order_number,r.source_data->>'Kundnamn' customer,
 r.source_data->>'Rubrik' description,replace(r.source_data->>'Kvantitet',',','.')::numeric tons,
 exists(select 1 from saw_orders s where s.order_number=r.source_data->>'Ordernummer') linked
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant and r.is_valid and b.status in('completed','needs_review')
 and r.data_kind='revenue' and r.source_data->>'Artikelnummer'='3-24'
 and lower(trim(r.source_data->>'Enhet'))='ton'
 and r.source_data->>'Orderstatus' in('Invoiced','ReadyForInvoicing','Reported')
 and replace(r.source_data->>'Kvantitet',',','.') ~ '^-?[0-9]+([.][0-9]+)?$'
 and r.occurred_on between p_from and p_to
 and(p_months is null or extract(month from r.occurred_on)::integer=any(p_months))
 and(r.amount=0 or exists(select 1 from private.hub_kpi_prepared_display_facts f join current_state s on s.active_generation=f.generation_id where f.tenant_id=p_tenant and f.fact_id=r.id::text))
 )select coalesce(sum(tons)filter(where linked),0),coalesce(sum(tons)filter(where not linked),0),
 coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('chip_revenue',case when linked then tons*chip_rate end)order by occurred_on,id),'[]'::jsonb)
 into chip_tons,chip_pending,chip_rows from candidates c;
 chip_value:=chip_tons*chip_rate;
 answer:=jsonb_set(answer,'{summary}',(answer->'summary')||jsonb_build_object(
 'chip_tons',chip_tons,'chip_rate',chip_rate,'chip_revenue',chip_value,'chip_pending_tons',chip_pending,
 'saw_revenue',coalesce((answer#>>'{summary,saw_revenue}')::numeric,0)+chip_value,
 'result',coalesce((answer#>>'{summary,result}')::numeric,0)+chip_value));
 answer:=answer||jsonb_build_object('chip_rows',chip_rows);
 end if;
 end if;
 return answer;
end $$;
revoke all on function public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])from public,anon;
grant execute on function public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])to authenticated;
