-- Read-only review of published facts against current canonical project evidence.
-- A current project snapshot never rewrites historical financial classification.
create or replace function public.hub_kpi_unclassified_projects_v1(p_tenant_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid reconciliation period';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then return jsonb_build_object('available',false);end if;
 with facts as materialized(
 select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant_id and generation_id=generation
 and occurred_on between p_from and p_to and cost_center='unclassified'
 ), grouped as(
 select source,kind,project,count(*) rows,round(sum(amount),2) amount,min(occurred_on) first_date,max(occurred_on) last_date
 from facts group by source,kind,project
 ), evidence as(
 select f.*,p.matches,p.object_id,p.project_name,p.cost_center,p.effective_date,
 case when p.matches=0 then 'missing_project_evidence' when p.matches<>1 then 'ambiguous_project_identity'
 when nullif(p.cost_center,'') is null then 'missing_cost_center'
 when p.effective_date is null then 'missing_effective_date'
 when p.effective_date>f.first_date::text then 'historical_date_review'
 else 'classification_review' end reason
 from grouped f left join lateral(
 select count(*) matches,min(o.id::text) object_id,min(o.data->>'display_name') project_name,
 min(o.data#>>'{project_register,cost_center}') cost_center,
 min(o.data#>>'{project_register,source,effective_date}') effective_date
 from public.hub_objects o where o.tenant_id=p_tenant_id and o.object_type='Project' and o.data->>'project_number'=f.project
 )p on true
 )select jsonb_build_object('available',true,'generation',generation,'rows',(select count(*) from facts),
 'cost',coalesce((select round(sum(amount),2) from facts where kind='cost'),0),
 'revenue',coalesce((select round(sum(amount),2) from facts where kind='revenue'),0),
 'projects',coalesce((select jsonb_agg(to_jsonb(e) order by abs(amount) desc,source,kind,project) from evidence e),'[]'::jsonb))into answer;
 return answer;
end $$;
revoke all on function public.hub_kpi_unclassified_projects_v1(uuid,date,date) from public,anon;
grant execute on function public.hub_kpi_unclassified_projects_v1(uuid,date,date) to authenticated,service_role;
