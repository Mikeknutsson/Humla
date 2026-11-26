CREATE OR REPLACE FUNCTION public.hub_saw_activity_report_v1(p_tenant uuid, p_from date, p_to date, p_user uuid DEFAULT NULL::uuid, p_unit uuid DEFAULT NULL::uuid, p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare answer jsonb;complete_scope boolean;invoice_total numeric;invoice_saw numeric;invoice_extra numeric;chip_rate numeric;chip_tons numeric;chip_value numeric;chip_pending numeric;chip_rows jsonb; invoice_snapshot jsonb; invoice_source text; requested_to date:=p_to; begin
 if p_months is not null and(cardinality(p_months)=0 or not p_months<@array[1,2,3,4,5,6,7,8,9,10,11,12])then raise exception 'Invalid months';end if;
 complete_scope:=p_user is null and p_unit is null and exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and role='owner' and status='active');
 if complete_scope and p_from is not null and p_to is not null and p_to-p_from between 0 and 366 then
  select f.payload, f.resource into invoice_snapshot,invoice_source
  from public.hub_fortnox_raw f
  where f.tenant_id=p_tenant and f.resource in ('saw_article_check_v1','saw_article_export_v1')
   and f.payload->>'from'<=p_from::text and f.payload->>'to'>=p_from::text
   and jsonb_typeof(f.payload->'rows')='array'
  order by least((f.payload->>'to')::date,p_to) desc, (f.resource='saw_article_check_v1') desc, f.fetched_at desc
  limit 1;
  if invoice_snapshot is not null then p_to:=least(p_to,(invoice_snapshot->>'to')::date); end if;
 end if;
 with scoped as materialized(select d.* from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)d where exists(select 1 from private.hub_saw_activity_rules_v1 sr where sr.tenant_id=p_tenant and sr.unit_id=d.unit_id) or d.original?'_humla_saw_activity' or (d.original?'_humla_monthly_overhead' and exists(select 1 from private.hub_saw_activity_rules_v1 sr where sr.tenant_id=p_tenant and sr.unit_id=d.unit_id)) or exists(select 1 from public.hub_identity_keys k join private.hub_saw_activity_rules_v1 r on r.tenant_id=k.tenant_id and r.review_project_id=public.hub_resolve_canonical_object_v1(k.tenant_id,k.object_id) where k.tenant_id=d.tenant_id and k.identity_type='next_project_number' and k.identity_value=d.project)),
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
 costs as materialized(select fact_id,occurred_on,project,category,amount,evidence->>'Leverantör' supplier,evidence->>'Verifikation nr' voucher,coalesce(evidence->>'Verifikationstext',evidence#>>'{_humla_monthly_overhead,rule_name}') description,
 coalesce(evidence#>>'{_humla_saw_activity,reason}',case when evidence#>>'{_humla_monthly_overhead,cost_type}'='management' then 'Overhead / Arbetsledning – Transport' else 'Overhead – Transport och Sortergården' end) allocation_reason
 from authorized where kind='cost' and unit_id=(select unit_id from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant) and(p_unit is null or unit_id=p_unit)),
 pending as(select fact_id,occurred_on,project,amount,evidence->>'Leverantör' supplier,evidence->>'Verifikation nr' voucher,coalesce(evidence->>'Verifikationstext',evidence#>>'{_humla_monthly_overhead,rule_name}') description
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
 if invoice_snapshot is not null then
  select coalesce(sum(amount),0),coalesce(sum(amount) filter(where article='12-04'),0),coalesce(sum(amount) filter(where article='12-041'),0)
  into invoice_total,invoice_saw,invoice_extra
  from jsonb_to_recordset(invoice_snapshot->'rows') as line(date date,article text,amount numeric)
  where line.date between p_from and p_to and article in ('12-04','12-041')
  and (p_months is null or extract(month from line.date)::int=any(p_months));
  answer:=jsonb_set(answer,'{summary}',(answer->'summary')||jsonb_build_object(
   'workify_gross_revenue',answer#>'{summary,gross_revenue}',
   'gross_revenue',invoice_total,'invoice_article_revenue',invoice_saw,'invoice_extra_revenue',invoice_extra,
   'saw_revenue',invoice_total-coalesce((answer#>>'{summary,truck_revenue}')::numeric,0),
   'result',invoice_total-coalesce((answer#>>'{summary,truck_revenue}')::numeric,0)-coalesce((answer#>>'{summary,cost}')::numeric,0),
   'invoice_covered_to',p_to,'invoice_period_clipped',p_to<requested_to,
   'revenue_source',case invoice_source when 'saw_article_check_v1' then 'fortnox_api' else 'fortnox_export' end));
 elsif complete_scope and p_from >= date '2025-09-01' and p_to <= date '2026-08-31' then
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
 workify_candidates as(
 select r.id::text,r.occurred_on,r.source_data->>'Artikelnamn' article_name,r.source_data->>'Ordernummer' order_number,r.source_data->>'Kundnamn' customer,
 r.source_data->>'Rubrik' description,replace(r.source_data->>'Kvantitet',',','.')::numeric tons,
 exists(select 1 from saw_orders s where s.order_number=r.source_data->>'Ordernummer') and not exists(select 1 from private.hub_saw_activity_rules_v1 cr where cr.tenant_id=p_tenant and r.occurred_on between cr.chip_weigh_from and cr.chip_weigh_to) linked
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant and r.is_valid and b.status in('completed','needs_review')
 and r.data_kind='revenue' and r.source_data->>'Artikelnummer' in('3-24','3-09')
 and lower(trim(r.source_data->>'Enhet'))='ton'
 and r.source_data->>'Orderstatus' in('Invoiced','ReadyForInvoicing','Reported')
 and replace(r.source_data->>'Kvantitet',',','.') ~ '^-?[0-9]+([.][0-9]+)?$'
 and r.occurred_on between p_from and p_to
 and not exists(select 1 from private.hub_saw_chip_deliveries_v1 w join private.hub_saw_activity_rules_v1 cr on cr.tenant_id=w.tenant_id where w.tenant_id=p_tenant and r.source_data->>'Ordernummer'=any(w.order_numbers) and r.occurred_on between cr.chip_weigh_from and cr.chip_weigh_to)
 and(p_months is null or extract(month from r.occurred_on)::integer=any(p_months))
 and(r.amount=0 or exists(select 1 from private.hub_kpi_prepared_display_facts f join current_state s on s.active_generation=f.generation_id where f.tenant_id=p_tenant and f.fact_id=r.id::text))
 ), candidates as(
 select id,occurred_on,article_name,order_number,customer,description,tons,linked,'Workify'::text source from workify_candidates
 union all
 select 'weigh:'||ticket_number,occurred_on,'Stam/grot',array_to_string(order_numbers,' + '),customer,evidence,tons,true,'Vågunderlag'
 from private.hub_saw_chip_deliveries_v1 where tenant_id=p_tenant and occurred_on between p_from and p_to
 and(p_months is null or extract(month from occurred_on)::integer=any(p_months))
 )select coalesce(sum(tons)filter(where linked),0),coalesce(sum(tons)filter(where not linked),0),
 coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('chip_revenue',case when linked then tons*chip_rate end)order by occurred_on,id),'[]'::jsonb)
 into chip_tons,chip_pending,chip_rows from candidates c;
 chip_value:=chip_tons*chip_rate;
 answer:=jsonb_set(answer,'{summary}',(answer->'summary')||jsonb_build_object(
 'chip_weigh_basis',exists(select 1 from private.hub_saw_activity_rules_v1 cr where cr.tenant_id=p_tenant and p_from<=cr.chip_weigh_to and p_to>=cr.chip_weigh_from),'chip_tons',chip_tons,'chip_rate',chip_rate,'chip_revenue',chip_value,'chip_pending_tons',chip_pending,
 'saw_revenue',coalesce((answer#>>'{summary,saw_revenue}')::numeric,0)+chip_value,
 'result',coalesce((answer#>>'{summary,result}')::numeric,0)+chip_value));
 answer:=answer||jsonb_build_object('chip_rows',chip_rows);
 end if;
 end if;
 return answer;
end $function$;
