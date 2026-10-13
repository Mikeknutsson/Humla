-- NEXT accounting revenue has no Workify order/status and remains unaffected.
create or replace function private.hub_workify_revenue_in_scope_v1(p_source jsonb)
returns boolean language sql immutable set search_path='' as $$
 select case when p_source ? 'Ordernummer' then
  coalesce(p_source->>'Orderstatus' in ('ReadyForInvoicing','Invoiced','Reported'),false)
 else true end;
$$;
revoke all on function private.hub_workify_revenue_in_scope_v1(jsonb) from public,anon;
grant execute on function private.hub_workify_revenue_in_scope_v1(jsonb) to authenticated,service_role;

-- Tenant-scoped read access for SECURITY INVOKER revenue readers. Writes remain private.
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

-- Patch the shared Hub fact producers, not each Dashboard calculation.
do $migration$
declare signature text; definition text; needle text; replacement text;
begin
 foreach signature in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)',
  'private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  needle:='and (x.data_kind<>''revenue'' or x.amount<>0)';
  replacement:='and (x.data_kind<>''revenue'' or (x.amount<>0 and private.hub_workify_row_in_scope_v1(x.id,x.source_data)))';
  if strpos(definition,needle)=0 then raise exception 'Unexpected Hub fact definition: %',signature;end if;
  execute replace(definition,needle,replacement);
 end loop;
 foreach signature in array array['public.hub_kpi_workify_revenue_allocation_v1(uuid,date,date)',
  'public.hub_kpi_workify_revenue_by_cost_center_v1(uuid,date,date,text)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  needle:='x.data_kind=''revenue'' and x.is_valid';
  if strpos(definition,needle)=0 then raise exception 'Unexpected Hub revenue definition: %',signature;end if;
  execute replace(definition,needle,needle||' and private.hub_workify_row_in_scope_v1(x.id,x.source_data)');
 end loop;
end $migration$;
notify pgrst,'reload schema';
