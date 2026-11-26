select pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));

create or replace function private.hub_allocate_transport_management_vehicles_v1(p_tenant uuid,p_generation uuid)
returns void
language plpgsql
set search_path = ''
as $function$
begin
 if not exists(select 1 from public.hub_tenants where id=p_tenant and slug='elleholms') then return; end if;

 -- These NEXT projects cover Transport's management vehicles. Payroll and
 -- other operating projects stay outside this rule.
 create temporary table transport_management_source on commit drop as
 select f.*
 from private.hub_kpi_prepared_facts f
 where f.tenant_id=p_tenant and f.generation_id=p_generation
  and f.fiscal_year>=2025 and f.cost_center='30' and f.kind='cost'
  and f.business_group='Arbetsledning' and (f.unit_id is null or f.unit_name='Övrigt')
  and (f.project,f.vehicle) in (('2059','MDE75S'),('2063','SOU57P'))
  and ((f.source='NEXT' and f.account ~ '^(5[0-9]{3}|6[0-9]{3}|8410)$'
        and f.category in ('fixed','fuel','service_repair','other'))
       or (f.source='Piusi' and f.category='fuel'))
  and f.amount<>0 and f.amount=round(f.amount,2)
  and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
  and not (coalesce(f.original,'{}') ?| array['_humla_cost_rule','_humla_transport_management_vehicle',
   '_humla_monthly_overhead','_humla_transport_staff','_humla_saw_activity'])
  and (f.original#>>'{_humla_distribution,status}') is distinct from 'allocated';

 create temporary table transport_management_output on commit drop as
 with recipients as materialized (
  -- Use the same monthly revenue basis as the published Transport
  -- management overhead, including its unit exclusion rules.
  select f.occurred_on,f.unit_id,max(f.unit_name) unit_name,max(f.business_group) business_group,
   max((f.original#>>'{_humla_monthly_overhead,unit_month_revenue}')::numeric) weight,
   min(f.original#>>'{_humla_monthly_overhead,rule_id}') rule_id
  from private.hub_kpi_prepared_facts f
  join public.hub_cost_allocation_rules r on r.tenant_id=f.tenant_id
   and r.id::text=f.original#>>'{_humla_monthly_overhead,rule_id}'
  where f.tenant_id=p_tenant and f.generation_id=p_generation
   and f.cost_center='30' and f.source='Overhead' and f.category='management'
   and f.unit_id is not null
   and f.unit_name not in ('Trading Material','Grusmaterial - Lager','Grusmaterial Försäljning','Övrigt')
   and r.enabled and r.allocation_method='revenue_share'
   and r.target_scope->'cost_centers'='["30"]'::jsonb
   and f.original#>>'{_humla_monthly_overhead,status}'='allocated'
   and exists(select 1 from pg_temp.transport_management_source s where s.occurred_on=f.occurred_on)
   and not exists (
    select 1 from private.hub_kpi_prepared_display_facts e
    where e.tenant_id=p_tenant and e.generation_id=p_generation and e.cost_center='30'
     and e.unit_id=f.unit_id and e.kind='revenue'
     and e.occurred_on between date_trunc('month',f.occurred_on)::date
         and (date_trunc('month',f.occurred_on)+interval '1 month -1 day')::date
    group by e.unit_id
    having bool_and(coalesce(e.category in ('material','tipp','tipp_deponi'),false))
   )
  group by f.occurred_on,f.unit_id
  having count(distinct r.id)=1
 ), shares as (
  select s.fact_id,r.*,
   sum(r.weight) over (partition by s.fact_id) total_weight,
   sum(r.weight) over (partition by s.fact_id order by r.unit_id rows unbounded preceding) cumulative_weight,
   row_number() over (partition by s.fact_id order by r.unit_id) ordinal
  from pg_temp.transport_management_source s join recipients r using(occurred_on)
  where r.weight>0
 )
 select allocated.*
 from shares r join pg_temp.transport_management_source s using(fact_id)
 cross join lateral (
  select jsonb_build_object(
   'original_fact_id',s.fact_id,'original_amount',s.amount,
   'original_category',s.category,'original_vehicle',s.vehicle,
   'rule_id',r.rule_id,'method','revenue_share','status','allocated'
  ) evidence
 ) a
 cross join lateral jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(s)||jsonb_build_object(
  'fact_id',case when r.ordinal=1 then s.fact_id else s.fact_id||':management-vehicle:'||r.unit_id end,
  'unit_id',r.unit_id,'unit_name',r.unit_name,'business_group',r.business_group,
  'vehicle',null,'category','overhead',
  'amount',round(s.amount*r.cumulative_weight/r.total_weight,2)
          -round(s.amount*(r.cumulative_weight-r.weight)/r.total_weight,2),
  'original',coalesce(s.original,'{}')||jsonb_build_object('_humla_transport_management_vehicle',a.evidence),
  'display_original',coalesce(s.display_original,'{}')||jsonb_build_object('_humla_transport_management_vehicle',a.evidence)
 )) allocated;

 if exists (
  select 1 from pg_temp.transport_management_output o join pg_temp.transport_management_source s
   on o.original#>>'{_humla_transport_management_vehicle,original_fact_id}'=s.fact_id
  group by s.fact_id,s.amount having sum(o.amount)<>s.amount
 ) then raise exception 'Transport management vehicle costs do not reconcile'; end if;

 delete from private.hub_kpi_prepared_display_facts f using pg_temp.transport_management_output o
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=o.fact_id;
 delete from private.hub_kpi_prepared_facts f using pg_temp.transport_management_output o
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=o.fact_id;

 insert into private.hub_kpi_prepared_facts select * from pg_temp.transport_management_output;
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,
  unit_id,unit_name,business_group,source,cost_center,display_original
 from pg_temp.transport_management_output;
 drop table pg_temp.transport_management_output,pg_temp.transport_management_source;
end;
$function$;

revoke all on function private.hub_allocate_transport_management_vehicles_v1(uuid,uuid) from public,anon,authenticated;

-- Run after the monthly overhead has established its recipient basis.
do $install$
declare
 definition text:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 anchor constant text:='perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);';
 hook constant text:='perform private.hub_allocate_transport_management_vehicles_v1(job.tenant_id,generation);';
begin
 if position(hook in definition)>0 then return; end if;
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Report worker no longer has the expected monthly overhead step';
 end if;
 execute replace(definition,anchor,anchor||chr(10)||hook);
end;
$install$;

-- Keep the review buckets in the report totals but independent from the
-- groups that contain trading and tipping.
do $review$
declare
 definition text:=pg_get_functiondef('private.hub_transport_leader_facts_v2(uuid,date,date,uuid)'::regprocedure);
 anchor constant text:=$old$case when extra.include then 'Ej tilldelat – Transport' else f.business_group end$old$;
 replacement constant text:=$new$case when not extra.include then f.business_group
  when b.bucket=33 then 'Ej klassificerat – Workify' when b.bucket=34 then 'Ej fördelat – Transport'
  else 'Ej tilldelat – Transport' end$new$;
begin
 if position(replacement in definition)>0 then return; end if;
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Transport report no longer has the expected review grouping';
 end if;
 execute replace(definition,anchor,replacement);
end;
$review$;

do $backfill$
declare workspace record;
begin
 for workspace in
  select s.tenant_id,s.active_generation from private.hub_kpi_report_state s
  join public.hub_tenants t on t.id=s.tenant_id
  where t.slug='elleholms' and s.active_generation is not null for update of s
 loop
  perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||workspace.tenant_id::text,0));
  perform private.hub_allocate_transport_management_vehicles_v1(workspace.tenant_id,workspace.active_generation);
  perform private.hub_validate_report_projection_v1(workspace.tenant_id,workspace.active_generation);
  update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=workspace.tenant_id;
 end loop;
end;
$backfill$;
