-- Reuse dated, confirmed Hub knowledge when new NEXT files arrive.
-- This releases allocation-only holds, never malformed financial evidence.
create or replace function public.hub_kpi_resolve_import_allocations_v1(p_tenant_id uuid,p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare released integer; valid integer; invalid integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs' using errcode='42501';
 end if;
 perform 1 from public.kpi_import_batches where id=p_batch_id and tenant_id=p_tenant_id and data_kind='cost' for update;
 if not found then raise exception 'Kostnadsimporten finns inte i arbetsytan';end if;
 update public.kpi_import_rows r set is_valid=true,validation_errors='[]'::jsonb,
  allocation=coalesce(r.allocation,'{}'::jsonb)||jsonb_build_object('allocation_status','classified','resolution','saved_hub_rules','reviewed_by',auth.uid(),'reviewed_at',now())
 where r.tenant_id=p_tenant_id and r.batch_id=p_batch_id and r.data_kind='cost' and not r.is_valid
  and r.amount is not null and r.occurred_on is not null
  and r.validation_errors<@'["Kostnadsfördelning behöver granskas","Fordonsbeteckning saknar verifierad regnummerkoppling"]'::jsonb
  and (
   exists(select 1 from public.kpi_project_classification_periods p
    where p.tenant_id=r.tenant_id and p.project_reference=r.project_reference
     and p.valid_from<=r.occurred_on and (p.valid_to is null or p.valid_to>=r.occurred_on)
     and nullif(trim(p.cost_center),'') is not null and p.cost_center<>'unclassified')
   or exists(select 1 from public.kpi_dashboard_allocations a
    where a.tenant_id=r.tenant_id and a.source='NEXT' and a.kind='cost'
     and a.dimension in ('cost_center','unit','vehicle','project','group','shared_cost')
     and a.valid_from<=r.occurred_on and (a.valid_to is null or a.valid_to>=r.occurred_on)
     and case a.reference_type when 'fact' then a.reference=r.id::text
      when 'project' then a.reference=r.project_reference
      when 'vehicle' then a.reference=r.vehicle_registration
      when 'account' then a.reference=r.account else false end)
  );
 get diagnostics released=row_count;
 select count(*) filter(where is_valid),count(*) filter(where not is_valid) into valid,invalid
  from public.kpi_import_rows where tenant_id=p_tenant_id and batch_id=p_batch_id;
 update public.kpi_import_batches set valid_row_count=valid,invalid_row_count=invalid,
  status=case when invalid=0 then 'completed' else 'needs_review' end,completed_at=now(),
  error_summary=(select coalesce(jsonb_agg(jsonb_build_object('row',row_number,'errors',validation_errors)),'[]'::jsonb)
   from (select row_number,validation_errors from public.kpi_import_rows where tenant_id=p_tenant_id and batch_id=p_batch_id and not is_valid order by row_number limit 50) x)
 where tenant_id=p_tenant_id and id=p_batch_id;
 return jsonb_build_object('released',released,'validRows',valid,'invalidRows',invalid,'status',case when invalid=0 then 'completed' else 'needs_review' end);
end $fn$;
revoke all on function public.hub_kpi_resolve_import_allocations_v1(uuid,uuid) from public,anon;
grant execute on function public.hub_kpi_resolve_import_allocations_v1(uuid,uuid) to authenticated;
