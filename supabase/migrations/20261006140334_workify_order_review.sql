-- Workify order allocation is atomic and tenant-scoped. Line facts stay individual.
create or replace function public.kpi_approve_workify_order_review(p_row_id uuid,p_values jsonb,p_reason text)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $$
declare r public.kpi_import_rows; sibling public.kpi_import_rows; approved public.kpi_import_rows;
 order_number text; result jsonb; affected integer:=1; pending integer:=0;
begin
 if auth.uid() is null then raise exception 'Inloggning krävs'; end if;
 select * into r from public.kpi_import_rows where id=p_row_id;
 if not found or not public.hub_has_permission(r.tenant_id,'kpi.manage') then raise exception 'Behörighet saknas'; end if;
 order_number:=nullif(btrim(r.source_data->>'Ordernummer'),'');
 if r.data_kind<>'revenue' or order_number is null or not (r.source_data ?& array['Artikelnummer','Artikeldatum','Summa','Fakturerad']) then
  return public.kpi_approve_review(p_row_id,p_values,p_reason);
 end if;
 -- Lock batches before rows, in stable order, including other imported copies of the order.
 perform b.id from public.kpi_import_batches b where b.tenant_id=r.tenant_id and b.id in
 (select x.batch_id from public.kpi_import_rows x where x.tenant_id=r.tenant_id and x.data_kind='revenue'
 and btrim(x.source_data->>'Ordernummer')=order_number
 and x.source_data ?& array['Artikelnummer','Artikeldatum','Summa','Fakturerad']) order by b.id for update;
 result:=public.kpi_approve_review(p_row_id,p_values,p_reason);
 select * into approved from public.kpi_import_rows where id=p_row_id;
 for sibling in select x.* from public.kpi_import_rows x
 where x.tenant_id=r.tenant_id and x.data_kind='revenue' and x.id<>r.id
 and btrim(x.source_data->>'Ordernummer')=order_number
 and x.source_data ?& array['Artikelnummer','Artikeldatum','Summa','Fakturerad']
 and coalesce(x.allocation->>'target','')<>'ignored'
 order by x.id for update
 loop
  if not sibling.is_valid and sibling.occurred_on is not null and sibling.amount is not null
   and sibling.amount::text not in ('NaN','Infinity','-Infinity') then
   perform public.kpi_approve_review(sibling.id,to_jsonb(sibling)||jsonb_build_object(
    'project_reference',approved.project_reference,'vehicle_registration',approved.vehicle_registration,
    'employee_number',null,'cost_center',approved.cost_center,'review_target',approved.allocation->>'target'),p_reason);
  else
   update public.kpi_import_rows set project_reference=approved.project_reference,
    vehicle_registration=approved.vehicle_registration,vehicle_object_id=null,employee_number=null,employee_object_id=null,
    cost_center=approved.cost_center,
    allocation=coalesce(sibling.allocation,'{}')||jsonb_build_object('review_reason',btrim(p_reason),'reviewed_by',auth.uid(),
    'reviewed_at',now(),'target',approved.allocation->>'target','manual_override',true,'review_order',order_number)
    where id=sibling.id;
   if not sibling.is_valid then pending:=pending+1; end if;
  end if;
  affected:=affected+1;
 end loop;
 return result||jsonb_build_object('order_number',order_number,'affected',affected,'pending',pending);
end $$;
revoke all on function public.kpi_approve_workify_order_review(uuid,jsonb,text) from public,anon;
grant execute on function public.kpi_approve_workify_order_review(uuid,jsonb,text) to authenticated;
create index if not exists kpi_import_rows_workify_order_review_idx on public.kpi_import_rows
 (tenant_id,(btrim(source_data->>'Ordernummer'))) where data_kind='revenue';
