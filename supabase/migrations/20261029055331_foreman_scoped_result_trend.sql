-- Daily cumulative totals use the same canonical scope and targets as scorecard v4.
create or replace function public.hub_foreman_result_trend_v1(
 p_tenant uuid,p_from date,p_to date,p_user uuid
) returns jsonb language plpgsql stable security definer
set search_path='' set jit='off' as $fn$
declare output jsonb;
begin
 -- The existing helper validates dates, auth.uid, tenant, owner preview,
 -- dated canonical-unit responsibility and Sortergarden's KST20-only scope.
 with facts as materialized (
  select f.occurred_on,f.kind,f.amount,coalesce(t.margin_percent,g.margin_percent) target
  from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user) f
  left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id
   and t.valid_from<=f.occurred_on and (t.valid_to is null or t.valid_to>=f.occurred_on)
  left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group
 ), daily as (
  select occurred_on,coalesce(sum(amount) filter(where kind='revenue'),0) revenue,
   coalesce(sum(amount) filter(where kind='cost'),0) cost,
   sum(amount*target/100) filter(where kind='revenue') target_result,
   count(*) filter(where kind='revenue' and amount<>0 and target is null) missing_targets,
   count(*) filter(where kind='revenue' and amount<>0 and target is not null) targeted_rows
  from facts group by occurred_on
 ), cumulative as (
  select occurred_on,sum(revenue) over w revenue,sum(cost) over w cost,
   sum(target_result) over w target_result,sum(missing_targets) over w missing_targets,
   sum(targeted_rows) over w targeted_rows
  from daily window w as (order by occurred_on rows between unbounded preceding and current row)
 ), points as (
  select occurred_on date,revenue,cost,revenue-cost result,
   case when revenue>0 then (revenue-cost)/revenue*100 end margin_percent,
   case when missing_targets=0 and targeted_rows>0 then target_result end target_result,
   case when missing_targets=0 and targeted_rows>0 and revenue>0 then target_result/revenue*100 end target_margin_percent,
   case when missing_targets=0 and targeted_rows>0 then revenue-cost-target_result end deviation_amount,
   missing_targets
  from cumulative
 )
 select jsonb_build_object('from',p_from,'to',p_to,
  'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
  'points',coalesce((select jsonb_agg(to_jsonb(p) order by date) from points p),'[]'::jsonb),
  'latest',(select to_jsonb(p) from points p order by date desc limit 1)
 ) into output;
 return output;
end $fn$;
revoke all on function public.hub_foreman_result_trend_v1(uuid,date,date,uuid) from public,anon;
grant execute on function public.hub_foreman_result_trend_v1(uuid,date,date,uuid) to authenticated;
comment on function public.hub_foreman_result_trend_v1(uuid,date,date,uuid) is
 'Read-only daily cumulative financial result and revenue-weighted margin goal for the existing authorized foreman scope. Missing goals remain null. No annual-budget extrapolation.';
