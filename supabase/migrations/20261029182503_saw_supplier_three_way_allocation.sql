create function private.hub_allocate_saw_supplier_common_v1(p_tenant uuid,p_generation uuid)returns void
language plpgsql set search_path=''set jit=off as $$
declare f private.hub_kpi_prepared_facts;o private.hub_kpi_prepared_facts;v record;total numeric;saw_part numeric;entre_part numeric;pool numeric;piece numeric;used numeric;n int;i int;meta jsonb;
begin
if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'Access denied'using errcode='42501';end if;
delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_supplier_common';
delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_supplier_common';
for f in select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='cost'
and original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and original#>>'{_humla_saw_activity,branch}'='retained'
loop
total:=(f.original#>>'{_humla_saw_activity,original_amount}')::numeric;
saw_part:=round(total*0.5,2);entre_part:=round(total*0.25,2);pool:=total-saw_part-entre_part;
update private.hub_kpi_prepared_facts set amount=saw_part,
original=jsonb_set(jsonb_set(original,'{_humla_saw_activity,share}','0.5'),'{_humla_saw_activity,allocated_amount}',to_jsonb(saw_part)),
display_original=jsonb_set(jsonb_set(display_original,'{_humla_saw_activity,share}','0.5'),'{_humla_saw_activity,allocated_amount}',to_jsonb(saw_part))
where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id||':saw';
update private.hub_kpi_prepared_facts set amount=entre_part,cost_center='10',unit_id=null,unit_name=null,business_group=null,
original=jsonb_set(jsonb_set(original,'{_humla_saw_activity,share}','0.5'),'{_humla_saw_activity,allocated_amount}',to_jsonb(saw_part)),
display_original=jsonb_set(jsonb_set(display_original,'{_humla_saw_activity,share}','0.5'),'{_humla_saw_activity,allocated_amount}',to_jsonb(saw_part))
where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
i:=0;used:=0;
for v in
with rev as(select unit_id,sum(amount)revenue from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='revenue'and cost_center='30'and unit_id is not null
and occurred_on>=date_trunc('month',f.occurred_on)::date and occurred_on<(date_trunc('month',f.occurred_on)+interval'1 month')::date
and not coalesce((original->>'_humla_excluded_from_kpi')::boolean,false)group by unit_id having sum(amount)>0),
eligible as(select distinct u.id,p.period->>'name'name,coalesce(g.name,'Ej klassificerat')business_group
from rev join public.hub_objects u on u.tenant_id=p_tenant and u.id=rev.unit_id and u.object_type='EconomicUnit'
cross join lateral jsonb_array_elements(u.data->'periods')p(period)
left join public.kpi_business_groups g on g.tenant_id=p_tenant and g.id::text=p.period->>'business_group_id'
where coalesce((p.period->>'enabled')::boolean,false)and(p.period->>'valid_from')::date<=f.occurred_on and(p.period->>'valid_to'is null or(p.period->>'valid_to')::date>=f.occurred_on))
select *,count(*)over()parts from eligible order by id
loop
n:=v.parts;i:=i+1;piece:=case when i=n then pool-used else round(pool/n,2)end;used:=used+piece;
o:=f;o.fact_id:=f.fact_id||':supplier-common:'||v.id;o.amount:=piece;o.category:='management';o.unit_id:=v.id;o.unit_name:=v.name;o.business_group:=v.business_group;o.cost_center:='30';o.cost_center_name:='Transport';o.vehicle:=null;
meta:=jsonb_build_object('engine','supplier_three_way_v1','original_fact_id',f.fact_id,'original_amount',total,'direct_saw_share',0.5,'transport_pool_share',0.25,'enterprise_share',0.25,'recipient_count',n,'method','equal_positive_monthly_revenue_units');
o.original:=jsonb_set(f.original,'{_humla_saw_activity,branch}','"shared_transport"')||jsonb_build_object('_humla_supplier_common',meta);
o.display_original:=jsonb_set(f.display_original,'{_humla_saw_activity,branch}','"shared_transport"')||jsonb_build_object('_humla_supplier_common',meta);
insert into private.hub_kpi_prepared_facts select(o).*;
end loop;
if i=0 or used<>pool then raise exception 'Supplier pool has no eligible recipients or failed conservation';end if;
end loop;
delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts f
where f.tenant_id=p_tenant and f.generation_id=p_generation and f.original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id;
insert into private.hub_kpi_prepared_display_facts
select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original#>>'{_humla_saw_activity,reason}'='supplier_work_full';
end $$;
revoke all on function private.hub_allocate_saw_supplier_common_v1(uuid,uuid)from public,anon,authenticated;
do $migration$
declare d text;
begin
select pg_get_functiondef('private.hub_apply_saw_activity_v1(uuid,uuid)'::regprocedure)into d;
d:=replace(d,'select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals',
'perform private.hub_allocate_saw_supplier_common_v1(p_tenant,p_generation);'||chr(10)||'select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals');
execute d;
end $migration$;