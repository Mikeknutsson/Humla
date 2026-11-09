-- Additive, read-only economic ledger. Existing reports are not switched by this migration.
-- Identity fingerprints never contain derived allocations, driver guesses or export state.
create or replace function private.hub_economic_key_v2(
 p_kind text,p_date date,p_amount numeric,p_quantity numeric,p_currency text,p_raw jsonb,p_row_id text)
returns text language sql immutable set search_path='' as $$
 select case
 when p_kind='revenue' and p_raw ? 'Ordernummer' and p_raw ? 'Artikelnummer'
 then 'workify:'||private.hub_workify_import_key_v1(p_date,p_amount,p_quantity,p_raw,true)
 when p_raw ? 'Konto' and p_raw ? 'Projektnr' and p_raw ? 'Verifikation nr'
 then 'next:'||encode(extensions.digest(jsonb_build_array(p_kind,p_date,trim_scale(p_amount),
 trim_scale(p_quantity),coalesce(nullif(p_currency,''),'SEK'),
 trim(p_raw->>'Konto'),trim(p_raw->>'Projektnr'),trim(p_raw->>'Verifikation nr'),
 trim(p_raw->>'Faktura nr'),trim(p_raw->>'AO/ÄTA'),trim(p_raw->>'Leverantör'),
 trim(p_raw->>'Verifikationstext'),trim(p_raw->>'Notering'))::text,'sha256'),'hex')
 else 'row:'||p_row_id end;
$$;
revoke all on function private.hub_economic_key_v2(text,date,numeric,numeric,text,jsonb,text) from public,anon,authenticated,service_role;

create or replace function private.hub_economic_transactions_v2(p_tenant_id uuid,p_from date,p_to date)
returns table(row_id uuid,canonical_key text,kind text,occurred_on date,amount numeric,currency text,
 source_family text,economic_status text,allocation_status text,vehicle_object_id uuid,
 vehicle text,project text,cost_center text,source_data jsonb,validation_errors jsonb)
language plpgsql stable security definer set search_path='' set jit='off' set work_mem='64MB' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
 raise exception 'KPI access required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period';end if;
 return query with base as materialized (
 select r.*,b.created_at imported_at,
 private.hub_economic_key_v2(r.data_kind,r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,r.id::text) fp,
 case
 when coalesce(r.validation_errors,'[]') ? 'Importen återtagen eller ersatt; ingår inte i beräkningar' then 'excluded_withdrawn'
 when coalesce(r.validation_errors,'[]') ? 'Fakturan finns i NeXT intäktsbokföring; fakturaunderlag räknas inte som ytterligare intäkt' then 'excluded_accounted_elsewhere'
 when r.occurred_on is null or r.amount is null or r.amount::text in ('NaN','Infinity','-Infinity') then 'invalid_economic_data'
 when r.is_valid then 'eligible'
 when r.validation_errors <> '[]'::jsonb and not exists (
 select 1 from jsonb_array_elements_text(coalesce(r.validation_errors,'[]')) e
 where e not in ('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling','Workify-artikeln ska till fordon: registreringsnummer behöver mappas')
 and e not like 'Ej mappad Workify-artikel:%') then 'eligible'
 else 'invalid_economic_data' end eligibility
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant_id and r.data_kind in ('cost','revenue')
 and (r.occurred_on between p_from and p_to or r.occurred_on is null)
 ), occurrences as materialized (
 select b.*,row_number() over(partition by tenant_id,data_kind,fp,batch_id,eligibility order by row_number,id) occurrence
 from base b
 ), ranked as (
 select o.*,row_number() over(partition by tenant_id,data_kind,fp,occurrence,eligibility order by imported_at,batch_id,row_number,id) copy_rank
 from occurrences o
 )
 select r.id,r.fp||':'||r.occurrence,r.data_kind,r.occurred_on,r.amount,r.currency,
 case when left(r.fp,8)='workify:' then 'Workify' when left(r.fp,5)='next:' then 'NEXT' else coalesce(r.source_system,'Other') end,
 case when r.eligibility<>'eligible' then r.eligibility when r.copy_rank>1 then 'excluded_duplicate' else 'included' end,
 case when r.vehicle_object_id is not null then 'verified' else 'unallocated' end,
 r.vehicle_object_id,r.vehicle_registration,r.project_reference,r.cost_center,r.source_data,r.validation_errors from ranked r;
end $$;
revoke all on function private.hub_economic_transactions_v2(uuid,date,date) from public,anon,authenticated,service_role;

create or replace function public.hub_kpi_economic_reconciliation_v2(p_tenant_id uuid,p_from date,p_to date,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='45s' set jit='off' set work_mem='64MB' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page';end if;
 with facts as materialized(select * from private.hub_economic_transactions_v2(p_tenant_id,p_from,p_to)),
 totals as(select kind,currency,economic_status,count(*) rows,coalesce(sum(amount) filter(where amount::text not in ('NaN','Infinity','-Infinity')),0) amount from facts group by 1,2,3),
 items as(select * from facts where economic_status='included' order by occurred_on,row_id limit 100 offset p_page*100)
 select jsonb_build_object('engineVersion','hub-economic-v2','mode','comparison_only','from',p_from,'to',p_to,
 'totals',coalesce((select jsonb_agg(to_jsonb(t) order by kind,currency,economic_status)from totals t),'[]'),
 'includedRows',(select count(*) from facts where economic_status='included'),
 'unallocatedRows',(select count(*)from facts where economic_status='included' and allocation_status='unallocated'),
 'invalidAmountRows',(select count(*)from facts where amount is null or amount::text in ('NaN','Infinity','-Infinity')),
 'page',p_page,'pageSize',100,'items',coalesce((select jsonb_agg(to_jsonb(i))from items i),'[]')) into result;
 return result;
end $$;
revoke all on function public.hub_kpi_economic_reconciliation_v2(uuid,date,date,integer) from public,anon;
grant execute on function public.hub_kpi_economic_reconciliation_v2(uuid,date,date,integer) to authenticated;
notify pgrst,'reload schema';

