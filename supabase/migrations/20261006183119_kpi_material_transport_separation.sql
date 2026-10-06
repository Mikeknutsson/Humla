CREATE OR REPLACE FUNCTION private.hub_kpi_material_purchase_costs_v1(p_tenant_id uuid, p_row_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if cardinality(p_row_ids)>10000 then raise exception 'Too many rows';end if;
 WITH requested_orders AS MATERIALIZED (
 SELECT DISTINCT nullif(trim(source_data->>'Ordernummer'),'') order_number
 FROM public.kpi_import_rows
 WHERE tenant_id=p_tenant_id AND id=ANY(p_row_ids)
 AND data_kind='revenue' 
), order_rows AS MATERIALIZED (
 SELECT r.*, e.supplier_key order_receipt_supplier,e.read_status order_read_status,e.receipt_reference order_receipt_reference
 FROM public.kpi_import_rows r
 JOIN requested_orders o ON o.order_number=nullif(trim(r.source_data->>'Ordernummer'),'')
 LEFT JOIN private.hub_kpi_internal_receipt_reads e ON e.tenant_id=r.tenant_id AND e.receipt_url=nullif(r.source_data->>'FilUrl','')
 WHERE r.tenant_id=p_tenant_id AND r.data_kind='revenue'
 
), order_receipts AS MATERIALIZED (
 SELECT nullif(trim(source_data->>'Ordernummer'),'') order_number,
 count(DISTINCT nullif(source_data->>'FilUrl','')) FILTER(WHERE order_read_status IS DISTINCT FROM 'not_receipt') receipt_count,
 array_agg(DISTINCT order_receipt_supplier) FILTER(WHERE order_read_status IN ('reviewed','ocr') AND order_receipt_supplier IS NOT NULL) suppliers,
 string_agg(DISTINCT order_receipt_reference,', ') FILTER(WHERE order_read_status IN ('reviewed','ocr') AND order_receipt_supplier IS NOT NULL) references
 FROM order_rows GROUP BY 1
), order_comments AS MATERIALIZED (
 SELECT nullif(trim(r.source_data->>'Ordernummer'),'') order_number,array_agg(DISTINCT s.supplier) suppliers
 FROM order_rows r CROSS JOIN LATERAL (VALUES
 ('KYLLINGE','kylinge|kyllinge|johanssons'),('SCHWEDEN_SPLITT','schweden|splitt'),('VAMBASA','vambåsa|vambasa'),
 ('ONNESTAD','önnestad|onnestad'),('OSSJO','össjö|ossjo'))s(supplier,pattern)
 WHERE coalesce(r.source_data->>'ArtikelKommentar','') ~* s.pattern GROUP BY 1
), raw as materialized(
 select r.*,case when coalesce(nullif(source_data->>'Kvantitet',''),'') ~ '^-?[0-9 ]+([.,][0-9]+)?$' then replace(replace(source_data->>'Kvantitet',' ',''),',','.')::numeric else quantity end effective_quantity,
 case when exists(select 1 from jsonb_array_elements(a.source_rows) e where trim(e->'values'->>'Namn') ilike 'Tippavgift%') then 'tipp_deponi'
 when exists(select 1 from jsonb_array_elements(a.source_rows) e where coalesce(e#>>'{values,Namn}',e->>'name','') ~* 'inkl[.]?\s*transport')
 and coalesce(r.source_data->>'Artikelnamn',r.description,'') ~* 'förstärkningslager|bärlager|slitlager|makadam|stenmjöl|råberg|dräneringsgrus|matjord|fyllnadsmaterial' then 'material'
 else a.revenue_category end category,
 (regexp_match(coalesce(r.source_data->>'Artikelnamn',r.description),'([0-9]+)[/-]([0-9]+)'))[1]||'-'||(regexp_match(coalesce(r.source_data->>'Artikelnamn',r.description),'([0-9]+)[/-]([0-9]+)'))[2] fraction,
 o.receipt_count order_receipt_count,o.suppliers order_receipt_suppliers,o.references order_receipt_references,c.suppliers order_comment_suppliers,
 e.supplier_key receipt_supplier,e.material_fractions,e.receipt_quantity,e.receipt_date,e.receipt_reference,e.read_status,e.note receipt_note,
 -- Explicit source comments are a preliminary source hint, never a verified receipt.
 case when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'kylinge|kyllinge|johanssons' then 'KYLLINGE'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'schweden|splitt' then 'SCHWEDEN_SPLITT'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'vambåsa|vambasa' then 'VAMBASA'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'önnestad|onnestad' then 'ONNESTAD'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'össjö|ossjo' then 'OSSJO' end comment_supplier
 from public.kpi_import_rows r
 left join order_receipts o on o.order_number=nullif(trim(r.source_data->>'Ordernummer'),'')
 left join order_comments c on c.order_number=nullif(trim(r.source_data->>'Ordernummer'),'')
 left join private.hub_kpi_internal_receipt_reads e on e.tenant_id=r.tenant_id and e.receipt_url=nullif(r.source_data->>'FilUrl','')
 left join lateral(select a.revenue_category,a.source_rows from public.kpi_workify_article_rules a where a.tenant_id=r.tenant_id and a.enabled and a.article_number=r.source_data->>'Artikelnummer' and a.valid_from<=r.occurred_on and (a.valid_to is null or a.valid_to>=r.occurred_on) order by a.valid_from desc,a.id limit 1)a on true
 where r.tenant_id=p_tenant_id and r.id=any(p_row_ids) and r.data_kind='revenue' 
 ), scoped as(
 select r.*,case when cardinality(material_fractions)=1 and (material_fractions[1]=fraction or material_fractions[1]=regexp_replace(source_data->>'Artikelnummer','^[A-Za-z]+','') or (split_part(material_fractions[1],'-',1)=split_part(fraction,'-',1) and coalesce(source_data->>'Artikelnamn',description) ~ ('/'||split_part(material_fractions[1],'-',2)||'([^0-9]|$)'))) then material_fractions[1] else fraction end price_fraction,
 case when coalesce(order_receipt_count,0)>0 then
 coalesce(case when read_status in ('reviewed','ocr') and (receipt_date is null or receipt_date=occurred_on) and (cardinality(material_fractions)=0 or (cardinality(material_fractions)=1 and (material_fractions[1]=fraction or material_fractions[1]=regexp_replace(source_data->>'Artikelnummer','^[A-Za-z]+','') or (split_part(material_fractions[1],'-',1)=split_part(fraction,'-',1) and coalesce(source_data->>'Artikelnamn',description) ~ ('/'||split_part(material_fractions[1],'-',2)||'([^0-9]|$)'))))) then receipt_supplier else null end,case when cardinality(order_receipt_suppliers)=1 then order_receipt_suppliers[1] end)
 else case when cardinality(order_comment_suppliers)=1 then order_comment_suppliers[1] end end supplier,
 case when coalesce(order_receipt_count,0)>0 then
 case when (case when read_status in ('reviewed','ocr') and (receipt_date is null or receipt_date=occurred_on) and (cardinality(material_fractions)=0 or (cardinality(material_fractions)=1 and (material_fractions[1]=fraction or material_fractions[1]=regexp_replace(source_data->>'Artikelnummer','^[A-Za-z]+','') or (split_part(material_fractions[1],'-',1)=split_part(fraction,'-',1) and coalesce(source_data->>'Artikelnamn',description) ~ ('/'||split_part(material_fractions[1],'-',2)||'([^0-9]|$)'))))) then receipt_supplier else null end) is not null then 'row_receipt' when cardinality(order_receipt_suppliers)=1 then 'order_receipt' else 'receipt_review' end
 else case when cardinality(order_comment_suppliers)=1 then 'order_comment' when cardinality(order_comment_suppliers)>1 then 'comment_review' else 'average' end end supplier_basis,
 case when fraction is not null and coalesce(source_data->>'Artikelnamn',description) ~ '[0-9]+[/-][0-9]+/[0-9]+' and not coalesce((cardinality(material_fractions)=1 and (material_fractions[1]=fraction or material_fractions[1]=regexp_replace(source_data->>'Artikelnummer','^[A-Za-z]+','') or (split_part(material_fractions[1],'-',1)=split_part(fraction,'-',1) and coalesce(source_data->>'Artikelnamn',description) ~ ('/'||split_part(material_fractions[1],'-',2)||'([^0-9]|$)')))),false) then true else false end ambiguous_fraction
 from raw r
 ), receipt_counts as materialized(
 select other.source_data->>'FilUrl' receipt_url,other.source_data->>'Artikelnummer' article,count(*) uses from public.kpi_import_rows other
 where other.tenant_id=p_tenant_id and other.data_kind='revenue' and nullif(other.source_data->>'FilUrl','') is not null group by 1,2
 ), prices as(
 select r.*,p.net_price,p.source_reference,p.note price_note,p.valid_from price_valid_from,
 avgp.average_price,avgp.samples,avgp.sources,
 -- Reused attachments cannot verify the same quantity against several source lines.
 coalesce(rc.uses,0) receipt_uses
 from scoped r
 left join receipt_counts rc on rc.receipt_url=r.source_data->>'FilUrl' and rc.article=r.source_data->>'Artikelnummer'
 left join lateral(select p.* from private.hub_kpi_internal_purchase_prices p where p.tenant_id=r.tenant_id and p.supplier_key=r.supplier and p.material_fraction=r.price_fraction and p.standard_material and p.unit=lower(r.source_data->>'Enhet') and (p.valid_from is null or p.valid_from<=r.occurred_on) and (p.valid_to is null or p.valid_to>=r.occurred_on) order by p.valid_from desc nulls last,p.source_key limit 1)p on true
 left join lateral(select round(avg(q.net_price),4) average_price,count(*) samples,jsonb_agg(jsonb_build_object('supplier',q.supplier_key,'price',q.net_price,'source',q.source_reference)) sources from(
 select distinct on(p.supplier_key) p.* from private.hub_kpi_internal_purchase_prices p where p.tenant_id=r.tenant_id and p.supplier_key in ('KYLLINGE','SCHWEDEN_SPLITT','VAMBASA') and p.material_fraction=r.price_fraction and p.standard_material and p.unit=lower(r.source_data->>'Enhet') and (p.valid_from is null or p.valid_from<=r.occurred_on) and (p.valid_to is null or p.valid_to>=r.occurred_on) order by p.supplier_key,p.valid_from desc nulls last,p.source_key)q)avgp on true
 ), selected as(
 select r.*,case when category='material' and not ambiguous_fraction
 and coalesce(source_data->>'Artikelnamn',description,'') !~* 'uttaget.*kund|tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus' then case when supplier_basis in ('receipt_review','comment_review') then null when supplier is not null then net_price else average_price end end rate,
 case when category='material' and coalesce(source_data->>'Artikelnamn',description,'') ~* 'uttaget.*kund' then 'customer_paid_review'
 when category='material' and coalesce(source_data->>'Artikelnamn',description,'') ~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus' then 'special_material_review'
 when category is distinct from 'material' then case when category='tipp_deponi' then 'missing_tipping_price' else 'not_applicable' end
 when supplier_basis='receipt_review' then 'order_supplier_review'
 when supplier_basis='comment_review' then 'order_comment_review'
 when ambiguous_fraction then 'ambiguous_material'
 when supplier is not null and net_price is not null then case when receipt_supplier=supplier and receipt_date=occurred_on and read_status='reviewed' and price_valid_from is not null then 'receipt_price_list' else 'preliminary_source' end
 when supplier is null and average_price is not null then 'average_estimate'
 else 'missing_price' end price_status
 from prices r
 ) select coalesce(jsonb_object_agg(id::text,jsonb_build_object(
 'rate',rate,'quantity',effective_quantity,'unit',lower(source_data->>'Enhet'),'amount',case when rate is not null and effective_quantity is not null then round(rate*effective_quantity,2) end,
 'margin',case when rate is not null and effective_quantity is not null and amount is not null then amount-round(rate*effective_quantity,2) end,
 'status',price_status,'supplier',supplier,'supplier_basis',supplier_basis,'order_receipt_references',order_receipt_references,'fraction',price_fraction,
 'price_source',case when supplier is not null then source_reference else 'Medelpris Johanssons / Schweden Splitt / Vambåsa' end,
 'price_sources',case when supplier is null then sources end,'price_sample_count',case when supplier is null then samples else case when net_price is null then 0 else 1 end end,
 'receipt_quantity',case when supplier_basis='row_receipt' and supplier=receipt_supplier and receipt_uses=1 and receipt_date=occurred_on and price_fraction=any(material_fractions) and receipt_quantity<=effective_quantity+0.01 and read_status='reviewed' then receipt_quantity end,
 'receipt_cost',case when supplier_basis='row_receipt' and supplier=receipt_supplier and receipt_uses=1 and receipt_date=occurred_on and price_fraction=any(material_fractions) and receipt_quantity<=effective_quantity+0.01 and read_status='reviewed' and rate is not null then round(receipt_quantity*rate,2) end,
 'receipt_reference',receipt_reference,'receipt_read_status',coalesce(read_status,case when nullif(source_data->>'FilUrl','') is null then 'missing_receipt' else 'not_read' end),
 'note',concat_ws('; ',receipt_note,price_note,
 case supplier_basis when 'order_receipt' then 'Täkt ärvd från kvitto på samma order; kvittomängd överförs inte'
 when 'order_comment' then 'Täkt från orderns kommentarer; inga kvitton finns'
 when 'receipt_review' then 'Ordern har kvitton utan entydig täkt för denna rad; kräver granskning'
 when 'comment_review' then 'Orderns kommentarer anger flera täkter; kräver granskning' end,
 case when supplier_basis='order_receipt' then 'Orderns kvittoreferenser: '||order_receipt_references end,case when receipt_uses>1 then 'Bilagan delas av flera rader; kvittomängden kräver fördelning' end,case when receipt_date is not null and receipt_date<>occurred_on then 'Kvittodatum skiljer sig från transaktionsdatum' end,
 case when rate is not null and effective_quantity is null then 'Mängd saknas' end)
 )),'{}'::jsonb) into result from selected;
 return result;
end $function$

;
revoke all on function private.hub_kpi_material_purchase_costs_v1(uuid,uuid[]) from public,anon,authenticated;
-- Reallocate derived reports only. Never create purchase costs from estimates:
-- NEXT remains the cost source; receipt/list estimates split bundled revenue.
create index if not exists hub_kpi_prepared_facts_generation_fact_idx
 on private.hub_kpi_prepared_facts(generation_id,fact_id);
create table private.hub_kpi_material_separation_settings (
 tenant_id uuid primary key references public.hub_tenants(id),
 material_unit_id uuid not null references public.kpi_units(id),
 valid_from date not null,
 enabled boolean not null default false,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now()
);
alter table private.hub_kpi_material_separation_settings enable row level security;
revoke all on private.hub_kpi_material_separation_settings from public,anon,authenticated;

create function private.hub_kpi_separate_material_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare cfg record; batch record; f record; prices jsonb; evidence jsonb; part numeric;
 bundled boolean; carrier text; carrier_unit uuid; carrier_name text; allocation jsonb;
 before_revenue numeric; before_cost numeric; after_revenue numeric; after_cost numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then
 raise exception 'KPI management required' using errcode='42501'; end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then
 raise exception 'Report generation tenant mismatch';end if;
 select s.*,u.name,u.projects[1] material_project into cfg from private.hub_kpi_material_separation_settings s
 join public.kpi_units u on u.id=s.material_unit_id and u.tenant_id=s.tenant_id and u.enabled and cardinality(u.projects)=1 and u.unit_type='project'
 where s.tenant_id=p_tenant and s.enabled;
 if not found then return;end if;
 -- Never apply twice to a derived generation.
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=p_generation and original?'_humla_material_separation') then
 raise exception 'Material separation already applied';end if;
 select coalesce(sum(amount)filter(where kind='revenue'),0),coalesce(sum(amount)filter(where kind='cost'),0)
 into before_revenue,before_cost from private.hub_kpi_prepared_facts where generation_id=p_generation;

 -- Only detach material purchases from vehicle carriers. Existing storage and
 -- Trading assignments, and all tipping assignments, remain intact.
 update private.hub_kpi_prepared_facts f set
 unit_id=cfg.material_unit_id,unit_name=cfg.name,vehicle=null,project=cfg.material_project,business_group='Grusmaterial',
 original=f.original||jsonb_build_object('_humla_material_separation',jsonb_build_object(
 'method','next_material_cost','original_fact_id',f.fact_id,'original_amount',f.amount,
 'original_vehicle',f.vehicle,'original_unit_id',f.unit_id,'original_project',f.project))
 where f.generation_id=p_generation and f.occurred_on>=cfg.valid_from and f.kind='cost' and f.category='material'
 and (f.vehicle is not null or exists(select 1 from public.kpi_units u where u.id=f.unit_id and u.tenant_id=p_tenant and u.unit_type in('vehicle','compound')));

 for batch in
 select array_agg(id) ids from (
 select distinct r.id,(row_number()over(order by r.id)-1)/1000 bucket
 from public.kpi_import_rows r
 where r.tenant_id=p_tenant and exists(
 select 1 from private.hub_kpi_prepared_facts f where f.generation_id=p_generation
 and f.occurred_on>=cfg.valid_from and f.source='Workify' and f.kind='revenue' and f.fact_id=r.id::text
 and coalesce(f.original->>'Artikelnamn',f.description,'') ~* 'förstärkningslager|bärlager|slitlager|makadam|stenmjöl|råberg|dräneringsgrus|matjord|fyllnadsmaterial')
 )q group by bucket
 loop
 prices:=private.hub_kpi_material_purchase_costs_v1(p_tenant,batch.ids);
 for f in select f.*,coalesce(a.article_name,a.source_rows#>>'{0,values,Namn}','') rule_name,
 r.vehicle_registration source_registration
 from private.hub_kpi_prepared_facts f
 join public.kpi_import_rows r on r.id::text=f.fact_id and r.tenant_id=p_tenant
 left join lateral(select a.* from public.kpi_workify_article_rules a
 where a.tenant_id=p_tenant and a.article_number=f.original->>'Artikelnummer' and a.enabled
 and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
 order by a.valid_from desc,a.id limit 1)a on true
 where f.generation_id=p_generation and f.fact_id=any(array(select x::text from unnest(batch.ids)x))
 loop
 bundled:=concat_ws(' ',f.rule_name,f.original->>'Artikelnamn',f.description) ~* 'inkl[.]?\s*transport';
 if not bundled and f.category<>'material' then continue;end if;
 evidence:=prices->f.fact_id;
 part:=case when bundled then (evidence->>'amount')::numeric else f.amount end;
 if bundled and (part is null or (part<>0 and sign(part)<>sign(f.amount))) then
 update private.hub_kpi_prepared_facts set original=original||jsonb_build_object('_humla_material_separation',
 jsonb_build_object('status','needs_review','reason',coalesce(evidence->>'status','missing_purchase_price'),'purchase',evidence))
 where generation_id=p_generation and fact_id=f.fact_id;
 continue;
 end if;
 carrier:=coalesce(nullif(f.vehicle,''),nullif(upper(trim(f.source_registration)),''));
 carrier_unit:=f.unit_id;carrier_name:=f.unit_name;
 -- A project-targeted bundled article still has a transport remainder on its
 -- resolved vehicle. Without that identity, preserve the source allocation.
 if bundled and f.vehicle is null and carrier is not null then
 select case when count(distinct u.id)=1 then (array_agg(distinct u.id))[1] end,
 case when count(distinct u.id)=1 then max(u.name) end into carrier_unit,carrier_name
 from public.kpi_units u where u.tenant_id=p_tenant and u.enabled
 and (exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant and p.unit_id=u.id
 and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
 and carrier in(select jsonb_array_elements_text(coalesce(p.payload->'registrations',to_jsonb(u.registrations)))))
 or (not exists(select 1 from public.kpi_unit_periods p where p.unit_id=u.id and p.tenant_id=p_tenant)
 and carrier=any(u.registrations) and u.valid_from<=f.occurred_on and (u.valid_to is null or u.valid_to>=f.occurred_on)));
 end if;
 allocation:=jsonb_build_object('method',case when bundled then 'purchase_price_transport_remainder' else 'material_article' end,
 'original_fact_id',f.fact_id,'original_amount',f.amount,'original_vehicle',f.vehicle,
 'original_unit_id',f.unit_id,'original_project',f.project,'purchase',evidence,
 'estimated',coalesce(evidence->>'status','') in('average_estimate','preliminary_source'));
 if bundled then
 -- Clone only revenue. Preserve date, cost centre, source and original evidence.
 insert into private.hub_kpi_prepared_facts
 select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(f)-'rule_name'-'source_registration'||
 jsonb_build_object('fact_id',f.fact_id||':material','amount',part,'category','material',
 'unit_id',case when f.vehicle is null and f.unit_id is not null then f.unit_id else cfg.material_unit_id end,
 'unit_name',case when f.vehicle is null and f.unit_id is not null then f.unit_name else cfg.name end,
 'vehicle',null,'project',case when f.vehicle is null and f.unit_id is not null then f.project else cfg.material_project end,
 'business_group',case when f.vehicle is null and f.unit_id is not null then f.business_group else 'Grusmaterial' end,
 'original',f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material'))))).*;
 update private.hub_kpi_prepared_facts set amount=f.amount-part,category='transport',
 vehicle=carrier,unit_id=carrier_unit,unit_name=carrier_name,
 project=case when f.vehicle is null and carrier is not null then null else f.project end,
 original=f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','transport'))
 where generation_id=p_generation and fact_id=f.fact_id;
 elsif f.vehicle is not null then
 update private.hub_kpi_prepared_facts set vehicle=null,unit_id=cfg.material_unit_id,unit_name=cfg.name,
 project=cfg.material_project,business_group='Grusmaterial',
 original=f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material'))
 where generation_id=p_generation and fact_id=f.fact_id;
 end if;
 end loop;
 end loop;
 select coalesce(sum(amount)filter(where kind='revenue'),0),coalesce(sum(amount)filter(where kind='cost'),0)
 into after_revenue,after_cost from private.hub_kpi_prepared_facts where generation_id=p_generation;
 if before_revenue<>after_revenue or before_cost<>after_cost then raise exception 'Material separation total mismatch';end if;
end $$;
revoke all on function private.hub_kpi_separate_material_v1(uuid,uuid) from public,anon,authenticated;

-- Preserve the live worker and its independent nightly schedule. Insert the
-- postprocessor immediately before the compact display projection is created.
do $$ declare definition text; needle text:=' insert into private.hub_kpi_prepared_display_facts';
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if position(needle in definition)=0 or position('hub_kpi_separate_material_v1' in definition)>0 then
 raise exception 'Unexpected report worker version';end if;
 definition:=replace(definition,needle,' perform private.hub_kpi_separate_material_v1(job.tenant_id,generation);'||chr(10)||
 ' update private.hub_kpi_prepared_facts set display_original=display_original||jsonb_build_object(''_humla_material_separation'',original->''_humla_material_separation'') where generation_id=generation and original?''_humla_material_separation'';'||chr(10)||needle);
 execute definition;
end $$;

do $$ declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 if position('''material_separation''' in definition)>0 then raise exception 'Separation projection already installed';end if;
 definition:=replace(definition,'jsonb_build_object(''time_report_id'',original->''time_report_id'',',
 'jsonb_build_object(''_humla_material_separation'',original->''_humla_material_separation'',''time_report_id'',original->''time_report_id'',');
 definition:=replace(definition,'''quality'',',
 '''material_separation'',(select jsonb_build_object(''active'',count(*)>0,''review_rows'',count(*)filter(where original#>>''{_humla_material_separation,status}''=''needs_review''),''split_rows'',count(*)filter(where original#>>''{_humla_material_separation,component}''=''transport'')) from facts where jsonb_typeof(original->''_humla_material_separation'')=''object''),''quality'',');
 execute definition;
end $$;

-- Once material has left the vehicles, per-truck revenue must also exclude
-- project revenue. Otherwise moving material off a truck inflates this metric.
do $$ declare definition text; old_metric text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 old_metric:='''revenue_per_vehicle'',round((t.revenue-t.hired)/nullif(t.vehicles,0),2)';
 if position(old_metric in definition)=0 then raise exception 'Unexpected own truck metric';end if;
 definition:=replace(definition,old_metric,
 '''revenue_per_vehicle'',case when exists(select 1 from facts where jsonb_typeof(original->''_humla_material_separation'')=''object'') then round((select coalesce(sum(amount),0) from facts where kind=''revenue'' and vehicle not in(''LASTBIL'',''INHYRDLASTBIL'',''Ej fördelat'',''''))/nullif(t.vehicles,0),2) else round((t.revenue-t.hired)/nullif(t.vehicles,0),2) end');
 execute definition;
 definition:=pg_get_functiondef('private.hub_kpi_transport_period_report_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 old_metric:='round(coalesce(invoiced_revenue,0)/active_vehicles,2)';
 if position(old_metric in definition)=0 then raise exception 'Unexpected monthly truck metric';end if;
 definition:=replace(definition,old_metric,
 'case when exists(select 1 from private.hub_kpi_material_separation_settings where tenant_id=p_tenant_id and enabled) then round((select coalesce(sum(invoiced_revenue),0) from vehicles where not hired)/active_vehicles,2) else round(coalesce(invoiced_revenue,0)/active_vehicles,2) end');
 definition:=replace(definition,'Fakturerad omsättning / antal egna intäktsbärande fordon i perioden. Inhyrdas samlingsenhet ingår i intäkten men inte i antalet. Fullständigt lastbilsbestånd behöver verifieras.',
 'Intäkter på egna intäktsbärande fordon / antal fordon när materialuppdelning är aktiv. Projektintäkter och inhyrda räknas då inte med. Fullständigt lastbilsbestånd behöver verifieras.');
 execute definition;
end $$;
