-- Completeness diagnostics only. No payroll or allocation is inferred from account numbers.
create or replace function public.hub_kpi_personnel_coverage_v1(p_tenant_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid reconciliation period';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then return jsonb_build_object('available',false);end if;
 with facts as materialized(
 select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant_id and generation_id=generation
 and occurred_on between p_from and p_to and kind='cost'
 ), evidence as(
 select cost_center,source,category,
 case when source='TransPA' and original->>'actual_payroll'='true' then 'actual_payroll_flag'
 when source='TransPA' and original->>'actual_payroll'='false' then 'estimated_payroll'
 when source='TransPA' then 'payroll_basis_missing'
 when source='NEXT' and account='7010' and original->>'Verifikation nr' like 'ARB.%' then 'next_work_time_reference'
 else 'mapped_personnel_expense' end basis,
 count(*) rows,round(sum(amount),2) amount
 from facts where source='TransPA' or category='personnel' or (source='NEXT' and account='7010')
 group by 1,2,3,4
 ), centers as(select * from(values('20','Sortergården'),('30','Transport'),('40','Verkstad'),('unclassified','Ej klassificerat'))c(code,name))
 select jsonb_build_object('available',true,'generation',generation,
 'centers',(select jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,
 'sources',coalesce((select jsonb_agg(to_jsonb(e) order by source,basis,category) from evidence e where e.cost_center=c.code),'[]'::jsonb)) order by c.code) from centers c),
 'registered_personnel_projects',coalesce((select jsonb_agg(jsonb_build_object('object_id',o.id,'name',o.data->>'display_name',
 'project',o.data->>'project_number','current_center',o.data#>>'{project_register,cost_center}',
 'effective_date',o.data#>>'{project_register,source,effective_date}')order by o.data#>>'{project_register,cost_center}',o.data->>'display_name')
 from public.hub_objects o where o.tenant_id=p_tenant_id and o.object_type='Project'
 and o.data#>>'{project_register,business_group}'='Personal' and o.data#>>'{project_register,cost_center}' in('20','40')),'[]'::jsonb),
 'salary_resources',(select count(*) from public.hub_transpa_salary_resources r where r.tenant_id=p_tenant_id
 and r.period_start<=p_to and r.period_end>=p_from),
 'registered_transpa_people',(select count(*) from public.hub_transpa_persons p where p.tenant_id=p_tenant_id))into answer;
 return answer;
end $$;
revoke all on function public.hub_kpi_personnel_coverage_v1(uuid,date,date) from public,anon;
grant execute on function public.hub_kpi_personnel_coverage_v1(uuid,date,date) to authenticated,service_role;
