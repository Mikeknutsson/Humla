-- Approved reporting estimates are not supplier invoices or import rows.
create table private.hub_kpi_provisional_supplier_costs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 unit_id uuid not null references public.hub_objects(id),supplier_name text not null,
 month_start date not null,amount numeric not null check(amount>0),
 basis jsonb not null,approved_by uuid not null,approved_at timestamptz not null default now(),
 enabled boolean not null default true,
 unique(tenant_id,unit_id,supplier_name,month_start),
 check(month_start=date_trunc('month',month_start)::date)
);
alter table private.hub_kpi_provisional_supplier_costs enable row level security;
revoke all on private.hub_kpi_provisional_supplier_costs from public,anon,authenticated;
create function private.hub_kpi_publish_provisional_supplier_costs_v1(p_tenant uuid,p_generation uuid)
returns jsonb language plpgsql set search_path='' set plan_cache_mode='force_custom_plan' as $$
declare e record;t record;fid text;raw jsonb;changed integer:=0;suppressed integer:=0;last_date date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 for e in select * from private.hub_kpi_provisional_supplier_costs where tenant_id=p_tenant loop
  fid:='provisional-supplier-cost:'||e.id::text;last_date:=(e.month_start+interval '1 month - 1 day')::date;
  if not e.enabled or exists(select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation
    and f.source='NEXT' and f.kind='cost' and f.occurred_on between e.month_start and last_date
    and upper(trim(f.original->>'Leverantör'))=upper(trim(e.supplier_name))) then
   -- Only this recoverable derived estimate is removed; approval and basis remain.
   delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=fid and source='Preliminär arbetskostnad';
   delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=fid and source='Preliminär arbetskostnad';
   suppressed:=suppressed+1;continue;
  end if;
  if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=fid)then continue;end if;
  select p.payload->>'name' name,p.payload->>'main_vehicle' vehicle,p.payload->'projects'->>0 project,
   coalesce(g.name,c.business_group,'Ej klassificerat') grp,c.cost_center,c.cost_center_name into strict t
  from public.kpi_units u join public.hub_objects h on h.id=u.id and h.tenant_id=u.tenant_id and h.object_type='EconomicUnit'
  join public.kpi_unit_periods p on p.unit_id=u.id and p.tenant_id=u.tenant_id and p.valid_from<=last_date and (p.valid_to is null or p.valid_to>=last_date)
  join public.kpi_project_classification_periods c on c.tenant_id=u.tenant_id and c.project_reference=p.payload->'projects'->>0 and c.valid_from<=last_date and (c.valid_to is null or c.valid_to>=last_date)
  left join public.kpi_business_groups g on g.tenant_id=u.tenant_id and g.id::text=p.payload->>'business_group_id' and g.enabled
  where u.tenant_id=p_tenant and u.id=e.unit_id and (p.payload->>'enabled')::boolean;
  raw:=jsonb_build_object('Preliminär',true,'Leverantör',e.supplier_name,'Status','Saknar faktura – preliminär arbetskostnad',
   'Underlag',e.basis,'_humla_provisional_cost',jsonb_build_object('id',e.id,'approved_by',e.approved_by,'approved_at',e.approved_at,'month',e.month_start,'amount',e.amount,'replacement','Replaced when actual NEXT supplier cost is published for this month'));
  insert into private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,description,original,cost_center,cost_center_name,classification_source,display_original)
  values(p_generation,p_tenant,extract(year from e.month_start)::integer-case when extract(month from e.month_start)<9 then 1 else 0 end,
   fid,last_date,'cost',e.amount,'personnel',t.project,t.vehicle,e.unit_id,t.name,t.grp,'Preliminär arbetskostnad',
   'PRELIMINÄR – '||e.supplier_name||' – ersättningsbelopp enligt godkänt föregående månadsunderlag',raw,t.cost_center,t.cost_center_name,jsonb_build_object('provisional_supplier_cost',e.id),raw);
  insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
  from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=fid;
  changed:=changed+1;
 end loop;
 return jsonb_build_object('added',changed,'suppressed',suppressed);
end $$;
revoke all on function private.hub_kpi_publish_provisional_supplier_costs_v1(uuid,uuid) from public,anon,authenticated;
do $migration$
declare d text;needle text:='perform private.hub_ps_validate_fuel_v1(job.tenant_id,generation);';
begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(d,needle)=0 or strpos(d,'hub_kpi_publish_provisional_supplier_costs_v1')>0 then raise exception 'Unexpected worker hook';end if;
 execute replace(d,needle,'perform private.hub_kpi_publish_provisional_supplier_costs_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;
