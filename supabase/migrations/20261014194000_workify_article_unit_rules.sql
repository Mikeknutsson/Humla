-- Explicit article routing references canonical Humla economic units.
create table private.hub_workify_article_unit_rules(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 article_contains text not null check(length(trim(article_contains)) between 2 and 200),
 target_unit_id uuid not null references public.hub_objects(id),
 valid_from date not null,valid_to date,enabled boolean not null default true,
 approval_reference text not null,created_by uuid not null,created_at timestamptz not null default now(),
 check(valid_to is null or valid_to>=valid_from),unique(tenant_id,article_contains,valid_from)
);
alter table private.hub_workify_article_unit_rules enable row level security;
revoke all on private.hub_workify_article_unit_rules from public,anon,authenticated;
create table private.hub_article_unit_routing_audit(
 tenant_id uuid not null,generation_id uuid not null,fact_id text not null,
 rule_id uuid references private.hub_workify_article_unit_rules(id),
 before_record jsonb not null,after_record jsonb not null,actor uuid not null,
 created_at timestamptz not null default now(),primary key(generation_id,fact_id)
);
alter table private.hub_article_unit_routing_audit enable row level security;
revoke all on private.hub_article_unit_routing_audit from public,anon,authenticated;
create function private.hub_apply_workify_article_units_v1(p_tenant uuid,p_generation uuid)
returns integer language plpgsql set search_path='' set plan_cache_mode='force_custom_plan' as $$
declare r record;t record;n integer:=0;before_count bigint;before_amount numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 select count(*),sum(amount) into before_count,before_amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 for r in select f.*,a.id rule_id,a.target_unit_id from private.hub_kpi_prepared_facts f
 join private.hub_workify_article_unit_rules a on a.tenant_id=f.tenant_id and a.enabled and f.occurred_on>=a.valid_from and (a.valid_to is null or f.occurred_on<=a.valid_to)
 and strpos(lower(coalesce(nullif(f.original->>'Artikelnamn',''),f.description,'')),lower(trim(a.article_contains)))>0
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='Workify' and f.kind='revenue'
 loop
  if exists(select 1 from private.hub_workify_article_unit_rules a where a.tenant_id=p_tenant and a.enabled and a.id<>r.rule_id and a.target_unit_id<>r.target_unit_id
   and r.occurred_on>=a.valid_from and (a.valid_to is null or r.occurred_on<=a.valid_to)
   and strpos(lower(coalesce(nullif(r.original->>'Artikelnamn',''),r.description,'')),lower(trim(a.article_contains)))>0)then raise exception 'Conflicting article routing requires review';end if;
  select u.id,p.payload->>'name' name,p.payload->>'main_vehicle' vehicle,p.payload->'projects'->>0 project,g.name grp,
   pc.cost_center,pc.cost_center_name into strict t
  from public.kpi_units u join public.hub_objects h on h.id=u.id and h.tenant_id=u.tenant_id and h.object_type='EconomicUnit'
  join public.kpi_unit_periods p on p.unit_id=u.id and p.tenant_id=u.tenant_id and p.valid_from<=r.occurred_on and (p.valid_to is null or p.valid_to>=r.occurred_on)
  join public.kpi_business_groups g on g.id::text=p.payload->>'business_group_id' and g.tenant_id=u.tenant_id and g.enabled
  join public.kpi_project_classification_periods pc on pc.tenant_id=u.tenant_id and pc.project_reference=p.payload->'projects'->>0 and pc.valid_from<=r.occurred_on and (pc.valid_to is null or pc.valid_to>=r.occurred_on)
  where u.tenant_id=p_tenant and u.id=r.target_unit_id and (p.payload->>'enabled')::boolean;
  if t.vehicle is null or t.project is null then raise exception 'Article target lacks confirmed vehicle/project';end if;
  if row(r.unit_id,r.vehicle,r.project,r.cost_center,r.business_group) is not distinct from row(t.id,t.vehicle,t.project,t.cost_center,t.grp)then continue;end if;
  insert into private.hub_article_unit_routing_audit(tenant_id,generation_id,fact_id,rule_id,before_record,after_record,actor)
  values(p_tenant,p_generation,r.fact_id,r.rule_id,to_jsonb(r),jsonb_build_object('unit_id',t.id,'vehicle',t.vehicle,'project',t.project,'cost_center',t.cost_center,'business_group',t.grp),auth.uid()) on conflict do nothing;
  update private.hub_kpi_prepared_facts set unit_id=t.id,unit_name=t.name,vehicle=t.vehicle,project=t.project,cost_center=t.cost_center,cost_center_name=t.cost_center_name,business_group=t.grp,
   classification_source=coalesce(classification_source,'{}')||jsonb_build_object('article_unit_rule',r.rule_id,'reason','confirmed_article_unit_rule'),
   display_original=display_original||jsonb_build_object('_humla_article_unit_rule',r.rule_id)
  where tenant_id=p_tenant and generation_id=p_generation and fact_id=r.fact_id;
  update private.hub_kpi_prepared_display_facts set unit_id=t.id,unit_name=t.name,vehicle=t.vehicle,project=t.project,cost_center=t.cost_center,business_group=t.grp,
   original=original||jsonb_build_object('_humla_article_unit_rule',r.rule_id)
  where tenant_id=p_tenant and generation_id=p_generation and fact_id=r.fact_id;
  n:=n+1;
 end loop;
 if row(before_count,before_amount) is distinct from (select row(count(*),sum(amount))from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)then raise exception 'Article routing changed financial totals';end if;
 return n;
end $$;
revoke all on function private.hub_apply_workify_article_units_v1(uuid,uuid) from public,anon,authenticated;
do $migration$
declare d text;needle text:='perform private.hub_apply_cost_allocation_v1(job.tenant_id,generation);';
begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected publication worker';end if;
 execute replace(d,needle,'perform private.hub_apply_workify_article_units_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;
