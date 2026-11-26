create function private.hub_saw_invoice_order_adjustments(p_tenant uuid,p_payload jsonb)
returns table(invoice_date date,invoice text,article text,order_number text,invoice_amount numeric,workify_amount numeric,adjustment numeric)
language sql stable set search_path='' as $$
 with invoices as materialized (
  select l.date,l.invoice,l.article,max(nullif(l."customerNumber",'')) customer,sum(l.amount) amount
  from jsonb_to_recordset(p_payload->'rows') l(date date,invoice text,article text,"customerNumber" text,amount numeric)
  where l.article in ('12-04','12-041') and nullif(l.invoice,'') is not null
  group by l.date,l.invoice,l.article
 ), observations as materialized (
  select distinct r.source_data->>'Kundnr' customer,r.source_data->>'Artikelnummer' article,
   nullif(btrim(r.source_data->>'ExterntDokumentnummer'),'') document,
   nullif(btrim(r.source_data->>'Ordernummer'),'') order_number,left(r.source_data->>'Artikeldatum',10)::date worked
  from private.hub_workify_row_observations r
  where r.tenant_id=p_tenant and r.source_data->>'Artikelnummer' in ('12-04','12-041')
   and nullif(btrim(r.source_data->>'Ordernummer'),'') is not null
   and left(r.source_data->>'Artikeldatum',10) between (((p_payload->>'from')::date)-90)::text and p_payload->>'to'
   and (r.source_data->>'Kundnr' in (select customer from invoices)
    or r.source_data->>'ExterntDokumentnummer' in (select invoice from invoices))
 ), exact as materialized (
  select i.invoice,i.article,min(w.order_number) order_number
  from invoices i join observations w on w.document=i.invoice and w.article=i.article
   and (i.customer is null or w.customer=i.customer)
  group by 1,2 having count(distinct w.order_number)=1
 ), by_customer as (
  select i.invoice,i.article,min(w.order_number) order_number
  from invoices i join observations w on w.customer=i.customer and w.article=i.article and w.document is null
   and w.worked between i.date-90 and i.date
  where i.amount>0 and not exists(select 1 from exact e where e.invoice=i.invoice and e.article=i.article)
   and not exists(select 1 from exact e where e.order_number=w.order_number and e.article=w.article)
   and (select count(*) from invoices other where other.customer=i.customer and other.article=i.article
    and other.amount>0 and not exists(select 1 from exact e where e.invoice=other.invoice and e.article=other.article))=1
  group by 1,2 having count(distinct w.order_number)=1
 ), linked as materialized (
  select i.*,coalesce(e.order_number,c.order_number) order_number
  from invoices i left join exact e using(invoice,article) left join by_customer c using(invoice,article)
 ), kpi as materialized (
  select l.order_number,l.article,sum(case when l.article='12-04'
    then (f.original#>>'{_humla_saw_activity,original_amount}')::numeric else f.amount end) amount
  from private.hub_kpi_prepared_display_facts f
  join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
  join private.hub_saw_activity_rules_v1 rules on rules.tenant_id=f.tenant_id and rules.unit_id=f.unit_id
  join private.hub_kpi_prepared_facts b on b.tenant_id=f.tenant_id and b.generation_id=f.generation_id
   and b.fact_id=coalesce(f.original#>>'{_humla_saw_activity,original_fact_id}',f.fact_id)
  join (select distinct order_number,article from linked where order_number is not null) l
   on l.order_number=b.original->>'Ordernummer' and l.article=b.original->>'Artikelnummer'
  where f.tenant_id=p_tenant and f.kind='revenue' and f.source='Workify'
   and f.occurred_on between (p_payload->>'from')::date and (p_payload->>'to')::date
   and (l.article='12-041' or f.original#>>'{_humla_saw_activity,branch}'='saw')
   and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
  group by 1,2
 ), calculations as (
  select l.*,coalesce(k.amount,0) base,row_number() over(partition by l.order_number,l.article order by l.date,l.invoice) position
  from linked l left join kpi k using(order_number,article)
 )
 select date,invoice,article,order_number,amount,
  case when order_number is not null and position=1 then base else 0 end,
  case when order_number is not null then amount-case when position=1 then base else 0 end end
 from calculations
$$;
revoke all on function private.hub_saw_invoice_order_adjustments(uuid,jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.hub_foreman_facts_with_saw_invoices(p_tenant uuid, p_from date, p_to date, p_user uuid)
 RETURNS SETOF private.hub_kpi_prepared_display_facts
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with base as materialized (
  select * from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)
 ), saw as materialized (
  select r.unit_id,s.active_generation generation_id
  from private.hub_saw_activity_rules_v1 r join private.hub_kpi_report_state s using (tenant_id)
  where r.tenant_id=p_tenant
 ), scope_members as materialized (
  select m.user_id,p.cost_centers
  from public.hub_tenant_members m
  left join private.hub_foreman_access_plans p on p.tenant_id=m.tenant_id and p.auth_user_id=m.user_id and p.status='active'
  where m.tenant_id=p_tenant and m.status='active' and (
   (p_user='00000000-0000-0000-0000-000000000030'::uuid
    and trim(m.display_name) ~* '^(marcus|ola|pierre)([[:space:]]|$)')
    or (p_user is distinct from '00000000-0000-0000-0000-000000000030'::uuid and m.user_id=coalesce(p_user,auth.uid()))
  )
 ), owner_scope as (
  select exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant
   and m.user_id=auth.uid() and m.role='owner' and m.status='active') and
   (p_user is null or p_user='00000000-0000-0000-0000-000000000030'::uuid) allowed
 ), snapshot as materialized (
  select * from private.hub_saw_fortnox_snapshot(p_tenant,p_from,p_to)
 ), coverage as (
  select least((payload->>'to')::date,p_to) covered_to, resource from snapshot
  union all
  select p_to,'confirmed_invoice_statistics'
  where not exists(select 1 from snapshot) and p_from>=date '2025-09-01' and p_to<=date '2026-08-31'
   and exists(select 1 from private.hub_saw_invoice_lines_v1 where tenant_id=p_tenant)
 ), allowed_days as materialized (
  select dates.day::date occurred_on,c.covered_to,c.resource,s.unit_id,s.generation_id
  from coverage c cross join saw s
  cross join lateral generate_series(p_from::timestamp,c.covered_to::timestamp,interval '1 day') dates(day)
  where (select allowed from owner_scope) or exists (
   select 1 from scope_members m where case when m.cost_centers is not null then '30'=any(m.cost_centers)
    else exists(select 1 from public.hub_transport_leader_units a
     where a.tenant_id=p_tenant and a.user_id=m.user_id and a.unit_id=s.unit_id
      and a.valid_from<=dates.day::date and (a.valid_to is null or a.valid_to>=dates.day::date))
    end
  )
 ), invoice_lines as (
  select l.invoice_date occurred_on,l.adjustment amount
  from snapshot x cross join lateral private.hub_saw_invoice_order_adjustments(p_tenant,x.payload) l
  where l.invoice_date between p_from and p_to and l.adjustment is not null
  union all
  select l.occurred_on,l.amount from private.hub_saw_invoice_lines_v1 l
  where l.tenant_id=p_tenant and l.occurred_on between p_from and p_to
   and exists(select 1 from coverage c where c.resource='confirmed_invoice_statistics')
 ), invoiced as (
  select occurred_on,sum(amount) amount from invoice_lines group by 1
 )
 select f.generation_id,f.tenant_id,f.fiscal_year,f.fact_id,f.occurred_on,f.kind,
  case when d.occurred_on is not null then f.amount-coalesce((f.original#>>'{_humla_saw_activity,original_amount}')::numeric,0)
   else f.amount end,
  f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,f.source,f.cost_center,
  case when d.occurred_on is not null then f.original||jsonb_build_object('_humla_saw_fortnox',jsonb_build_object(
    'resource',d.resource,'covered_to',d.covered_to,'kind','truck_allocation')) else f.original end
 from base f left join allowed_days d on d.occurred_on=f.occurred_on and d.unit_id=f.unit_id and d.resource='confirmed_invoice_statistics'
  and f.kind='revenue' and f.original#>>'{_humla_saw_activity,reason}'='article_hour_split'
  and f.original#>>'{_humla_saw_activity,branch}'='saw'
 where not (f.kind='revenue' and f.source='Workify' and exists (
  select 1 from allowed_days covered where covered.occurred_on=f.occurred_on and covered.unit_id=f.unit_id and covered.resource='confirmed_invoice_statistics'
 ) and exists (
  select 1 from private.hub_kpi_prepared_facts original_row
  where original_row.tenant_id=f.tenant_id and original_row.generation_id=f.generation_id and original_row.fact_id=f.fact_id
   and original_row.original->>'Artikelnummer'='12-041'
 ))
 union all
 select d.generation_id,p_tenant,extract(year from d.occurred_on)::int-case when extract(month from d.occurred_on)<9 then 1 else 0 end,
  'saw-invoice-correction:'||d.occurred_on,d.occurred_on,'revenue',coalesce(i.amount,0),'transport',null,null,
  d.unit_id,'Sågning','Sågning',case when d.resource='confirmed_invoice_statistics' then 'Artikelstatistik' else 'Fortnox' end,'30',
  jsonb_build_object('_humla_saw_fortnox',jsonb_build_object('resource',d.resource,'covered_to',d.covered_to,'kind',case when d.resource='confirmed_invoice_statistics' then 'invoice_net' else 'invoice_delta' end))
 from allowed_days d left join invoiced i using (occurred_on)
 where i.occurred_on is not null or d.occurred_on=(select min(occurred_on) from allowed_days)
$function$;

CREATE OR REPLACE FUNCTION private.hub_foreman_scorecard_v1(p_tenant uuid, p_from date, p_to date, p_user uuid, p_unit uuid, p_page integer, p_months integer[], p_group text, p_comparison boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare output jsonb; time_basis jsonb; hours numeric; time_to date; time_revenue numeric; time_cost numeric; covered int; ola_view boolean;
begin
 if p_months is not null and (cardinality(p_months)=0 or not p_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12]) then raise exception 'Invalid months';end if;
 if p_page is null or p_page<0 or p_page>10000 then raise exception 'Invalid page';end if;
 select (p_group is null or p_group='Trading & Grusförsäljning') and (p_user='00000000-0000-0000-0000-000000000030'::uuid or exists(
  select 1 from public.hub_tenant_members m
  where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active'
    and trim(m.display_name) ~* '^ola([[:space:]]|$)'
 )) into ola_view;
 with scope_facts as materialized(select f.*,
  case
   when ola_view is not true then f.business_group
   when f.unit_name in ('Trading Material','Grusmaterial - Lager','Grusmaterial Försäljning')
    then 'Trading & Grusförsäljning'
   when f.unit_name in ('WCF22U','LZP91Z','HGL39H') then 'Asfaltskörning'
   when f.unit_name='DUN012' then 'Fasta uppdrag'
   when f.unit_name='Inhyrda bilar' or f.business_group='Inhyrda lastbilar' then 'Bygg & Anläggning'
   else f.business_group
  end as view_group,
  case when ola_view and f.unit_name='Grusmaterial - Lager'
   then 'Grusmaterial Försäljning' else f.unit_name end as view_unit_name
 from private.hub_foreman_facts_with_saw_invoices(p_tenant,p_from,p_to,p_user) f where (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 facts as materialized(select f.*,case when f.category='material' then 'material' when f.category in ('tipp','tipp_deponi') then 'tipp' when f.category='transport' then 'transport' else 'other' end section
 from scope_facts f where (p_unit is null or f.unit_id=p_unit) and (p_group is null or case when p_group='Trading & Grusförsäljning' then f.view_group
    else coalesce(nullif(f.business_group,''),'Ej klassificerat') end=p_group) and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 enriched as materialized(select f.*,coalesce(t.margin_percent,g.margin_percent,20::numeric) margin_percent from facts f left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id and t.valid_from<=f.occurred_on and(t.valid_to is null or t.valid_to>=f.occurred_on) left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group),
 totals as(select unit_id,min(view_unit_name) unit_name,
 coalesce(nullif(view_group,''),'Ej klassificerat') business_group,
 grouping(unit_id,view_group) level,count(*) rows,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,
 count(*)filter(where kind='revenue' and amount<>0 and margin_percent is null) missing_targets,
 sum(amount*margin_percent/100)filter(where kind='revenue') target_result
 from enriched group by grouping sets ((unit_id),(view_group),())),
 metrics as(select *,revenue-cost result,case when revenue>0 then (revenue-cost)/revenue*100 end margin_percent,
 case when missing_targets=0 and revenue>0 and target_result is not null then target_result/revenue*100 end target_margin_percent,
 case when missing_targets=0 and target_result is not null then revenue-cost-target_result end deviation_amount,
 case when missing_targets=0 and revenue>0 and target_result is not null then ((revenue-cost)-target_result)/revenue*100 end deviation_pp from totals),
 unit_cost_rows as materialized(select unit_id,category,sum(amount) amount,count(*) rows from facts where kind='cost' group by unit_id,category),
 unit_cost_breakdowns as materialized(select unit_id,jsonb_agg(jsonb_build_object('category',category,'amount',amount,'rows',rows) order by category) cost_breakdown from unit_cost_rows group by unit_id),
 units as(select * from metrics where level=1),
 breakdown as(select kind,category,sum(amount) amount,count(*) rows from facts group by kind,category),
 sections as(select section,coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,count(*) rows from facts group by section),
 analysis_finance as materialized(
 select unit_id,min(view_unit_name) unit_name,coalesce(nullif(view_group,''),'Ej klassificerat') business_group,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,
 coalesce(sum(amount)filter(where kind='cost' and category='personnel'),0) personnel,
 coalesce(sum(amount)filter(where kind='cost' and category='service_repair'),0) service_repair,
 coalesce(sum(amount)filter(where kind='cost' and category='fuel'),0) fuel,
 count(*)filter(where kind='cost' and category='personnel' and source<>'TransPA') other_personnel_rows
 from scope_facts where unit_id is not null group by unit_id,coalesce(nullif(view_group,''),'Ej klassificerat')
 ),
 time_ids as materialized(select distinct original->>'time_report_id' time_report_id from scope_facts
 where source='TransPA' and category='personnel' and original->>'time_report_id' is not null),
 -- Resolve time through the already published canonical unit link. Never divide a
 -- person's full report among vehicles by cost or by a guessed registration.
 time_links as materialized(
 select f.original->>'time_report_id' time_report_id,(array_agg(distinct f.unit_id))[1] unit_id,
 min(coalesce(nullif(f.business_group,''),'Ej klassificerat')) business_group,
 count(distinct f.unit_id)=1 and bool_and(f.unit_id is not null)
 and count(distinct coalesce(nullif(f.business_group,''),'Ej klassificerat'))=1 unambiguous
 from private.hub_kpi_prepared_display_facts f
 where f.tenant_id=p_tenant and f.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and f.source='TransPA' and f.category='personnel' and f.original->>'time_report_id' is not null group by f.original->>'time_report_id'
 ),
 analysis_time as(
 select a.unit_id,a.business_group,sum(t.work_hours) hours,
 count(*)filter(where not l.unambiguous or t.work_hours is null or t.work_hours<0) uncertain_reports
 from analysis_finance a join (select distinct unit_id,coalesce(nullif(view_group,''),'Ej klassificerat') business_group,original->>'time_report_id' time_report_id
 from scope_facts where source='TransPA' and category='personnel') s using(unit_id,business_group)
 join time_links l using(time_report_id)
 left join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant
 and t.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and t.time_report_id=s.time_report_id and t.work_date between p_from and p_to
 group by a.unit_id,a.business_group
 ),
 analysis_inputs as(select a.*,case when a.other_personnel_rows=0 and t.uncertain_reports=0 and t.hours>0 then t.hours end worked_hours
 from analysis_finance a left join analysis_time t using(unit_id,business_group)),
 details as(select fact_id,occurred_on,kind,amount,category,unit_id,view_unit_name as unit_name,project,vehicle,source,cost_center,
 original#>>'{_humla_invoice,order_number}' order_number,original#>>'{_humla_invoice,customer_name}' customer,
 original->'_humla_cost_rule' allocation_rule,original from facts order by occurred_on desc,fact_id limit 100 offset p_page*100)
 select jsonb_build_object('from',p_from,'to',p_to,
 'scope',case when p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') then 'transport' else 'assigned' end,
 'summary',(select to_jsonb(m)||jsonb_build_object('revenue',case when rows>0 then revenue end,'cost',case when rows>0 then cost end,'result',case when rows>0 then result end,'unassigned_rows',(select count(*) from facts where unit_id is null)) from metrics m where level=3),
 'groups',(select coalesce(jsonb_agg(to_jsonb(m) order by business_group),'[]') from metrics m where level=2),
 'breakdown',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('share_of_revenue',case when m.revenue>0 then b.amount/m.revenue*100 end) order by b.kind,b.category),'[]') from breakdown b cross join metrics m where m.level=3),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)||jsonb_build_object('cost_breakdown',coalesce((select c.cost_breakdown from unit_cost_breakdowns c where c.unit_id is not distinct from u.unit_id),'[]'::jsonb)) order by unit_name nulls last),'[]')from units u),
 'monthly_unit_results',case when p_user is not null and p_unit is null and p_group is null then (
  select coalesce(jsonb_agg(to_jsonb(m) order by m.unit_id,m.month_start),'[]'::jsonb)
  from (
   select unit_id,date_trunc('month',occurred_on::timestamp)::date as month_start,
    coalesce(sum(amount) filter(where kind='revenue'),0)-coalesce(sum(amount) filter(where kind='cost'),0) result
   from enriched group by unit_id,date_trunc('month',occurred_on::timestamp)::date
  ) m
 ) end,
 'sections',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('result',case when not exists(select 1 from sections c where c.section='other' and c.cost<>0) then revenue-cost end,'margin_percent',case when revenue<>0 and not exists(select 1 from sections c where c.section='other' and c.cost<>0) then (revenue-cost)/revenue*100 end)),'[]')from sections s),
 'transactions',case when p_unit is not null then(select coalesce(jsonb_agg(to_jsonb(d)),'[]')from details d)else '[]'::jsonb end,
 'analysis_inputs',(select coalesce(jsonb_agg(to_jsonb(a) order by unit_id,business_group),'[]') from analysis_inputs a),
 'saw_breakdown',(select case when count(*)>0 then jsonb_build_object(
 'invoice_covered_to',max(original#>>'{_humla_saw_fortnox,covered_to}'),
 'invoice_source',max(original#>>'{_humla_saw_fortnox,resource}'),
 'invoice_net',sum(amount)filter(where original#>>'{_humla_saw_fortnox,kind}'='invoice_net'),
 'invoice_adjustment',sum(amount)filter(where original#>>'{_humla_saw_fortnox,kind}'='invoice_delta'),
 'revenue',coalesce(sum(amount)filter(where kind='revenue'),0),
 'material_revenue',coalesce(sum(amount)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_tons',coalesce(sum((original#>>'{_humla_saw_chip,tons}')::numeric)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_rate',(select chip_rate_per_ton from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant),
 'cost',coalesce(sum(amount)filter(where kind='cost'),0),
 'management_cost',coalesce(sum(amount)filter(where kind='cost' and category='management'),0),
 'other_cost',coalesce(sum(amount)filter(where kind='cost' and category is distinct from 'management'),0),
 'truck_charge',coalesce(sum((original#>>'{_humla_saw_activity,hours}')::numeric*(original#>>'{_humla_saw_activity,truck_hour_rate}')::numeric)
 filter(where kind='revenue' and original#>>'{_humla_saw_activity,reason}'='article_hour_split' and original#>>'{_humla_saw_activity,branch}'='saw'),0),
 'material_rows',coalesce(jsonb_agg(jsonb_build_object('id',fact_id,'date',occurred_on,'tons',original#>'{_humla_saw_chip,tons}',
 'amount',amount,'source',original#>>'{_humla_saw_chip,source}','ticket',original#>>'{_humla_saw_chip,ticket_number}',
 'order',coalesce(original#>>'{_humla_saw_chip,order_number}',original#>>'{_humla_saw_chip,order_numbers}')) order by occurred_on,fact_id)
 filter(where kind='revenue' and original?'_humla_saw_chip'),'[]'::jsonb)) end
 from facts where unit_id=(select unit_id from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant)),
 'driver_count',case when not p_comparison then private.hub_kpi_driver_count_v1(p_tenant,(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
  p_from,p_to,p_months,array(select distinct original->>'time_report_id' from facts where source='TransPA' and original->>'time_report_id' is not null),
  (select coalesce(jsonb_agg(jsonb_build_object('fact_id',fact_id,'vehicle',vehicle,'amount',amount)),'[]')
   from facts where source='NEXT' and kind='cost' and category='personnel' and vehicle is not null)) end,
 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant)) into output;
 
if p_comparison or p_user='00000000-0000-0000-0000-000000000030'::uuid then return output; end if;
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,p_to,p_user,p_unit,p_months,p_group);
time_to:=case when(time_basis->>'shared_crane_time')::boolean then(time_basis->>'through')::date else least((time_basis->>'transpa_through')::date,(time_basis->>'next_through')::date)end;
if time_to is not null and time_to<p_to then
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,time_to,p_user,p_unit,p_months,p_group);
end if;
hours:=(time_basis->>'worked_hours')::numeric;
select coalesce(sum(f.amount)filter(where f.kind='revenue'),0),coalesce(sum(f.amount)filter(where f.kind='cost'),0)into time_revenue,time_cost
from private.hub_transport_leader_facts_v2(p_tenant,p_from,coalesce(time_to,p_to),p_user)f
where(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
and(p_months is null or extract(month from f.occurred_on)::int=any(p_months));
select count(*)into covered from jsonb_to_recordset(coalesce(time_basis->'units','[]'))u(unit_id uuid,hours numeric)
where u.hours>0 and exists(select 1 from jsonb_to_recordset(output->'units')r(unit_id uuid)where r.unit_id=u.unit_id);
output:=output||jsonb_build_object('area_kpis',private.hub_foreman_area_kpis_v1(output,true)||jsonb_build_object(
'worked_hours',hours,'verified_hours',hours,'covered_units',covered,'hours_complete',false,
'revenue_per_hour',case when hours>0 then time_revenue/hours end,
'cost_per_hour',case when hours>0 then time_cost/hours end,
'result_per_hour',case when hours>0 then(time_revenue-time_cost)/hours end,
'time_from',p_from,'time_to',time_to,'time_sources',time_basis-'units',
'time_revenue',time_revenue,'time_cost',time_cost,'time_result',time_revenue-time_cost));

 output:=private.hub_foreman_mileage_v1(p_tenant,output,p_user,p_months,p_group);
 return private.hub_foreman_time_cards_v1(p_tenant,output,p_user,p_months,p_group);
end $function$;

CREATE OR REPLACE FUNCTION public.hub_saw_activity_report_v1(p_tenant uuid, p_from date, p_to date, p_user uuid DEFAULT NULL::uuid, p_unit uuid DEFAULT NULL::uuid, p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare answer jsonb;complete_scope boolean;invoice_total numeric;invoice_saw numeric;invoice_extra numeric;chip_rate numeric;chip_tons numeric;chip_value numeric;chip_pending numeric;chip_rows jsonb; invoice_snapshot jsonb; invoice_source text; invoice_delta numeric; extra_workify numeric; invoice_unmatched int; begin
 if p_months is not null and(cardinality(p_months)=0 or not p_months<@array[1,2,3,4,5,6,7,8,9,10,11,12])then raise exception 'Invalid months';end if;
 complete_scope:=p_user is null and p_unit is null and exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and role='owner' and status='active');
 if complete_scope and p_from is not null and p_to is not null and p_to-p_from between 0 and 366 then
  select payload,resource into invoice_snapshot,invoice_source from private.hub_saw_fortnox_snapshot(p_tenant,p_from,p_to);
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
 select jsonb_build_object('complete_scope',complete_scope,'summary',(select jsonb_build_object('gross_revenue',sum(gross_revenue),'workify_extra',(select coalesce(sum(amount),0) from authorized where kind='revenue' and source='Workify' and evidence->>'Artikelnummer'='12-041'),'hours',sum(hours),'truck_revenue',sum(truck_revenue),'saw_revenue',sum(saw_revenue),'orders',count(distinct coalesce(order_number,row_id)),
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
  select coalesce(sum(invoice_amount),0),coalesce(sum(invoice_amount) filter(where article='12-04'),0),coalesce(sum(invoice_amount) filter(where article='12-041'),0),
   coalesce(sum(adjustment),0),count(*) filter(where order_number is null)
  into invoice_total,invoice_saw,invoice_extra,invoice_delta,invoice_unmatched
  from private.hub_saw_invoice_order_adjustments(p_tenant,invoice_snapshot) line
  where line.invoice_date between p_from and p_to and
   (p_months is null or extract(month from line.invoice_date)::int=any(p_months));
  extra_workify:=coalesce((answer#>>'{summary,workify_extra}')::numeric,0);
  answer:=jsonb_set(answer,'{summary}',(answer->'summary')||jsonb_build_object(
   'workify_gross_revenue',coalesce((answer#>>'{summary,gross_revenue}')::numeric,0)+extra_workify,
   'gross_revenue',coalesce((answer#>>'{summary,gross_revenue}')::numeric,0)+extra_workify+invoice_delta,
   'invoice_article_revenue',invoice_saw,'invoice_extra_revenue',invoice_extra,
   'invoice_adjustment',invoice_delta,'invoice_unmatched',invoice_unmatched,
   'saw_revenue',coalesce((answer#>>'{summary,saw_revenue}')::numeric,0)+extra_workify+invoice_delta,
   'result',coalesce((answer#>>'{summary,result}')::numeric,0)+extra_workify+invoice_delta,
   'invoice_covered_to',least(p_to,(invoice_snapshot->>'to')::date),'invoice_period_clipped',p_to>(invoice_snapshot->>'to')::date,
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