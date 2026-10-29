
create or replace function private.hub_saw_material_value_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql security definer set search_path='' set jit=off as $f$
declare rule private.hub_saw_activity_rules_v1;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'Access denied' using errcode='42501';end if;
 select * into rule from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant;
 if not found or rule.chip_rate_per_ton is null then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
 delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_chip';
 delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_chip';
 with saw_orders as materialized(
 select distinct nullif(original->>'Ordernummer','') order_number from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant and generation_id=p_generation and original#>>'{_humla_saw_activity,reason}'='article_hour_split'
 ), eligible as materialized(
 select r.*,b.created_at batch_created,
 private.hub_workify_content_key_v2(r.occurred_on,r.amount,replace(trim(r.source_data->>'Kvantitet'),',','.')::numeric,r.source_data) content_key
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant and r.data_kind='revenue' and b.status in('completed','needs_review')
 and r.source_data->>'Artikelnummer' in('3-09','3-24') and lower(trim(r.source_data->>'Enhet'))='ton'
 and replace(trim(r.source_data->>'Kvantitet'),',','.')~'^-?[0-9]+([.][0-9]+)?$'
 and r.occurred_on>=rule.valid_from
 and private.hub_workify_financially_eligible_v1(r.is_valid,r.validation_errors)
 and private.hub_workify_row_in_scope_v1(r.id,r.source_data)
 and exists(select 1 from saw_orders s where s.order_number=r.source_data->>'Ordernummer')
 and not coalesce(r.occurred_on between rule.chip_weigh_from and rule.chip_weigh_to,false)
 and not exists(select 1 from private.hub_saw_chip_deliveries_v1 w where w.tenant_id=p_tenant
 and r.source_data->>'Ordernummer'=any(w.order_numbers))
 ), occurrences as(
 select e.*,row_number()over(partition by batch_id,content_key order by row_number,id) occurrence from eligible e
 ), workify as(
 select distinct on(content_key,occurrence) * from occurrences order by content_key,occurrence,batch_created desc,id
 ), deliveries as(
 select 'weigh:'||w.ticket_number id,w.occurred_on,w.tons,'Vågunderlag'::text source,
 jsonb_build_object('ticket_number',w.ticket_number,'order_numbers',w.order_numbers,'source_file',w.source_file,'source_page',w.source_page) evidence
 from private.hub_saw_chip_deliveries_v1 w where w.tenant_id=p_tenant and w.unit_id=rule.unit_id
 union all
 select 'workify:'||w.id::text,w.occurred_on,replace(trim(w.source_data->>'Kvantitet'),',','.')::numeric,'Workify',
 jsonb_build_object('source_row_id',w.id,'order_number',w.source_data->>'Ordernummer','article',w.source_data->>'Artikelnummer')
 from workify w
 ), valued as(
 select *,jsonb_build_object('_humla_saw_chip',evidence||jsonb_build_object('rule','registered_saw_material_v1','tons',tons,'rate_per_ton',rule.chip_rate_per_ton,'source',source,'cash_flow',false)) meta
 from deliveries where tons<>0
 )
 insert into private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,
 unit_id,unit_name,business_group,source,description,original,cost_center,cost_center_name,classification_source,display_original)
 select p_generation,p_tenant,extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,
 'saw-material:'||id,occurred_on,'revenue',round(tons*rule.chip_rate_per_ton,2),'material',
 rule.unit_id,'Sågning','Sågning','Materialvärde','Invägt Grot/Stock – beräknat materialvärde',meta,'30','Transport',
 jsonb_build_object('rule','registered_saw_material_v1'),meta from valued;
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_chip';
end $f$;
revoke all on function private.hub_saw_material_value_v1(uuid,uuid) from public,anon,authenticated;
