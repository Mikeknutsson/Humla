create or replace function private.hub_allocate_saw_supplier_common_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' set jit=off as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation) then
  raise exception 'Generation mismatch';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));

 create temporary table saw_supplier_input on commit drop as
 select f.fact_id,f.occurred_on,f.amount,(f.original#>>'{_humla_saw_activity,original_amount}')::numeric original_amount,
  r.unit_id saw_id,r.supplier_share
 from private.hub_kpi_prepared_facts f
 join private.hub_saw_activity_rules_v1 r on r.tenant_id=f.tenant_id and f.occurred_on>=r.valid_from
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost'
  and f.original#>>'{_humla_saw_activity,reason}'='supplier_work_full'
  and f.original#>>'{_humla_saw_activity,branch}'='retained' and not (f.original?'_humla_supplier_common');

 create temporary table saw_supplier_recipients on commit drop as
 with periods as materialized (
  select distinct date_trunc('month',occurred_on)::date month_start,saw_id from pg_temp.saw_supplier_input
 ), revenue as (
  select p.month_start,p.saw_id,f.unit_id,sum(f.amount) revenue
  from periods p join private.hub_kpi_prepared_facts f
   on f.tenant_id=p_tenant and f.generation_id=p_generation and f.occurred_on>=p.month_start
   and f.occurred_on<p.month_start+interval '1 month'
  where f.kind='revenue' and f.cost_center='30' and f.unit_id is not null and f.unit_id<>p.saw_id
   and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
   and coalesce(f.category,'') not in ('material','tipp_deponi')
  group by 1,2,3 having sum(f.amount)>0
 )
 select distinct r.month_start,r.unit_id,period.value->>'name' name,g.name business_group,
  period.value#>>'{main_vehicle,source_reference}' vehicle
 from revenue r join public.hub_objects u on u.id=r.unit_id and u.tenant_id=p_tenant and u.object_type='EconomicUnit'
 cross join lateral jsonb_array_elements(u.data->'periods') period(value)
 join public.hub_objects v on v.id::text=period.value#>>'{main_vehicle,object_id}' and v.tenant_id=p_tenant
 left join public.kpi_business_groups g on g.id::text=period.value->>'business_group_id' and g.tenant_id=p_tenant
 where (period.value->>'enabled')::boolean and v.data->>'vehicle_type' in ('Lastbil','Traktor')
  and (period.value->>'valid_from')::date<r.month_start+interval '1 month'
  and coalesce((period.value->>'valid_to')::date,'infinity')>=r.month_start
  and coalesce(g.name,'') not in ('Sågning','Trading Material','Grusmaterial','Ballast','Återvinning','Inhyrda lastbilar');

 if exists(select 1 from pg_temp.saw_supplier_recipients group by month_start,unit_id having count(*)>1) then
  raise exception 'Ambiguous transport recipient periods';
 end if;
 if exists(select 1 from pg_temp.saw_supplier_input i where not exists(
  select 1 from pg_temp.saw_supplier_recipients r where r.month_start=date_trunc('month',i.occurred_on)::date
 )) then raise exception 'Supplier month lacks eligible transport vehicles'; end if;

 create temporary table saw_supplier_output on commit drop as
 with parts as (
  select i.*,round(original_amount*supplier_share,2) saw,
   round(original_amount*(1-supplier_share)/2,2) enterprise from pg_temp.saw_supplier_input i
 ), vehicle_parts as (
  select p.fact_id,r.*,p.original_amount-p.saw-p.enterprise pool,
   count(*) over(partition by p.fact_id) n,row_number() over(partition by p.fact_id order by r.unit_id) ordinal
  from parts p join pg_temp.saw_supplier_recipients r on r.month_start=date_trunc('month',p.occurred_on)::date
 ), branches as (
  select fact_id,fact_id output_id,enterprise amount,'10' center,'Entreprenad' center_name,
   null::uuid unit_id,null::text name,null::text business_group,null::text vehicle,'enterprise' branch,0::bigint n from parts
  union all
  select fact_id,fact_id||':saw',saw,'30','Transport',saw_id,'Sågning','Sågning',null,'saw',0 from parts
  union all
  select fact_id,fact_id||':transport:'||unit_id,
   (trunc(pool*100/n)+case when ordinal<=abs(mod(pool*100,n)) then sign(pool) else 0 end)/100,
   '30','Transport',unit_id,name,business_group,vehicle,'transport',n from vehicle_parts
 )
 select outrow.*
 from branches b join parts p using(fact_id)
 join private.hub_kpi_prepared_facts f on f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=p.fact_id
 cross join lateral (
  select (f.original->'_humla_saw_activity')||jsonb_build_object(
   'branch',case when b.branch='transport' then 'shared_transport' when b.branch='enterprise' then 'retained' else 'saw' end,
   'share',case when b.branch='saw' then p.supplier_share else (1-p.supplier_share)/2 end,
   'allocated_amount',b.amount) saw_meta,
   jsonb_build_object('branch',b.branch,'source_fact_id',p.fact_id,'original_amount',p.original_amount,'recipient_count',b.n) common_meta
 ) meta
 cross join lateral jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(f)||jsonb_build_object(
  'fact_id',b.output_id,'amount',b.amount,'cost_center',b.center,'cost_center_name',b.center_name,
  'unit_id',b.unit_id,'unit_name',b.name,'business_group',b.business_group,'vehicle',b.vehicle,
  'original',f.original||jsonb_build_object('_humla_saw_activity',meta.saw_meta)
   ||case when b.branch='transport' then jsonb_build_object('_humla_supplier_common',meta.common_meta) else '{}' end,
  'display_original',coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta.saw_meta)
   ||case when b.branch='transport' then jsonb_build_object('_humla_supplier_common',meta.common_meta) else '{}' end
 )) outrow;

 create temporary table saw_supplier_replace on commit drop as
 select f.fact_id, i.fact_id source_id,f.amount
 from pg_temp.saw_supplier_input i join private.hub_kpi_prepared_facts f
  on f.tenant_id=p_tenant and f.generation_id=p_generation
  and (f.fact_id=i.fact_id or f.fact_id=i.fact_id||':saw' or
    (f.original?'_humla_supplier_common' and coalesce(f.original#>>'{_humla_supplier_common,source_fact_id}',f.original#>>'{_humla_supplier_common,original_fact_id}')=i.fact_id));
 if exists(select 1 from pg_temp.saw_supplier_input i
  left join (select source_id,sum(amount) amount,count(*) filter(where fact_id=source_id||':saw') saw_count
    from pg_temp.saw_supplier_replace group by 1) old on old.source_id=i.fact_id
  left join (select original#>>'{_humla_saw_activity,original_fact_id}' source_id,sum(amount) amount
    from pg_temp.saw_supplier_output group by 1) new on new.source_id=i.fact_id
  where old.saw_count is distinct from 1::bigint or old.amount is distinct from i.original_amount
   or new.amount is distinct from i.original_amount
 ) then raise exception 'Supplier allocation failed transaction-level conservation'; end if;

 delete from private.hub_kpi_prepared_display_facts f using pg_temp.saw_supplier_replace x
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=x.fact_id;
 delete from private.hub_kpi_prepared_facts f using pg_temp.saw_supplier_replace x
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=x.fact_id;
 insert into private.hub_kpi_prepared_facts select * from pg_temp.saw_supplier_output;
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
 from pg_temp.saw_supplier_output;

 drop table pg_temp.saw_supplier_replace,pg_temp.saw_supplier_output,pg_temp.saw_supplier_recipients,pg_temp.saw_supplier_input;
end $$;

-- The shared-project evidence lookup runs once per candidate cost line.
create index if not exists hub_kpi_prepared_saw_workify_order_idx
 on private.hub_kpi_prepared_facts (tenant_id,generation_id,(original->>'Ordernummer'))
 where source='Workify' and kind='revenue';
