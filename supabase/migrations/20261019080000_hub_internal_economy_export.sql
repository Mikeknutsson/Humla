-- Accounting report: material at self cost; other internal services at 90%.
create function private.hub_internal_economy_rows_v1(p_rows jsonb)
returns jsonb language sql stable set search_path='' as $$
 with expanded as(
  select r,c.category,
   coalesce((r->>'bundle')::boolean,false) bundle,
   case when c.category='material'then r->'purchase'else '{}'::jsonb end purchase
  from jsonb_array_elements(p_rows)r cross join lateral(
   select v.category from(values('material'),('transport'))v(category)where(r->>'bundle')::boolean
   union all select r->>'category'where not coalesce((r->>'bundle')::boolean,false)
  )c
 ), priced as(
  select *,case when category='material'then
   case when purchase->>'amount'is not null and(purchase->>'amount')not in('NaN','Infinity','-Infinity')
    and((purchase->>'amount')::numeric=0 or sign((purchase->>'amount')::numeric)=sign((r->>'amount')::numeric))
    then round((purchase->>'amount')::numeric,2)end
   when(r->>'bundle_unresolved')::boolean then null
   when bundle then round((r->>'bundle_transport')::numeric*0.9,2)
   when category in('transport','tipp_deponi')then round((r->>'amount')::numeric*0.9,2)end transfer_amount,
   case when bundle and category='transport'then(r->>'bundle_transport')::numeric
    when bundle and category='material'then(purchase->>'amount')::numeric else(r->>'amount')::numeric end debit_amount,
   coalesce((purchase->>'quantity')::numeric,(r->>'quantity')::numeric)quantity
  from expanded
 ), rows as(
  select r||jsonb_build_object('category',category,'component',case when bundle then category else 'original'end,
   'description',case when bundle then(r->>'description')||case when category='material'then' - materialdel'else' - transportdel'end else r->>'description'end,
   'original_amount',r->'amount','debit_amount',debit_amount,'amount',transfer_amount,'quantity',quantity,
   'discount_rate',case when category in('transport','tipp_deponi')then 0.10 else 0 end,
   'discount_amount',case when category in('transport','tipp_deponi')then round(debit_amount,2)-transfer_amount else 0 end,
   'rate',case when category='material'then(purchase->>'rate')::numeric else round(transfer_amount/nullif(quantity,0),4)end,
   'price_status',case when category='material'then coalesce(purchase->>'status','missing_price')when(r->>'bundle_unresolved')::boolean then'bundle_unresolved'else'internal_price'end,
   'price_basis',case when category='material'then purchase->>'price_source'when bundle then'Publicerad Hub-fördelning: transportdelen minus 10 %'else'Debiteringsbelopp från Workify minus 10 %'end,
   'estimated',category='material'and purchase->>'status'is distinct from'receipt_price_list',
   'preliminary',r->>'report_basis'='preliminary'or(category='material'and purchase->>'status'is distinct from'receipt_price_list')or transfer_amount is null,
   'from_center',r->>'receiver_center','to_center',r->>'source_center')row
  from priced
 )select coalesce(jsonb_agg(row order by row->>'occurred_on',row->>'order',row->>'source_key',row->>'component'),'[]')from rows;
$$;
revoke all on function private.hub_internal_economy_rows_v1(jsonb)from public,anon,authenticated;

create function public.hub_kpi_internal_economy_export_v1(p_tenant_id uuid,p_from date,p_to date,p_months integer[]default null)
returns jsonb language plpgsql stable security definer set search_path=''set jit='off'set statement_timeout='45s' as $$
declare raw jsonb;summary jsonb;source_rows jsonb;prices jsonb;rows jsonb;result jsonb;generation uuid;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 raw:=public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months);
 summary:=private.hub_internal_center_summary_engine_v2(raw->'rows');
 select coalesce(jsonb_agg(r),'[]')into source_rows from jsonb_array_elements(summary->'transfers')t cross join lateral jsonb_array_elements(t->'rows')r;
 prices:=public.hub_kpi_internal_purchase_costs_v1(p_tenant_id,array(select(r->>'row_id')::uuid from jsonb_array_elements(source_rows)r where r->>'category'='material'));
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 with source as materialized(
  select r,x.source_data,
   case when coalesce(nullif(x.source_data->>'Kvantitet',''),'')~'^-?[0-9 ]+([.,][0-9]+)?$'
    then replace(replace(x.source_data->>'Kvantitet',' ',''),',','.')::numeric else x.quantity end quantity
  from jsonb_array_elements(source_rows)r join public.kpi_import_rows x on x.id=(r->>'row_id')::uuid and x.tenant_id=p_tenant_id
 ), published as materialized(
  select coalesce(a.canonical_row_id::text,f.original->>'_humla_workify_source_row_id',split_part(f.fact_id,':',1))source_row,
   f.category,f.amount,f.original->'_humla_material_separation'split
  from private.hub_kpi_prepared_facts f
  left join private.hub_workify_reconciliation_audit a on a.tenant_id=f.tenant_id and a.row_id=coalesce(nullif(f.original->>'_humla_workify_source_row_id',''),split_part(f.fact_id,':',1))::uuid and a.action='duplicate'
  where f.tenant_id=p_tenant_id and f.generation_id=generation and f.source='Workify'and f.kind='revenue'
   and f.occurred_on between p_from and p_to and f.original#>>'{_humla_material_separation,method}'='purchase_price_transport_remainder'
 ), bundles as(
  select source_row,sum(amount)filter(where category='transport')transport,
   (array_agg(split->'purchase')filter(where category='material'))[1]purchase,
   count(*)filter(where category='material')material_rows,count(*)filter(where category='transport')transport_rows
  from published group by source_row
 )select coalesce(jsonb_agg(s.r||jsonb_build_object(
  'quantity',s.quantity,'customer',s.source_data->>'Kundnamn','title',s.source_data->>'Rubrik',
  'order_status',s.source_data->>'Orderstatus','object_number',s.source_data->>'Objektnummer','driver',s.source_data->>'Förare',
  'description',coalesce(nullif(s.source_data->>'Artikelnamn',''),s.r->>'description'),
  'bundle',coalesce(b.material_rows=1 and b.transport_rows=1,false),'bundle_transport',b.transport,
  'bundle_unresolved',coalesce(s.source_data->>'Artikelnamn','')ilike'%inkl%transport%'and b.source_row is null,
  'purchase',coalesce(b.purchase,prices->(s.r->>'row_id'),'{}'::jsonb))),'[]')into source_rows
 from source s left join bundles b on b.source_row=s.r->>'row_id';
 rows:=private.hub_internal_economy_rows_v1(source_rows);
 with items as materialized(select r,(r->>'amount')::numeric amount from jsonb_array_elements(rows)r),
 totals as(select count(*)rows,count(*)filter(where amount is null)missing_rows,
  count(*)filter(where(r->>'estimated')::boolean)estimated_rows,
  count(*)filter(where(r->>'preliminary')::boolean)preliminary_rows,
  coalesce(sum(amount),0)priced_amount,coalesce(sum((r->>'debit_amount')::numeric),0)debit_amount,
  coalesce(sum((r->>'discount_amount')::numeric),0)discount_amount,
  case when count(*)filter(where amount is null)=0 then coalesce(sum(amount),0)end total from items),
 centers as(select r->>'to_center'center,
  case when count(*)filter(where amount is null)=0 then coalesce(sum(amount),0)end total,
  coalesce(sum(amount),0)priced_amount,coalesce(sum((r->>'debit_amount')::numeric),0)debit_amount,
  coalesce(sum((r->>'discount_amount')::numeric),0)discount_amount,count(*)rows,count(*)filter(where amount is null)missing_rows,
  coalesce(sum(amount)filter(where r->>'category'='material'),0)material,
  coalesce(sum(amount)filter(where r->>'category'='transport'),0)transport,
  coalesce(sum(amount)filter(where r->>'category'='tipp_deponi'),0)tipp_deponi
  from items group by 1),
 projects as(select r->>'to_center'center,r->>'project'project,max(r->>'littra')name,
  case when count(*)filter(where amount is null)=0 then coalesce(sum(amount),0)end total,coalesce(sum(amount),0)priced_amount,
  count(*)rows,count(*)filter(where amount is null)missing_rows,
  coalesce(sum(amount)filter(where r->>'category'='material'),0)material,
  coalesce(sum(amount)filter(where r->>'category'='transport'),0)transport,
  coalesce(sum(amount)filter(where r->>'category'='tipp_deponi'),0)tipp_deponi
  from items group by 1,2)
 select jsonb_build_object('version',1,'period',jsonb_build_object('from',p_from,'to',p_to,'months',p_months),
  'created_at',now(),'generation',generation,'rows',rows,'totals',to_jsonb(t),
  'centers',coalesce((select jsonb_agg(to_jsonb(c)order by center)from centers c),'[]'),
  'projects',coalesce((select jsonb_agg(to_jsonb(p)order by center,project)from projects p),'[]'),
  'reconciliation',summary-'transfers'-'unassignedItems'-'otherItems'-'conflicts',
  'exceptions',jsonb_build_object('unassigned',summary->'unassignedItems','other',summary->'otherItems','conflicts',summary->'conflicts'),
  'basis','Överföring från KST 10 Entreprenad till KST 30 Transport och KST 20 Sortergården. Material värderas till Hubben-beräknad självkostnad utan materialpåslag. Godkända överslagspriser märks preliminära. Transport, tipp och övriga debiterade interna tjänster värderas till 90 % av debiteringsbeloppet (10 % avdrag). Material inklusive transport följer publicerad Hub-uppdelning; transportdelen får 10 % avdrag. Saknad uppdelning/prissättning visas öppet. Samtliga entydiga periodrader ingår oavsett exportstatus. Ingen bokföring, exportstatus eller KPI-intäkt ändras.')into result from totals t;
 return result;
end$$;
revoke all on function public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])from public,anon;
grant execute on function public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])to authenticated;
notify pgrst,'reload schema';
