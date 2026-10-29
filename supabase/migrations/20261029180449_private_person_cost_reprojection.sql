create function private.hub_reproject_person_cost_v1(p_tenant uuid,p_generation uuid)returns jsonb
language plpgsql set search_path=''set jit=off as $$
declare n int;
begin
if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'Access denied'using errcode='42501';end if;
if not exists(select 1 from private.hub_kpi_report_state where tenant_id=p_tenant and active_generation=p_generation)then raise exception 'Active generation required';end if;
perform pg_advisory_xact_lock(hashtextextended('person-cost:'||p_tenant,0));
create temporary table person_cost_changes on commit drop as
with candidates as(
select f.*,coalesce(a.before_fact,to_jsonb(f))base,
case when f.source='TransPA'then k.object_id else (f.original#>>'{_humla_approved_time,person_id}')::uuid end person_id,
case when f.source='TransPA'then coalesce((select monthly_salary from public.kpi_personnel_salary_settings where tenant_id=p_tenant and is_default limit 1),34000)
else (f.original#>>'{_humla_approved_time,monthly_salary}')::numeric end baseline
from private.hub_kpi_prepared_facts f
left join private.hub_person_cost_reprojection_v1 a using(tenant_id,generation_id,fact_id)
left join public.hub_identity_keys k on k.tenant_id=f.tenant_id and k.identity_type='transpa_employee_id'and k.identity_value=f.original->>'employee_id'and k.confidence=1
where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost'
and f.source in('TransPA','NEXT-schablon','Verkstadsschablon')and coalesce((f.original->>'actual_payroll')::boolean,false)=false
),changed as(
select c.*,private.hub_person_cost_salary_v1(p_tenant,c.person_id,c.occurred_on,c.baseline)/nullif(c.baseline,0)factor
from candidates c where exists(select 1 from private.hub_person_cost_basis_v1 p where p.tenant_id=p_tenant and p.person_id=c.person_id and p.valid_from<=c.occurred_on and(p.valid_to is null or p.valid_to>=c.occurred_on))
)
select *,((base->>'amount')::numeric)*factor target_amount from changed;
insert into private.hub_person_cost_reprojection_v1(tenant_id,generation_id,fact_id,before_fact)
select p_tenant,p_generation,fact_id,base from person_cost_changes on conflict do nothing;
update private.hub_kpi_prepared_facts f set amount=c.target_amount,
original=case when c.base#>>'{original,_humla_cost_rule,original_amount}'is not null then
jsonb_set(jsonb_set(c.base->'original','{_humla_cost_rule,original_amount}',to_jsonb((c.base#>>'{original,_humla_cost_rule,original_amount}')::numeric*c.factor)),
'{_humla_distribution,original_amount}',to_jsonb((c.base#>>'{original,_humla_cost_rule,original_amount}')::numeric*c.factor))else f.original end
from person_cost_changes c where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=c.fact_id;
get diagnostics n=row_count;
update private.hub_kpi_prepared_display_facts d set amount=f.amount
from private.hub_kpi_prepared_facts f join person_cost_changes c on c.fact_id=f.fact_id
where f.tenant_id=p_tenant and f.generation_id=p_generation and d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id;
update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=p_tenant;
return jsonb_build_object('updated_rows',n);
end $$;
revoke all on function private.hub_reproject_person_cost_v1(uuid,uuid)from public,anon,authenticated;