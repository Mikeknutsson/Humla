select pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
CREATE OR REPLACE FUNCTION private.hub_apply_monthly_overhead_v1(p_tenant uuid, p_generation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare before_base numeric;after_base numeric;result jsonb;asof_date date:=(clock_timestamp() at time zone 'Europe/Stockholm')::date;
begin
if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then raise exception 'Generation mismatch';end if;
perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
select sum(amount) into before_base from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and not(original?'_humla_monthly_overhead');
delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_monthly_overhead';
delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_monthly_overhead';
create temporary table monthly_overhead_output on commit drop as
with rules as materialized(
 select r.* from public.hub_cost_allocation_rules r where r.tenant_id=p_tenant and r.enabled and r.include_in_vehicle_result
 and r.source_scope->>'engine'='monthly_overhead_v1' and r.allocation_method in ('revenue_share','equal')
 and r.monthly_amount>=0 and r.valid_from<=asof_date),
months as materialized(
 select r.*,m.dt::date month_start,
 greatest(m.dt::date,r.valid_from) first_day,
 least((m.dt+interval '1 month -1 day')::date,coalesce(r.valid_to,asof_date),asof_date) last_day,
 extract(day from m.dt+interval '1 month -1 day')::numeric month_days
 from rules r cross join lateral generate_series(date_trunc('month',r.valid_from),date_trunc('month',least(coalesce(r.valid_to,asof_date),asof_date)),interval '1 month')m(dt)),
revenue as materialized(
 select date_trunc('month',f.occurred_on)::date month_start,
 public.hub_resolve_canonical_object_v1(p_tenant,f.unit_id) unit_id,
 f.cost_center,max(f.unit_name) unit_name,max(f.business_group) business_group,max(f.vehicle) vehicle,
 greatest(sum(f.amount),0) weight
 from private.hub_kpi_prepared_facts f
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='revenue' and f.unit_id is not null and f.occurred_on<=asof_date
 and f.occurred_on>=(select min(valid_from) from rules)
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and f.cost_center in('20','30')
 and private.hub_overhead_unit_eligible_v1(p_tenant,f.unit_id,f.cost_center,f.occurred_on)
 group by 1,2,3 having sum(f.amount)>0),
recipients as materialized(
 select candidate.*,
 sum(weight)over(partition by id,month_start) total_weight,
 count(*)over(partition by id,month_start) recipient_count
 from (
  select m.*,v.unit_id,v.cost_center,v.unit_name,v.business_group,v.vehicle,v.weight,
   row_number()over(partition by m.id,m.month_start,v.unit_id order by v.weight desc,v.cost_center) unit_rank
  from months m join revenue v on v.month_start=m.month_start and m.target_scope->'cost_centers' ? v.cost_center
  where m.last_day>=m.first_day
 ) candidate
 where allocation_method<>'equal' or unit_rank=1),
daily as(
 select r.*,d.dt::date occurred_on,round(r.monthly_amount*(r.last_day-r.first_day+1)/r.month_days,2) period_total,
 (case when r.allocation_method='equal' then 1::numeric/r.recipient_count else r.weight/r.total_weight end)/(r.last_day-r.first_day+1) share
 from recipients r cross join lateral generate_series(r.first_day::timestamp,r.last_day::timestamp,interval '1 day')d(dt)),
allocated as(
 select d.*,round(period_total*sum(share)over(partition by id,month_start order by occurred_on,unit_id,cost_center rows unbounded preceding),2)
 -round(period_total*coalesce(sum(share)over(partition by id,month_start order by occurred_on,unit_id,cost_center rows between unbounded preceding and 1 preceding),0),2) amount
 from daily d),
outputs as(
 select a.id rule_id,a.name,month_start,occurred_on,unit_id,cost_center,unit_name,business_group,vehicle,amount,monthly_amount,base_amount,po_percent,cost_category,
 jsonb_build_object('rule_id',id,'rule_name',name,'month',month_start,'monthly_amount',monthly_amount,'base_salary',base_amount,'po_percent',po_percent,
 'method',allocation_method,'recipient_count',recipient_count,'unit_month_revenue',weight,'scope_month_revenue',total_weight,'cost_group','overhead',
 'cost_type',case when common_cost_type='management' then 'management' else 'other' end,
 'status','allocated','basis',case when allocation_method='equal' then 'Equal amount per eligible economic unit, allocated daily' else 'Monthly net positive revenue share, allocated daily' end) meta from allocated a
 union all
 select m.id,m.name,m.month_start,d.dt::date,null::uuid,
 case when jsonb_array_length(m.target_scope->'cost_centers')=1 then m.target_scope#>>'{cost_centers,0}' else 'unclassified' end,
 'Overhead – saknar omsättningsunderlag','Ej fördelat',null::text,
 round(m.monthly_amount*(d.dt::date-m.first_day+1)/m.month_days,2)-round(m.monthly_amount*(d.dt::date-m.first_day)/m.month_days,2),
 m.monthly_amount,m.base_amount,m.po_percent,m.cost_category,
 jsonb_build_object('rule_id',m.id,'rule_name',m.name,'month',m.month_start,'monthly_amount',m.monthly_amount,
 'cost_group','overhead','cost_type',case when m.common_cost_type='management' then 'management' else 'other' end,'status','no_revenue_basis')
 from months m cross join lateral generate_series(m.first_day::timestamp,m.last_day::timestamp,interval '1 day')d(dt)
 where not exists(select 1 from recipients r where r.id=m.id and r.month_start=m.month_start))
select o.*,jsonb_build_object('_humla_monthly_overhead',meta,'Description',name) evidence from outputs o;

insert into private.hub_kpi_prepared_facts
(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,description,original,cost_center,cost_center_name,classification_source,display_original)
select p_generation,p_tenant,extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,
'overhead:'||rule_id||':'||occurred_on||':'||coalesce(unit_id::text,'unresolved')||':'||cost_center,
occurred_on,'cost',amount,cost_category,null,vehicle,unit_id,unit_name,business_group,'Overhead',name,evidence,cost_center,
case cost_center when '20' then 'Sortergården' when '30' then 'Transport' else 'Ej fördelat' end,
jsonb_build_object('source','monthly_overhead_v1','rule_id',rule_id),evidence
from pg_temp.monthly_overhead_output;
insert into private.hub_kpi_prepared_display_facts
select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_monthly_overhead';
if exists(
 select 1 from (select rule_id,month_start,sum(amount) actual,max(monthly_amount) monthly_amount,count(distinct occurred_on) days from pg_temp.monthly_overhead_output group by 1,2)x
 where actual<>round(monthly_amount*days/extract(day from month_start+interval '1 month -1 day'),2))then raise exception 'Monthly overhead does not reconcile';end if;
select sum(amount) into after_base from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and not(original?'_humla_monthly_overhead');
if before_base is distinct from after_base then raise exception 'Overhead changed source totals';end if;
select jsonb_build_object('rows',count(*),'cost',sum(amount),'unallocated_cost',coalesce(sum(amount)filter(where meta->>'status'<>'allocated'),0)) into result from pg_temp.monthly_overhead_output;
drop table pg_temp.monthly_overhead_output;
return result;
end $function$;
do $change$
declare r record; active uuid;
begin
 for r in
  update public.hub_cost_allocation_rules
  set allocation_method='equal'
  where enabled and source_scope->>'engine'='monthly_overhead_v1'
    and common_cost_type='other' and target_scope->'cost_centers' @> '["20","30"]'::jsonb
    and allocation_method='revenue_share'
  returning tenant_id
 loop
  select active_generation into active from private.hub_kpi_report_state where tenant_id=r.tenant_id for update;
  if active is not null then
   perform private.hub_apply_monthly_overhead_v1(r.tenant_id,active);
   perform private.hub_validate_report_projection_v1(r.tenant_id,active);
   update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=r.tenant_id;
  end if;
 end loop;
end;
$change$;