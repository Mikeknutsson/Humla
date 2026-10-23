-- Publish only confirmed supplier category corrections. Amounts, projects,
-- source rows and other report facts are conserved; before/after is retained.
alter table private.hub_kpi_report_state add column if not exists correction_revision integer not null default 0;
create table private.hub_kpi_supplier_category_audit(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,generation_id uuid not null,
 fact_id text not null,rule_id uuid not null,before_category text,after_category text not null,
 amount numeric not null,project text,vehicle text,unit_id uuid,actor uuid not null,
 applied_at timestamptz not null default now(),unique(generation_id,fact_id,rule_id)
);
alter table private.hub_kpi_supplier_category_audit enable row level security;
revoke all on private.hub_kpi_supplier_category_audit from public,anon,authenticated;
create or replace function private.hub_kpi_publish_supplier_categories_v1(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare generation uuid; affected text[]; changes uuid[]; corrected integer; display_corrected integer;amount_before numeric;amount_after numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management access required';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0))then raise exception 'Report worker busy';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant for update;
 if generation is null then raise exception 'Prepared report required';end if;
 with candidates as materialized(
  select f.fact_id,f.category before_category,r.target after_category,r.id rule_id,f.amount,f.project,f.vehicle,f.unit_id
  from public.kpi_import_rows source_row
  join private.hub_kpi_prepared_facts f on f.generation_id=generation and f.tenant_id=p_tenant and f.fact_id=source_row.id::text and f.source='NEXT' and f.kind='cost'
  join lateral(select r.* from public.kpi_dashboard_allocations r where r.tenant_id=p_tenant and r.dimension='category' and r.source='NEXT' and r.kind='cost' and r.reference_type='supplier'
   and upper(trim(r.reference))=upper(trim(source_row.source_data->>'Leverantör')) and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
   order by r.valid_from desc,r.created_at desc limit 1)r on true
  where source_row.tenant_id=p_tenant and source_row.data_kind='cost' and f.category is distinct from r.target
  -- Individual fact rules retain priority over supplier rules.
  and not exists(select 1 from public.kpi_dashboard_allocations x where x.tenant_id=p_tenant and x.dimension='category' and x.reference_type='fact' and x.reference=f.fact_id and x.source='NEXT' and x.kind='cost' and x.valid_from<=f.occurred_on and (x.valid_to is null or x.valid_to>=f.occurred_on))
 ), saved as(
  insert into private.hub_kpi_supplier_category_audit(tenant_id,generation_id,fact_id,rule_id,before_category,after_category,amount,project,vehicle,unit_id,actor)
  select p_tenant,generation,fact_id,rule_id,before_category,after_category,amount,project,vehicle,unit_id,auth.uid() from candidates
  on conflict(generation_id,fact_id,rule_id)do nothing returning id,fact_id,amount
 )select array_agg(id),array_agg(fact_id),sum(amount)into changes,affected,amount_before from saved;
 if affected is null then return jsonb_build_object('corrected',0,'amount_difference',0);end if;
 update private.hub_kpi_prepared_facts f set category=a.after_category
 from private.hub_kpi_supplier_category_audit a where f.generation_id=generation and f.tenant_id=p_tenant and f.fact_id=any(affected) and a.id=any(changes) and a.generation_id=generation and a.fact_id=f.fact_id;
 get diagnostics corrected=row_count;
 update private.hub_kpi_prepared_display_facts f set category=a.after_category
 from private.hub_kpi_supplier_category_audit a where f.generation_id=generation and f.tenant_id=p_tenant and f.fact_id=any(affected) and a.id=any(changes) and a.generation_id=generation and a.fact_id=f.fact_id;
 get diagnostics display_corrected=row_count;
 select sum(amount)into amount_after from private.hub_kpi_prepared_facts where generation_id=generation and tenant_id=p_tenant and fact_id=any(affected);
 if corrected<>cardinality(affected) or display_corrected<>corrected or amount_after is distinct from amount_before then raise exception 'Supplier correction conservation check failed';end if;
 update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=p_tenant;
 return jsonb_build_object('corrected',corrected,'amount',amount_after,'amount_difference',amount_after-amount_before,'generation',generation);
end $$;
revoke all on function private.hub_kpi_publish_supplier_categories_v1(uuid)from public,anon,authenticated;
do $$declare d text;begin
 d:=pg_get_functiondef('private.hub_kpi_report_status_v1(uuid)'::regprocedure);
 if position('correction_revision' in d)=0 then
  d:=replace(d,$old$'requested_at',requested_at,$old$,$new$'correction_revision',correction_revision,'requested_at',requested_at,$new$);
  if position('correction_revision' in d)=0 then raise exception 'Report status patch target changed';end if;
  execute d;
 end if;
end $$;
