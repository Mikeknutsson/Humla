CREATE OR REPLACE FUNCTION private.hub_payment_outcome_source_v1(p_tenant_id uuid, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare generation uuid;synced timestamptz;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_as_of is null or p_as_of<'2000-01-01' or p_as_of>'2100-12-31' then raise exception 'Invalid date';end if;
 select active_generation,synced_at into generation,synced from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select greatest(coalesce(max(coalesce(completed_at,created_at)),synced),(select max(uploaded_at) from private.hub_stena_files_v1 where tenant_id=p_tenant_id and complete)) into synced
 from public.kpi_import_batches where tenant_id=p_tenant_id and data_kind in ('revenue','cost') and completed_at is not null;
 with recursive facts as materialized(
 select * from private.hub_kpi_filtered_classified_facts_v1(p_tenant_id,p_as_of-730,p_as_of+90,'{}'::jsonb)
),
 stena_current as materialized(
 select distinct on(r.revenue_object_id) r.revenue_object_id,r.booking,r.occurred_on,
 coalesce(o.amount,r.amount) amount,f.source_kind,f.uploaded_at
 from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
 left join private.hub_stena_amount_overrides_v1 o on o.tenant_id=r.tenant_id and o.revenue_object_id=r.revenue_object_id
 where r.tenant_id=p_tenant_id and f.complete
 and exists(select 1 from private.hub_stena_rules_v1 cfg where cfg.tenant_id=p_tenant_id and cfg.enabled)
 order by r.revenue_object_id,(f.source_kind='settled')desc,f.uploaded_at desc,f.file_hash
),stena_edges as materialized(
 select f.fact_id,s.revenue_object_id from facts f
 cross join lateral regexp_matches(coalesce(f.original->>'Littranummer','')||' '||coalesce(f.original->>'ArtikelKommentar',''),'(?<![0-9])[0-9]{8}(?![0-9])','g') k
 join stena_current s on s.booking=k[1]
 where f.source='Workify' and f.kind='revenue'
 and f.original->>'Kundnamn' in('Elleholms Maskin (STENA)','Stena Recycling AB')
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
),stena_blocked(id) as(
 select revenue_object_id from stena_current where amount is null
 union
 select e2.revenue_object_id from stena_blocked b join stena_edges e1 on e1.revenue_object_id=b.id join stena_edges e2 on e2.fact_id=e1.fact_id
),stena_replaced as(
 select distinct e.fact_id from stena_edges e where not exists(
 select 1 from stena_edges x join stena_blocked b on b.id=x.revenue_object_id where x.fact_id=e.fact_id)
),stena_portal as materialized(
 select s.* from stena_current s where s.amount is not null and s.occurred_on between p_as_of-730 and p_as_of+90
 and not exists(select 1 from stena_blocked b where b.id=s.revenue_object_id)
),
revenues as(
 select fact_id id,cost_center center,'in'::text kind,occurred_on date,amount,coalesce(original->>'Kundnamn','') party,
 private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))) invoice_date,
 (coalesce(original->>'Kundnamn','')~*'^elleholms[[:space:]]+maskin' and regexp_replace(lower(coalesce(original->>'Kundnamn','')),'[^a-zåäö0-9]+','','g')<>'elleholmsmaskinstena') internal,false one_off,null::text row_id,coalesce(original->>'Ordernummer','') reference,description,account,project
 from facts f where source='Workify' and kind='revenue' and not exists(select 1 from stena_replaced x where x.fact_id=f.fact_id)
 union all
 select s.revenue_object_id::text,'30','in',s.occurred_on,s.amount,'Stena Recycling AB',
 null::date,false,false,null::text,s.booking,'Stena transport',null::text,null::text
 from stena_portal s
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
 'rows',coalesce((select jsonb_agg(jsonb_build_object('center',daily.center,'kind',daily.kind,'date',daily.date,'amount',daily.amount,'party',party,'invoiceDate',invoice_date,'internal',internal,'oneOff',one_off,'id',id,'rowId',row_id,'reference',reference,'description',description,'account',account,'project',project,'source',case when sp.revenue_object_id is not null then 'Stena portal' when kind='in' then 'Workify' else 'NEXT' end,'amountStatus',sp.source_kind)order by daily.date,daily.center,daily.kind,party,id)from daily left join stena_portal sp on sp.revenue_object_id::text=daily.id),'[]'::jsonb),
 'review_rows',0,'review_amount',0,
 'controls',jsonb_build_object('scope','live_approved_imports','from',p_as_of-730,'to',p_as_of+90,
 'supplierRows',(select count(*)from costs),'supplierAmount',(select coalesce(sum(amount),0)from costs),
 'excludedNonPayments',coalesce((select jsonb_agg(to_jsonb(e)order by reason)from exclusions e),'[]'::jsonb),
 'stena',jsonb_build_object('rows',(select count(*)from stena_portal),
 'settledRows',(select count(*)from stena_portal where source_kind='settled'),
 'settledAmount',(select coalesce(sum(amount),0)from stena_portal where source_kind='settled'),
 'historyRows',(select count(*)from stena_portal where source_kind='history'),
 'historyAmount',(select coalesce(sum(amount),0)from stena_portal where source_kind='history'),
 'unresolvedRows',(select count(*)from stena_current s where s.occurred_on between p_as_of-730 and p_as_of+90 and exists(select 1 from stena_blocked b where b.id=s.revenue_object_id)),
 'replacedWorkifyRows',(select count(*)from stena_replaced)),
 'originalsPreserved',true,'noLiveImportAmounts',false,'latestUploadedSource',true))into answer;
 return answer;
end $function$

