
create table private.hub_payment_forecast_exclusions(
 tenant_id uuid not null, row_id uuid not null references public.kpi_import_rows(id) on delete cascade,
 excluded boolean not null default true, note text not null default '', updated_by uuid not null, updated_at timestamptz not null default now(),
 primary key(tenant_id,row_id));
alter table private.hub_payment_forecast_exclusions enable row level security;
revoke all on private.hub_payment_forecast_exclusions from public,anon,authenticated;
create table private.hub_payment_forecast_exclusion_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,row_id uuid not null,excluded boolean not null,note text not null,actor uuid not null,created_at timestamptz not null default now());
alter table private.hub_payment_forecast_exclusion_events enable row level security;
revoke all on private.hub_payment_forecast_exclusion_events from public,anon,authenticated;
create or replace function private.hub_payment_forecast_set_exclusion_v1(p_tenant_id uuid,p_rows uuid[],p_excluded boolean,p_note text default '')
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare n integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_excluded is null or coalesce(cardinality(p_rows),0) not between 1 and 200 or length(coalesce(p_note,''))>500 then raise exception 'Invalid selection';end if;
 if exists(select 1 from unnest(p_rows) id where not exists(select 1 from public.kpi_import_rows r where r.id=id and r.tenant_id=p_tenant_id and r.data_kind='cost')) then raise exception 'Cost row not found';end if;
 insert into private.hub_payment_forecast_exclusions(tenant_id,row_id,excluded,note,updated_by)
 select p_tenant_id,id,p_excluded,coalesce(p_note,''),auth.uid() from (select distinct unnest(p_rows) id)s
 on conflict(tenant_id,row_id) do update set excluded=excluded.excluded,note=excluded.note,updated_by=excluded.updated_by,updated_at=now();
 get diagnostics n=row_count;
 insert into private.hub_payment_forecast_exclusion_events(tenant_id,row_id,excluded,note,actor)
 select p_tenant_id,id,p_excluded,coalesce(p_note,''),auth.uid() from (select distinct unnest(p_rows) id)s;
 return jsonb_build_object('updated',n);
end $fn$;
revoke all on function private.hub_payment_forecast_set_exclusion_v1(uuid,uuid[],boolean,text) from public,anon,authenticated;
grant execute on function private.hub_payment_forecast_set_exclusion_v1(uuid,uuid[],boolean,text) to authenticated;
create or replace function public.hub_payment_forecast_set_exclusion_v1(p_tenant_id uuid,p_rows uuid[],p_excluded boolean,p_note text default '')
returns jsonb language sql set search_path='pg_catalog' as $fn$select private.hub_payment_forecast_set_exclusion_v1(p_tenant_id,p_rows,p_excluded,p_note)$fn$;
revoke all on function public.hub_payment_forecast_set_exclusion_v1(uuid,uuid[],boolean,text) from public,anon;
grant execute on function public.hub_payment_forecast_set_exclusion_v1(uuid,uuid[],boolean,text) to authenticated;

CREATE OR REPLACE FUNCTION private.hub_payment_outcome_source_v1(p_tenant_id uuid, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare generation uuid;synced timestamptz;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_as_of is null or p_as_of<'2000-01-01' or p_as_of>'2100-12-31' then raise exception 'Invalid date';end if;
 select active_generation,synced_at into generation,synced from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select coalesce(max(coalesce(completed_at,created_at)),synced) into synced
 from public.kpi_import_batches where tenant_id=p_tenant_id and data_kind in ('revenue','cost') and completed_at is not null;
 with facts as materialized(
 select * from private.hub_kpi_filtered_classified_facts_v1(p_tenant_id,p_as_of-730,p_as_of+90,'{}'::jsonb)
),
 revenues as(
 select fact_id id,cost_center center,'in'::text kind,occurred_on date,amount,coalesce(original->>'Kundnamn','') party,
 private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))) invoice_date,
 (coalesce(original->>'Kundnamn','')~*'^elleholms[[:space:]]+maskin' and regexp_replace(lower(coalesce(original->>'Kundnamn','')),'[^a-zåäö0-9]+','','g')<>'elleholmsmaskinstena') internal,false one_off,null::text row_id,coalesce(original->>'Ordernummer','') reference,description,account,project
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
 coalesce(original->>'Leverantör','')~*'^elleholms[[:space:]]+maskin' internal,
 exists(select 1 from private.hub_payment_forecast_exclusions e where e.tenant_id=p_tenant_id and e.row_id::text=split_part(fact_id,':',1) and e.excluded) one_off,
 split_part(fact_id,':',1) row_id,coalesce(original->>'Verifikationstext',description,'') reference,description,account,project
 from cost_base where exclusion_reason is null
 ),daily as(
 select * from revenues union all select * from costs
 ), exclusions as(
 select exclusion_reason reason,count(*)rows,round(sum(coalesce((original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount)),2)amount from cost_base where exclusion_reason is not null group by 1
 )
 select jsonb_build_object('synced_at',synced,'generation',generation,
 'rows',coalesce((select jsonb_agg(jsonb_build_object('center',center,'kind',kind,'date',date,'amount',amount,'party',party,'invoiceDate',invoice_date,'internal',internal,'oneOff',one_off,'id',id,'rowId',row_id,'reference',reference,'description',description,'account',account,'project',project)order by date,center,kind,party,id)from daily),'[]'::jsonb),
 'review_rows',0,'review_amount',0,
 'controls',jsonb_build_object('scope','live_approved_imports','from',p_as_of-730,'to',p_as_of+90,
 'supplierRows',(select count(*)from costs),'supplierAmount',(select coalesce(sum(amount),0)from costs),
 'excludedNonPayments',coalesce((select jsonb_agg(to_jsonb(e)order by reason)from exclusions e),'[]'::jsonb),
 'originalsPreserved',true,'noLiveImportAmounts',false,'latestUploadedSource',true))into answer;
 return answer;
end $function$
;
NOTIFY pgrst,'reload schema';