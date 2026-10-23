create or replace function public.hub_workify_period_comparison_v1(p_tenant_id uuid,p_from date,p_to date,p_center text default '30',p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;batch uuid;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 or p_page is null or p_page<0 or p_page>100000 or p_center is null or p_center!~'^[0-9]{1,3}$'then raise exception 'Invalid comparison selection';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then return jsonb_build_object('available',false);end if;
 select b.id into batch from public.kpi_import_batches b where b.tenant_id=p_tenant_id and b.status in('completed','needs_review')
 and exists(select 1 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.batch_id=b.id and r.data_kind='revenue'
 and r.source_data?'Ordernummer'and r.occurred_on between p_from and p_to)
 order by b.created_at desc,b.id desc limit 1;
 if batch is null then return jsonb_build_object('available',false);end if;
 with published as materialized(
 select f.*,coalesce(nullif(f.original->>'Ordernummer',''),'Utan ordernummer')order_no
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant_id and f.generation_id=generation and f.source='Workify'
 and f.kind='revenue'and f.cost_center=p_center and f.occurred_on between p_from and p_to
 ), latest as materialized(
 select r.*,coalesce(nullif(r.source_data->>'Ordernummer',''),'Utan ordernummer')order_no,
 r.source_data->>'Orderstatus'in('Reported','ReadyForInvoicing','Invoiced')in_scope
 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.batch_id=batch and r.data_kind='revenue'
 and r.source_data?'Ordernummer'and r.source_data->>'Kostnadsställe'=p_center and r.occurred_on between p_from and p_to
 and r.currency='SEK'
 ), current_orders as(
 select f.order_no,count(*)current_rows,sum(f.amount)current_amount,
 jsonb_agg(jsonb_build_object('fact_id',f.fact_id,'file_name',b.file_name,'row_number',r.row_number,'date',f.occurred_on,
 'amount',f.amount,'vehicle',f.vehicle,'project',f.project,'article',f.original->>'Artikelnummer',
 'quantity',f.original->>'Kvantitet','price',f.original->>'Kundpris')order by f.occurred_on,f.fact_id)current_source_rows
 from published f left join public.kpi_import_rows r on r.tenant_id=p_tenant_id and r.id::text=coalesce(f.original->>'_humla_workify_source_row_id',split_part(f.fact_id,':',1))
 left join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=p_tenant_id group by f.order_no
 ), latest_orders as(
 select order_no,count(*)filter(where in_scope)latest_rows,coalesce(sum(amount)filter(where in_scope),0)latest_amount,
 max(source_data->>'Kundnamn')customer,max(source_data->>'Rubrik')title,
 jsonb_agg(jsonb_build_object('row_id',id,'row_number',row_number,'date',occurred_on,'status',source_data->>'Orderstatus','amount',amount,'is_valid',is_valid,
 'vehicle',source_data->>'RegNr','article',source_data->>'Artikelnummer','quantity',source_data->>'Kvantitet','price',source_data->>'Kundpris')order by row_number)source_rows
 from latest group by order_no
 ), orders as materialized(
 select coalesce(c.order_no,l.order_no)order_no,l.customer,l.title,
 coalesce(c.current_rows,0)current_rows,coalesce(l.latest_rows,0)latest_rows,
 coalesce(c.current_amount,0)current_amount,coalesce(l.latest_amount,0)latest_amount,
 coalesce(c.current_amount,0)-coalesce(l.latest_amount,0)difference,l.source_rows,c.current_source_rows
 from current_orders c full join latest_orders l using(order_no)
 ), totals as(
 select coalesce(sum(current_amount),0)current_amount,coalesce(sum(latest_amount),0)latest_amount,coalesce(sum(difference),0)difference,count(*)order_count,
 count(*)filter(where difference<>0)changed_orders from orders
 ), control as(select * from private.hub_workify_period_controls where tenant_id=p_tenant_id and period_from=p_from and period_to=p_to and cost_center=p_center and currency='SEK')
 select jsonb_build_object('available',true,'generation',generation,'from',p_from,'to',p_to,'center',p_center,
 'batch',(select jsonb_build_object('id',b.id,'file_name',b.file_name,'imported_at',b.created_at,'status',b.status)from public.kpi_import_batches b where b.id=batch),
 'totals',to_jsonb(t)||jsonb_build_object('latest_all_statuses',(select coalesce(sum(amount),0)from latest),
 'excluded_status_amount',(select coalesce(sum(amount)filter(where not in_scope),0)from latest),
 'reported_workify_total',(select amount from control),'reported_reference',(select reference from control),
 'difference_to_reported',t.current_amount-(select amount from control),
 'latest_to_reported',(select amount from control)-t.latest_amount,
 'order_partition_difference',t.current_amount-t.latest_amount-t.difference),
 'status_totals',(select coalesce(jsonb_agg(to_jsonb(x)order by status),'[]')from(select source_data->>'Orderstatus'status,count(*)rows,sum(amount)amount from latest group by 1)x),
 'orders',(select coalesce(jsonb_agg(to_jsonb(x)order by abs(difference)desc,order_no),'[]')from(select * from orders order by abs(difference)desc,order_no limit 50 offset p_page*50)x))into answer from totals t;
 return answer;
end $$;
revoke all on function public.hub_workify_period_comparison_v1(uuid,date,date,text,integer)from public,anon;
grant execute on function public.hub_workify_period_comparison_v1(uuid,date,date,text,integer)to authenticated,service_role;
