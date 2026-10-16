-- Transport leader scorecards: audited, user-scoped financial aggregates.
-- Shared KPI facts stay in Humla Hub; no client-side filtering of full tenant totals.
create or replace function public.hub_transport_leader_scorecard_v1(
 p_tenant_id uuid, p_from date, p_to date, p_user_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=''
as $fn$
declare
 v_caller uuid := auth.uid();
 v_target uuid;
 v_owner boolean;
 v_report jsonb;
 v_units jsonb;
 v_summary jsonb;
begin
 if v_caller is null or p_from is null or p_to is null or p_to < p_from
    or p_to > p_from + 366 then
   raise exception 'invalid_scope_or_period' using errcode='22023';
 end if;
 if not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant_id
   and m.user_id=v_caller and m.status='active') then
   raise exception 'access_denied' using errcode='42501';
 end if;
 select exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant_id
   and m.user_id=v_caller and m.status='active' and m.role='owner') into v_owner;
 v_target := coalesce(p_user_id,v_caller);
 if v_target <> v_caller and not v_owner then
   raise exception 'access_denied' using errcode='42501';
 end if;
 if not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant_id
   and m.user_id=v_target and m.status='active') then
   raise exception 'access_denied' using errcode='42501';
 end if;
 -- Only assignments covering the entire financial reporting interval are eligible.
 -- A mid-period handover MUST NOT grant access to the whole month's historic totals.
 if not exists(select 1 from public.hub_transport_leader_units a join public.kpi_units u
   on u.id=a.unit_id and u.tenant_id=a.tenant_id and u.enabled
   where a.tenant_id=p_tenant_id and a.user_id=v_target
   and a.valid_from<=p_from and (a.valid_to is null or a.valid_to>=p_to)) then
   return jsonb_build_object('from',p_from,'to',p_to,'target_user_id',v_target,
     'units','[]'::jsonb,'summary',jsonb_build_object('revenue',null,'cost',null,'result',null,'fuel',null),
     'quality',jsonb_build_object('status','no_complete_period_assignments'));
 end if;
 -- The existing centralized financial-facts engine performs reconciliation.
 -- This result is NEVER sent to the client before unit-level filtering.
 v_report := public.hub_kpi_unit_report_v2(p_tenant_id,p_from,p_to);
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_units
 from (
   select u.id as unit_id,u.name as unit_name,
     nullif(j->>'revenue','')::numeric as revenue,
     nullif(j->>'cost','')::numeric as cost,
     nullif(j->>'result','')::numeric as result,
     nullif(j->>'fuel','')::numeric as fuel,
     nullif(j->>'row_count','')::integer as row_count
   from jsonb_array_elements(coalesce(v_report->'units','[]'::jsonb)) j
   join public.kpi_units u on u.id=(j->>'unit_id')::uuid and u.tenant_id=p_tenant_id and u.enabled
   where exists(select 1 from public.hub_transport_leader_units a
     where a.tenant_id=p_tenant_id and a.user_id=v_target and a.unit_id=u.id
       and a.valid_from<=p_from and (a.valid_to is null or a.valid_to>=p_to))
   order by u.name
 ) x;
 select jsonb_build_object(
   'revenue',round(sum((j->>'revenue')::numeric),2),
   'cost',round(sum((j->>'cost')::numeric),2),
   'result',round(sum((j->>'result')::numeric),2),
   'fuel',round(sum((j->>'fuel')::numeric),2)
 ) into v_summary from jsonb_array_elements(v_units) j;
 return jsonb_build_object('from',p_from,'to',p_to,'target_user_id',v_target,
   'units',v_units,'summary',v_summary,
   'quality',jsonb_build_object('status','scoped','unit_count',jsonb_array_length(v_units),
    'excluded_unassigned_and_partial_handover',true));
end $fn$;
revoke all on function public.hub_transport_leader_scorecard_v1(uuid,date,date,uuid) from public;
grant execute on function public.hub_transport_leader_scorecard_v1(uuid,date,date,uuid) to authenticated;
