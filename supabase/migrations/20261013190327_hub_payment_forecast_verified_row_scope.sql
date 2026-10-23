-- Forecast inputs are frozen to the same generation as KPI and payroll.
-- They remain assumptions from registered activity, not an open invoice ledger.
create or replace function private.hub_payment_outcome_source_v1(p_tenant_id uuid,p_as_of date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;synced timestamptz;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_as_of is null or p_as_of<'2000-01-01' or p_as_of>'2100-12-31' then raise exception 'Invalid date';end if;
 select active_generation,synced_at into generation,synced from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report unavailable';end if;
 with facts as materialized(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant_id and generation_id=generation
 and occurred_on between p_as_of-730 and p_as_of+90),
 revenues as(
 select fact_id id,cost_center center,'in'::text kind,occurred_on date,amount,coalesce(original->>'Kundnamn','') party,
 private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))) invoice_date,
 coalesce(original->>'Kundnamn','')~*'^elleholms[[:space:]]+maskin' internal
 from facts where source='Workify' and kind='revenue'
 ),cost_base as(
 select f.*,case when account='7010' then 'payroll_separate'
 when private.hub_ps_own_tank_source_v1(original,account) then 'own_tank_consumption'
 when coalesce(original->>'Verifikation nr','')~'^(AO[.]|ARB[.]|NEXT[.](AO|ARB))' then 'internal_time_or_allocation'
 else null end exclusion_reason
 from facts f where source='NEXT' and kind='cost'
 ),costs as(
 select fact_id id,cost_center center,'out'::text kind,occurred_on date,
 coalesce((original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount) amount,
 coalesce(nullif(trim(original->>'Leverantör'),''),'') party,null::date invoice_date,
 coalesce(original->>'Leverantör','')~*'^elleholms[[:space:]]+maskin' internal
 from cost_base where exclusion_reason is null
 ),daily as(
 select center,kind,date,party,invoice_date,internal,sum(amount)amount
 from(select * from revenues union all select * from costs)f group by 1,2,3,4,5,6
 ), exclusions as(
 select exclusion_reason reason,count(*)rows,round(sum(coalesce((original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount)),2)amount from cost_base where exclusion_reason is not null group by 1
 )
 select jsonb_build_object('synced_at',synced,'generation',generation,
 'rows',coalesce((select jsonb_agg(jsonb_build_object('center',center,'kind',kind,'date',date,'amount',amount,'party',party,'invoiceDate',invoice_date,'internal',internal)order by date,center,kind,party)from daily),'[]'::jsonb),
 'review_rows',0,'review_amount',0,
 'controls',jsonb_build_object('scope','published_generation','from',p_as_of-730,'to',p_as_of+90,
 'supplierRows',(select count(*)from costs),'supplierAmount',(select coalesce(sum(amount),0)from costs),
 'excludedNonPayments',coalesce((select jsonb_agg(to_jsonb(e)order by reason)from exclusions e),'[]'::jsonb),
 'originalsPreserved',true,'noLiveImportAmounts',true))into answer;
 return answer;
end $$;
revoke all on function private.hub_payment_outcome_source_v1(uuid,date) from public,anon;
grant execute on function private.hub_payment_outcome_source_v1(uuid,date) to authenticated,service_role;

-- Keep the existing unit-detail response shape, with one authoritative ledger.
create function private.hub_kpi_verified_unit_detail_v1(p_tenant_id uuid,p_unit_id uuid,p_from date,p_to date,p_grain text,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Behörighet saknas';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 or p_page is null or p_page<0 or p_page>100000 or p_grain is null or p_grain not in('year','month','week','day') then raise exception 'Ogiltig period';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report unavailable';end if;
 if not exists(select 1 from private.hub_kpi_prepared_kpi_units where generation_id=generation and tenant_id=p_tenant_id and id=p_unit_id) then raise exception 'Enheten saknas';end if;
 with selected as materialized(
 select f.*,
 case when kind='revenue' then amount else 0 end revenue,
 case when kind='cost' and category<>'fuel' then amount else 0 end cost,
 case when kind='cost' and category='fuel' then amount else 0 end fuel,
 case when kind='revenue' then amount else -amount end result,
 case p_grain when 'year' then make_date(extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,9,1)
 when 'month' then date_trunc('month',occurred_on)::date when 'week' then date_trunc('week',occurred_on)::date else occurred_on end period_start
 from private.hub_kpi_prepared_facts f where generation_id=generation and tenant_id=p_tenant_id and unit_id=p_unit_id and occurred_on between p_from and p_to
 ),periods as(
 select period_start,greatest(period_start,p_from)range_start,
 least(p_to,(case p_grain when 'year' then period_start+interval'1 year' when 'month' then period_start+interval'1 month' when 'week' then period_start+interval'1 week' else period_start+interval'1 day' end)::date-1)range_end,
 count(*)row_count,sum(revenue)revenue,sum(cost)cost,sum(fuel)fuel,sum(result)result from selected group by 1
 ),items as(
 select fact_id id,occurred_on,description,project project_reference,vehicle vehicle_registration,
 original->>'employee_id' employee_number,account,
 coalesce((original#>>'{_humla_distribution,original_amount}')::numeric,(original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount)amount,
 revenue,cost,fuel,result,file_name,row_number,original source_data,original->'_humla_assignment' allocation
 from selected order by occurred_on,fact_id limit 50 offset p_page*50
 )
 select jsonb_build_object('scope','published_generation','generation',generation,
 'periods',coalesce((select jsonb_agg(to_jsonb(p)order by period_start)from periods p),'[]'::jsonb),
 'total_rows',(select count(*)from selected),'held_rows',null,
 'totals',(select jsonb_build_object('revenue',coalesce(sum(revenue),0),'cost',coalesce(sum(cost),0),'fuel',coalesce(sum(fuel),0),'result',coalesce(sum(result),0))from selected),
 'rows',coalesce((select jsonb_agg(to_jsonb(i))from items i),'[]'::jsonb))into answer;
 return answer;
end $$;
revoke all on function private.hub_kpi_verified_unit_detail_v1(uuid,uuid,date,date,text,integer) from public,anon;
grant execute on function private.hub_kpi_verified_unit_detail_v1(uuid,uuid,date,date,text,integer) to authenticated,service_role;
create or replace function public.kpi_unit_detail(p_tenant_id uuid,p_unit_id uuid,p_from date,p_to date,p_grain text default 'month',p_page integer default 0)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_kpi_verified_unit_detail_v1(p_tenant_id,p_unit_id,p_from,p_to,p_grain,p_page);
$$;
revoke all on function public.kpi_unit_detail(uuid,uuid,date,date,text,integer) from public,anon;
grant execute on function public.kpi_unit_detail(uuid,uuid,date,date,text,integer) to authenticated,service_role;

-- Source adapter folds material/transport components back to one source row.
-- Quantity is counted once; the sum of component revenues is preserved.
create function private.hub_kpi_verified_material_sales_v1(p_tenant uuid)
returns table(tenant_id uuid,id uuid,occurred_on date,amount numeric,source_data jsonb)
language plpgsql stable security definer set search_path='' as $$
declare generation uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'Behörighet saknas';end if;
 select active_generation into generation from private.hub_kpi_report_state where private.hub_kpi_report_state.tenant_id=p_tenant;
 if generation is null then return;end if;
 return query select p_tenant,split_part(f.fact_id,':',1)::uuid,min(f.occurred_on),sum(f.amount),(array_agg(f.original order by f.fact_id))[1]
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=generation and f.source='Workify' and f.kind='revenue'
 and nullif(f.original->>'Artikelnummer','') is not null and split_part(f.fact_id,':',1)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 group by split_part(f.fact_id,':',1);
end $$;
revoke all on function private.hub_kpi_verified_material_sales_v1(uuid) from public,anon;
grant execute on function private.hub_kpi_verified_material_sales_v1(uuid) to authenticated,service_role;
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_viewdef('public.hub_workify_material_sales_v1'::regclass,true);
 needle:='FROM kpi_import_rows r';
 if strpos(definition,needle)=0 then raise exception 'Unexpected material source view';end if;
 definition:=replace(definition,needle,'FROM (select tenant_id tenant_key,user_id,status from public.hub_tenant_members) member CROSS JOIN LATERAL private.hub_kpi_verified_material_sales_v1(member.tenant_key) r');
 needle:='WHERE data_kind = ''revenue''::text AND is_valid IS NOT FALSE AND NULLIF(source_data ->> ''Artikelnummer''::text, ''''::text) IS NOT NULL';
 if strpos(definition,needle)=0 then raise exception 'Unexpected material source predicate';end if;
 definition:=replace(definition,needle,'WHERE member.user_id=auth.uid() AND member.status=''active'' AND public.hub_has_permission(member.tenant_key,''kpi.read'')');
 execute 'create or replace view public.hub_workify_material_sales_v1 with(security_invoker=true) as '||definition;
end $migration$;
