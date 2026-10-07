-- User-authorized exact customer + littra material purchase override.
CREATE TABLE private.hub_kpi_internal_project_purchase_prices (
 tenant_id uuid NOT NULL REFERENCES public.hub_tenants(id),
 customer_name text NOT NULL,
 littra_number text NOT NULL,
 material_fraction text NOT NULL,
 unit text NOT NULL DEFAULT 'ton',
 net_price numeric NOT NULL CHECK(net_price>=0),
 valid_from date NOT NULL DEFAULT '2000-01-01',
 valid_to date CHECK(valid_to IS NULL OR valid_to>=valid_from),
 enabled boolean NOT NULL DEFAULT true,
 source_reference text NOT NULL,
 source_issued_on date,
 note text NOT NULL DEFAULT '',
 PRIMARY KEY(tenant_id,customer_name,littra_number,material_fraction,unit,valid_from)
);
ALTER TABLE private.hub_kpi_internal_project_purchase_prices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.hub_kpi_internal_project_purchase_prices FROM PUBLIC,anon,authenticated;
INSERT INTO private.hub_kpi_internal_project_purchase_prices(tenant_id,customer_name,littra_number,material_fraction,net_price,source_reference,source_issued_on,note)
SELECT '944597b6-9c46-4bef-998d-f19e23c4245b'::uuid,'PEAB Anläggning AB','4114-7511012-1200',fraction,price,'Uppdaterad Offert Elleholms Maskin AB Karlshamn.pdf','2026-03-02'::date,
'Johanssons Grus & Mark Entreprenad; Vattenverk Fas-2 Karlshamn. HLS, exkl moms. Projektregel enligt Mike 2026-10-07 gäller matchande orderrader inklusive historik. Offertens angivna 30 dagars offertgiltighet sparas som källvillkor; ingen automatisk prisändring efter 30 dagar.'
FROM (VALUES('0-16',65::numeric),('0-32',64::numeric),('0-90',60::numeric),('11-16',110::numeric),('0-4',65::numeric))p(fraction,price);

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
 SELECT r.*, links.receipt_url order_receipt_url,e.supplier_key order_receipt_supplier,e.read_status order_read_status,e.receipt_reference order_receipt_reference
 FROM public.kpi_import_rows r
 JOIN requested_orders o ON o.order_number=nullif(trim(r.source_data->>'Ordernummer'),'')
 LEFT JOIN LATERAL (
 SELECT DISTINCT receipt_url FROM (VALUES (nullif(trim(r.source_data->>'FilUrl'),'')),(case when r.source_data->>'Platser' ~ '^https?://' then nullif(trim(r.source_data->>'Platser'),'') end)) urls(receipt_url) WHERE receipt_url IS NOT NULL
 ) links ON true
 LEFT JOIN private.hub_kpi_internal_receipt_reads e ON e.tenant_id=r.tenant_id AND e.receipt_url=links.receipt_url
 WHERE r.tenant_id=p_tenant_id AND r.data_kind='revenue'
 
), order_receipts AS MATERIALIZED (
 SELECT nullif(trim(source_data->>'Ordernummer'),'') order_number,
 count(DISTINCT order_receipt_url) FILTER(WHERE order_read_status IS DISTINCT FROM 'not_receipt') receipt_count,
 count(DISTINCT order_receipt_url) FILTER(WHERE order_read_status IN ('reviewed','ocr') AND order_receipt_supplier IS NOT NULL) supplier_evidence_count,
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
 when (exists(select 1 from jsonb_array_elements(a.source_rows) e where coalesce(e#>>'{values,Namn}',e->>'name','') ~* 'in[ck]l?[.]?[[:space:]]*transport') or concat_ws(' ',a.article_name,r.source_data->>'Artikelnamn',r.description) ~* 'in[ck]l?[.]?[[:space:]]*transport')
 and coalesce(r.source_data->>'Artikelnamn',r.description,'') ~* 'förstärkningslager|bärlager|slitlager|makadam|stenmjöl|råberg|dräneringsgrus|matjord|fyllnadsmaterial' then 'material'
 else a.revenue_category end category,
 (regexp_match(coalesce(r.source_data->>'Artikelnamn',r.description),'([0-9]+)[/-]([0-9]+)'))[1]||'-'||(regexp_match(coalesce(r.source_data->>'Artikelnamn',r.description),'([0-9]+)[/-]([0-9]+)'))[2] fraction,
 o.receipt_count order_receipt_count,o.supplier_evidence_count,o.suppliers order_receipt_suppliers,o.references order_receipt_references,c.suppliers order_comment_suppliers,
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
 left join lateral(select a.revenue_category,a.source_rows,a.article_name from public.kpi_workify_article_rules a where a.tenant_id=r.tenant_id and a.enabled and a.article_number=r.source_data->>'Artikelnummer' and a.valid_from<=r.occurred_on and (a.valid_to is null or a.valid_to>=r.occurred_on) order by a.valid_from desc,a.id limit 1)a on true
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
 op.net_price project_net_price,op.source_reference project_price_reference,op.note project_price_note,op.material_fraction project_price_fraction,
 avgp.average_price,avgp.samples,avgp.sources,
 -- Reused attachments cannot verify the same quantity against several source lines.
 coalesce(rc.uses,0) receipt_uses
 from scoped r
 left join receipt_counts rc on rc.receipt_url=r.source_data->>'FilUrl' and rc.article=r.source_data->>'Artikelnummer'
 left join lateral(select p.* from private.hub_kpi_internal_purchase_prices p where p.tenant_id=r.tenant_id and p.supplier_key=r.supplier and p.material_fraction=r.price_fraction and p.standard_material and p.unit=lower(r.source_data->>'Enhet') and (p.valid_from is null or p.valid_from<=r.occurred_on) and (p.valid_to is null or p.valid_to>=r.occurred_on) order by p.valid_from desc nulls last,p.source_key limit 1)p on true
 left join lateral(select round(avg(q.net_price),4) average_price,count(*) samples,jsonb_agg(jsonb_build_object('supplier',q.supplier_key,'price',q.net_price,'source',q.source_reference)) sources from(
 select distinct on(p.supplier_key) p.* from private.hub_kpi_internal_purchase_prices p where p.tenant_id=r.tenant_id and p.supplier_key in ('KYLLINGE','SCHWEDEN_SPLITT','VAMBASA') and p.material_fraction=r.price_fraction and p.standard_material and p.unit=lower(r.source_data->>'Enhet') and (p.valid_from is null or p.valid_from<=r.occurred_on) and (p.valid_to is null or p.valid_to>=r.occurred_on) order by p.supplier_key,p.valid_from desc nulls last,p.source_key)q)avgp on true
 left join lateral(select op.* from private.hub_kpi_internal_project_purchase_prices op
 where op.tenant_id=r.tenant_id and op.customer_name=trim(r.source_data->>'Kundnamn')
 and op.littra_number=trim(r.source_data->>'Littranummer') and op.material_fraction=r.price_fraction
 and op.unit=lower(trim(r.source_data->>'Enhet')) and op.enabled
 and op.valid_from<=r.occurred_on and (op.valid_to is null or op.valid_to>=r.occurred_on)
 order by op.valid_from desc limit 1)op on true
 ), selected as(
 select r.*,case when (category='material' or project_net_price is not null) and not ambiguous_fraction
 and coalesce(source_data->>'Artikelnamn',description,'') !~* 'uttaget.*kund|tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus' then case when project_net_price is not null then project_net_price when supplier_basis in ('receipt_review','comment_review') then case when samples=3 then average_price end when supplier is not null then net_price else average_price end end rate,
 case when category='material' and coalesce(source_data->>'Artikelnamn',description,'') ~* 'uttaget.*kund' then 'customer_paid_review'
 when category='material' and coalesce(source_data->>'Artikelnamn',description,'') ~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus' then 'special_material_review'
 when project_net_price is not null and not ambiguous_fraction then 'project_price_override'
 when category is distinct from 'material' then case when category='tipp_deponi' then 'missing_tipping_price' else 'not_applicable' end
 when supplier_basis='receipt_review' then case when samples=3 and average_price is not null then 'average_estimate' else 'order_supplier_review' end
 when supplier_basis='comment_review' then case when samples=3 and average_price is not null then 'average_estimate' else 'order_comment_review' end
 when ambiguous_fraction then 'ambiguous_material'
 when supplier is not null and net_price is not null then case when receipt_supplier=supplier and receipt_date=occurred_on and read_status='reviewed' and price_valid_from is not null then 'receipt_price_list' else 'preliminary_source' end
 when supplier is null and average_price is not null then 'average_estimate'
 else 'missing_price' end price_status
 from prices r
 ) select coalesce(jsonb_object_agg(id::text,jsonb_build_object(
 'rate',rate,'quantity',effective_quantity,'unit',lower(source_data->>'Enhet'),'amount',case when rate is not null and effective_quantity is not null then round(rate*effective_quantity,2) end,
 'margin',case when rate is not null and effective_quantity is not null and amount is not null then amount-round(rate*effective_quantity,2) end,
 'status',price_status,'supplier',supplier,'price_rule',case when project_net_price is not null then jsonb_build_object('customer',trim(source_data->>'Kundnamn'),'littra',trim(source_data->>'Littranummer'),'fraction',project_price_fraction,'supplier','KYLLINGE') end,'supplier_basis',supplier_basis,'supplier_inferred',supplier_basis='order_receipt','supplier_evidence_count',coalesce(supplier_evidence_count,0),'order_receipt_references',order_receipt_references,'fraction',price_fraction,
 'price_source',case when project_net_price is not null then project_price_reference when supplier is not null then source_reference else 'Medelpris Johanssons / Schweden Splitt / Vambåsa' end,
 'price_sources',case when project_net_price is null and supplier is null then sources end,'price_sample_count',case when project_net_price is not null then 1 when supplier is null then samples else case when net_price is null then 0 else 1 end end,
 'receipt_quantity',case when supplier_basis='row_receipt' and supplier=receipt_supplier and receipt_uses=1 and receipt_date=occurred_on and price_fraction=any(material_fractions) and receipt_quantity<=effective_quantity+0.01 and read_status='reviewed' then receipt_quantity end,
 'receipt_cost',case when supplier_basis='row_receipt' and supplier=receipt_supplier and receipt_uses=1 and receipt_date=occurred_on and price_fraction=any(material_fractions) and receipt_quantity<=effective_quantity+0.01 and read_status='reviewed' and rate is not null then round(receipt_quantity*rate,2) end,
 'receipt_reference',receipt_reference,'receipt_read_status',coalesce(read_status,case when nullif(source_data->>'FilUrl','') is null then 'missing_receipt' else 'not_read' end),
 'note',concat_ws('; ',receipt_note,case when project_net_price is not null then project_price_note else price_note end,
 case supplier_basis when 'order_receipt' then 'Sannolikhetsregel: täkt antagen från tolkade kvitton på samma order som pekar på en enda täkt; kvittomängd överförs inte'
 when 'order_comment' then 'Täkt från orderns kommentarer; inga kvitton finns'
 when 'receipt_review' then case when price_status='average_estimate' then 'Täkt är inte entydig; schablonavdrag med medelpris från tre täkter. Kvittona behöver fortfarande granskas' else 'Ordern har kvitton utan entydig täkt för denna rad; kräver granskning' end
 when 'comment_review' then case when price_status='average_estimate' then 'Flera täkter i orderns kommentarer; schablonavdrag med medelpris från tre täkter' else 'Orderns kommentarer anger flera täkter; kräver granskning' end end,
 case when supplier_basis='order_receipt' then 'Orderns kvittoreferenser: '||order_receipt_references end,case when receipt_uses>1 then 'Bilagan delas av flera rader; kvittomängden kräver fördelning' end,case when receipt_date is not null and receipt_date<>occurred_on then 'Kvittodatum skiljer sig från transaktionsdatum' end,
 case when rate is not null and effective_quantity is null then 'Mängd saknas' end)
 )),'{}'::jsonb) into result from selected;
 return result;
end $function$;