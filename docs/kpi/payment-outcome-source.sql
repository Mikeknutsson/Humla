-- Source adapter for Dashboard payment forecast; reuses the active Hub snapshot.
create or replace function private.hub_payment_outcome_source_v1(p_tenant_id uuid,p_as_of date)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare generation uuid;synced timestamptz;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_as_of is null or p_as_of<'2000-01-01' or p_as_of>'2100-12-31' then raise exception 'Invalid date';end if;
 select active_generation,synced_at into generation,synced from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report unavailable';end if;
 with revenues as (
  select f.cost_center center,'in'::text kind,f.occurred_on date,f.amount,
   coalesce(f.original->>'Kundnamn','') party,
   private.hub_kpi_workify_date_v1(coalesce(nullif(trim(f.original->>'Fakturadatum'),''),nullif(trim(f.original->>'Fakturerad'),''))) invoice_date,
   private.hub_workify_customer_is_internal_v1(f.original->>'Kundnamn') internal
  from private.hub_kpi_prepared_facts f where f.generation_id=generation and f.tenant_id=p_tenant_id and f.source='Workify' and f.kind='revenue'
   and f.occurred_on between p_as_of-730 and p_as_of+90
 ), costs as (
  -- Read imported NeXT costs before vehicle-result, Piusi and material-schablon filters.
  -- This avoids losing supplier costs or adding vehicle allocations a second time.
  select coalesce(nullif(classification.cost_center,''),nullif(trim(x.cost_center),''),'unclassified') center,'out'::text kind,x.occurred_on date,x.amount,
   coalesce(x.source_data->>'Leverantör','') party,null::date invoice_date,
   coalesce(x.source_data->>'Leverantör','')~*'^elleholms[[:space:]]+maskin' internal
  from public.kpi_import_rows x
  left join lateral (select case when count(distinct nullif(p.cost_center,''))>1 then 'unclassified' else min(nullif(p.cost_center,'')) end cost_center from public.kpi_project_classification_periods p
   where p.tenant_id=p_tenant_id and p.project_reference=x.project_reference and p.valid_from<=x.occurred_on and (p.valid_to is null or p.valid_to>=x.occurred_on)
   ) classification on true
  where x.tenant_id=p_tenant_id and x.data_kind='cost' and x.is_valid and x.amount is not null
   and x.occurred_on between p_as_of-730 and p_as_of+90
 ), daily as (
  select center,kind,date,party,invoice_date,internal,sum(amount) amount from (select * from revenues union all select * from costs) f group by 1,2,3,4,5,6
 )
 select jsonb_build_object('synced_at',synced,'rows',coalesce((select jsonb_agg(jsonb_build_object('center',center,'kind',kind,'date',date,'amount',amount,'party',party,'invoiceDate',invoice_date,'internal',internal) order by date,center,kind,party) from daily),'[]'::jsonb),
 'review_rows',(select count(*) from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind in('revenue','cost') and not r.is_valid),
 'review_amount',(select coalesce(sum(amount),0) from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind in('revenue','cost') and not r.is_valid)) into answer;
 return answer;
end $$;
revoke all on function private.hub_payment_outcome_source_v1(uuid,date) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.hub_payment_outcome_source_v1(uuid,date) to authenticated;
create or replace function public.hub_payment_outcome_source_v1(p_tenant_id uuid,p_as_of date)
returns jsonb language sql security invoker set search_path=pg_catalog as $$ select private.hub_payment_outcome_source_v1(p_tenant_id,p_as_of) $$;
revoke all on function public.hub_payment_outcome_source_v1(uuid,date) from public,anon,authenticated;
grant execute on function public.hub_payment_outcome_source_v1(uuid,date) to authenticated;
