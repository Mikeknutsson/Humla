-- Approved Workify scope. Original import rows remain immutable.
create or replace function private.hub_workify_revenue_in_scope_v1(p_source jsonb)
returns boolean language sql immutable set search_path='' as $$
 select case when p_source ? 'Ordernummer' then coalesce(p_source->>'Orderstatus' in ('Reported','ReadyForInvoicing','Invoiced'),false) else true end;
$$;
revoke all on function private.hub_workify_revenue_in_scope_v1(jsonb) from public,anon;
grant execute on function private.hub_workify_revenue_in_scope_v1(jsonb) to authenticated,service_role;
grant execute on function private.hub_workify_financially_eligible_v1(boolean,jsonb) to authenticated;
grant select on private.hub_workify_reconciliation_audit,private.hub_workify_row_observations to authenticated;
create policy workify_reconciliation_tenant_read on private.hub_workify_reconciliation_audit
 for select to authenticated using(auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy workify_observations_tenant_read on private.hub_workify_row_observations
 for select to authenticated using(auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create or replace function private.hub_workify_row_in_scope_v1(p_row uuid,p_source jsonb)
returns boolean language sql stable set search_path='' as $$
 select not exists(select 1 from private.hub_workify_reconciliation_audit where row_id=p_row and action='duplicate')
 and private.hub_workify_revenue_in_scope_v1(private.hub_workify_effective_source_v1(p_row,p_source));
$$;
revoke all on function private.hub_workify_row_in_scope_v1(uuid,jsonb) from public,anon;
grant execute on function private.hub_workify_row_in_scope_v1(uuid,jsonb) to authenticated,service_role;
create or replace function private.hub_kpi_import_row_in_scope_v2(p_row uuid,p_kind text,p_date date,p_amount numeric,p_valid boolean,p_errors jsonb,p_source jsonb)
returns boolean language sql stable set search_path='' as $$
 select case when p_kind='revenue' and p_source ? 'Ordernummer' then
  p_date is not null and p_amount is not null and p_amount<>0 and p_amount::text not in ('NaN','Infinity','-Infinity')
  and nullif(trim(p_source->>'Ordernummer'),'') is not null
  and private.hub_workify_financially_eligible_v1(p_valid,p_errors)
  and private.hub_workify_row_in_scope_v1(p_row,p_source)
 else coalesce(p_valid,false) and (p_kind<>'revenue' or p_amount<>0) end;
$$;
revoke all on function private.hub_kpi_import_row_in_scope_v2(uuid,text,date,numeric,boolean,jsonb,jsonb) from public,anon;
grant execute on function private.hub_kpi_import_row_in_scope_v2(uuid,text,date,numeric,boolean,jsonb,jsonb) to authenticated,service_role;
create or replace function private.hub_workify_reporting_source_v1(p_row uuid,p_source jsonb,p_valid boolean)
returns jsonb language sql stable set search_path='' as $$
 select case when p_source ? 'Ordernummer' then private.hub_workify_effective_source_v1(p_row,p_source)
  ||jsonb_build_object('_humla_allocation_review',not coalesce(p_valid,false),'_humla_workify_source_row_id',p_row)
 else p_source end;
$$;
revoke all on function private.hub_workify_reporting_source_v1(uuid,jsonb,boolean) from public,anon;
grant execute on function private.hub_workify_reporting_source_v1(uuid,jsonb,boolean) to authenticated,service_role;

-- Keep every consumer on the same Hub predicate, including invoker readers.
do $migration$
declare signature text; definition text; needle text; replacement text;
begin
 foreach signature in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)',
  'private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  needle:='(x.data_kind<>''revenue'' or x.amount<>0) and x.is_valid';
  replacement:='private.hub_kpi_import_row_in_scope_v2(x.id,x.data_kind,x.occurred_on,x.amount,x.is_valid,x.validation_errors,x.source_data)';
  if strpos(definition,needle)=0 then raise exception 'Unexpected Hub fact predicate: %',signature;end if;
  definition:=replace(definition,needle,replacement);
  needle:='else x.source_data end || case';
  if strpos(definition,needle)=0 then raise exception 'Unexpected Hub source projection: %',signature;end if;
  definition:=replace(definition,needle,'else private.hub_workify_reporting_source_v1(x.id,x.source_data,x.is_valid) end || case');
  -- Uncertain allocation is explicit, while its amount remains in total revenue.
  foreach needle in array array['else f.vrn end','else f.uid end','else f.uname end','else f.grp end'] loop
   if strpos(definition,needle)=0 then raise exception 'Unexpected Hub allocation projection: % / %',signature,needle;end if;
   replacement:=case when needle='else f.grp end'
    then 'else case when f.raw->>''_humla_allocation_review''=''true'' then ''Ej klassificerat'' else f.grp end end'
    else replace(needle,'else f.','else case when f.raw->>''_humla_allocation_review''=''true'' then null else f.')||' end' end;
   definition:=replace(definition,needle,replacement);
  end loop;
  execute definition;
 end loop;
 foreach signature in array array['public.hub_kpi_workify_revenue_allocation_v1(uuid,date,date)',
  'public.hub_kpi_workify_revenue_by_cost_center_v1(uuid,date,date,text)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  needle:='x.data_kind=''revenue'' and x.is_valid';
  if strpos(definition,needle)=0 then raise exception 'Unexpected Hub revenue predicate: %',signature;end if;
  definition:=replace(definition,needle,'x.data_kind=''revenue'' and private.hub_kpi_import_row_in_scope_v2(x.id,x.data_kind,x.occurred_on,x.amount,x.is_valid,x.validation_errors,x.source_data)');
  if signature like '%by_cost_center%' then
   needle:='select x.amount,x.occurred_on,r.cost_center,r.project_reference,r.revenue_category,r.target_type';
   if strpos(definition,needle)=0 then raise exception 'Unexpected cost center projection';end if;
   definition:=replace(definition,needle,'select x.amount,x.occurred_on,coalesce(r.cost_center,nullif(x.cost_center,'''')) cost_center,r.project_reference,coalesce(r.revenue_category,''unclassified'') revenue_category,coalesce(r.target_type,''unclassified'') target_type');
   definition:=replace(definition,'join lateral (','left join lateral (');
   definition:=replace(definition,'r.cost_center=p_cost_center','coalesce(r.cost_center,nullif(x.cost_center,''''))=p_cost_center');
  else
   needle:='case when ov.order_name is not null then case when upper';
   if strpos(definition,needle)=0 then raise exception 'Unexpected vehicle projection';end if;
   definition:=replace(definition,needle,'case when not x.is_valid then '''' when ov.order_name is not null then case when upper');
   definition:=replace(definition,'case when ov.order_name is not null then ''vehicle'' else','case when not x.is_valid then ''unclassified'' when ov.order_name is not null then ''vehicle'' else');
  end if;
  execute definition;
 end loop;
end $migration$;
notify pgrst,'reload schema';
