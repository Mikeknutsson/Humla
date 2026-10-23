-- An explicitly approved project cost scope is separate from vehicle matching.
-- Move existing facts only; no inferred purchases or additional economic rows.
alter table private.hub_kpi_material_separation_settings
 add column project_cost_center text,
 add column project_cost_scope_reference text;

create table private.hub_material_project_scope_audit(
 tenant_id uuid not null,generation_id uuid not null,fact_id text not null,
 occurred_on date not null,amount numeric not null,previous_scope jsonb not null,
 target_unit uuid not null,target_center text not null,approval_reference text not null,
 created_at timestamptz not null default now(),primary key(generation_id,fact_id)
);
alter table private.hub_material_project_scope_audit enable row level security;
revoke all on private.hub_material_project_scope_audit from public,anon,authenticated;

create function private.hub_material_project_cost_scope_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
declare cfg record;before_count bigint;after_count bigint;before_amount numeric;after_amount numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then raise exception 'Generation tenant mismatch';end if;
 select s.*,u.projects[1] project,u.name into cfg
 from private.hub_kpi_material_separation_settings s join public.kpi_units u on u.id=s.material_unit_id and u.tenant_id=s.tenant_id
 where s.tenant_id=p_tenant and s.enabled and nullif(s.project_cost_center,'') is not null
 and nullif(s.project_cost_scope_reference,'') is not null and u.enabled and u.unit_type='project' and cardinality(u.projects)=1;
 if not found then return;end if;
 select count(*),coalesce(sum(amount),0)into before_count,before_amount from private.hub_kpi_prepared_facts where generation_id=p_generation and tenant_id=p_tenant;
 insert into private.hub_material_project_scope_audit(tenant_id,generation_id,fact_id,occurred_on,amount,previous_scope,target_unit,target_center,approval_reference)
 select p_tenant,p_generation,f.fact_id,f.occurred_on,f.amount,
 jsonb_build_object('unit_id',f.unit_id,'unit_name',f.unit_name,'cost_center',f.cost_center,'cost_center_name',f.cost_center_name,'business_group',f.business_group,'classification_source',f.classification_source,'vehicle',f.vehicle),
 cfg.material_unit_id,cfg.project_cost_center,cfg.project_cost_scope_reference
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='NEXT' and f.kind='cost'
 and f.project=cfg.project and f.occurred_on>=cfg.valid_from
 and row(f.unit_id,f.cost_center) is distinct from row(cfg.material_unit_id,cfg.project_cost_center)
 on conflict do nothing;
 update private.hub_kpi_prepared_facts f set unit_id=cfg.material_unit_id,unit_name=cfg.name,vehicle=null,
 cost_center=cfg.project_cost_center,cost_center_name=coalesce((select min(r.cost_center_name)from public.kpi_project_classification_periods r where r.tenant_id=p_tenant and r.cost_center=cfg.project_cost_center),cfg.project_cost_center),
 business_group='Grusmaterial',classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('reason','approved_material_project_cost_scope'),
 original=f.original||jsonb_build_object('_humla_material_project_scope',jsonb_build_object('approval',cfg.project_cost_scope_reference,'cost_center',cfg.project_cost_center,'unit_id',cfg.material_unit_id))
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='NEXT' and f.kind='cost' and f.project=cfg.project and f.occurred_on>=cfg.valid_from;
 select count(*),coalesce(sum(amount),0)into after_count,after_amount from private.hub_kpi_prepared_facts where generation_id=p_generation and tenant_id=p_tenant;
 if row(before_count,before_amount)is distinct from row(after_count,after_amount) then raise exception 'Material project changed financial totals';end if;
end $$;
revoke all on function private.hub_material_project_cost_scope_v1(uuid,uuid) from public,anon,authenticated;

do $migration$
declare definition text;needle text:='perform private.hub_kpi_separate_material_v1(job.tenant_id,generation);';
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(definition,needle)=0 or strpos(definition,'hub_material_project_cost_scope_v1')>0 then raise exception 'Unexpected material worker hook';end if;
 execute replace(definition,needle,needle||chr(10)||' perform private.hub_material_project_cost_scope_v1(job.tenant_id,generation);');
end $migration$;
