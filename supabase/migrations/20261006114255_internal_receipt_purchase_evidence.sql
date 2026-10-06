-- Additive receipt/price evidence. Original income, identities and transfer ledger stay intact.
create table private.hub_kpi_internal_purchase_prices (
 tenant_id uuid not null references public.hub_tenants(id),
 source_key text not null, supplier_key text not null, material_fraction text not null,
 material_name text not null, unit text not null default 'ton', net_price numeric not null,
 valid_from date, valid_to date, standard_material boolean not null default false,
 source_reference text not null, note text not null default '',
 primary key(tenant_id,source_key), check(net_price>=0), check(valid_to is null or valid_from is null or valid_to>=valid_from)
);
create table private.hub_kpi_internal_receipt_reads (
 tenant_id uuid not null references public.hub_tenants(id), receipt_url text not null,
 source_hash text, supplier_key text, material_fractions text[] not null default '{}',
 receipt_quantity numeric, receipt_date date, receipt_reference text,
 read_status text not null check(read_status in ('reviewed','ocr','unreadable','not_receipt','ambiguous')),
 ocr_text text, note text not null default '', read_at timestamptz not null default now(),
 primary key(tenant_id,receipt_url)
);
alter table private.hub_kpi_internal_purchase_prices enable row level security;
alter table private.hub_kpi_internal_receipt_reads enable row level security;
revoke all on private.hub_kpi_internal_purchase_prices,private.hub_kpi_internal_receipt_reads from public,anon,authenticated;

create or replace function public.hub_kpi_internal_purchase_costs_v1(p_tenant_id uuid,p_row_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if cardinality(p_row_ids)>10000 then raise exception 'Too many rows';end if;
 with raw as materialized(
 select r.*,case when coalesce(nullif(source_data->>'Kvantitet',''),'') ~ '^-?[0-9 ]+([.,][0-9]+)?$' then replace(replace(source_data->>'Kvantitet',' ',''),',','.')::numeric else quantity end effective_quantity,
 case when exists(select 1 from jsonb_array_elements(a.source_rows) e where trim(e->'values'->>'Namn') ilike 'Tippavgift%') then 'tipp_deponi' else a.revenue_category end category,
 (regexp_match(coalesce(r.source_data->>'Artikelnamn',r.description),'([0-9]+)[/-]([0-9]+)'))[1]||'-'||(regexp_match(coalesce(r.source_data->>'Artikelnamn',r.description),'([0-9]+)[/-]([0-9]+)'))[2] fraction,
 e.supplier_key receipt_supplier,e.material_fractions,e.receipt_quantity,e.receipt_date,e.receipt_reference,e.read_status,e.note receipt_note,
 -- Explicit source comments are a preliminary source hint, never a verified receipt.
 case when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'kylinge|kyllinge|johanssons' then 'KYLLINGE'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'schweden|splitt' then 'SCHWEDEN_SPLITT'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'vambåsa|vambasa' then 'VAMBASA'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'önnestad|onnestad' then 'ONNESTAD'
 when coalesce(r.source_data->>'ArtikelKommentar','') ~* 'össjö|ossjo' then 'OSSJO' end comment_supplier
 from public.kpi_import_rows r
 left join private.hub_kpi_internal_receipt_reads e on e.tenant_id=r.tenant_id and e.receipt_url=nullif(r.source_data->>'FilUrl','')
 left join lateral(select a.revenue_category,a.source_rows from public.kpi_workify_article_rules a where a.tenant_id=r.tenant_id and a.enabled and a.article_number=r.source_data->>'Artikelnummer' and a.valid_from<=r.occurred_on and (a.valid_to is null or a.valid_to>=r.occurred_on) order by a.valid_from desc,a.id limit 1)a on true
 where r.tenant_id=p_tenant_id and r.id=any(p_row_ids) and r.data_kind='revenue' and lower(trim(r.source_data->>'Kundnamn'))='elleholms maskin ab'
 ), scoped as(
 select r.*,case when cardinality(material_fractions)=1 and (material_fractions[1]=fraction or material_fractions[1]=regexp_replace(source_data->>'Artikelnummer','^[A-Za-z]+','') or (split_part(material_fractions[1],'-',1)=split_part(fraction,'-',1) and coalesce(source_data->>'Artikelnamn',description) ~ ('/'||split_part(material_fractions[1],'-',2)||'([^0-9]|$)'))) then material_fractions[1] else fraction end price_fraction,
 case when read_status in ('reviewed','ocr') and (receipt_date is null or receipt_date=occurred_on) and (cardinality(material_fractions)=0 or (cardinality(material_fractions)=1 and (material_fractions[1]=fraction or material_fractions[1]=regexp_replace(source_data->>'Artikelnummer','^[A-Za-z]+','') or (split_part(material_fractions[1],'-',1)=split_part(fraction,'-',1) and coalesce(source_data->>'Artikelnamn',description) ~ ('/'||split_part(material_fractions[1],'-',2)||'([^0-9]|$)'))))) then receipt_supplier else comment_supplier end supplier,
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
 select r.*,case when category='material' and not ambiguous_fraction then case when supplier is not null then net_price else average_price end end rate,
 case when category is distinct from 'material' then case when category='tipp_deponi' then 'missing_tipping_price' else 'not_applicable' end
 when ambiguous_fraction then 'ambiguous_material'
 when supplier is not null and net_price is not null then case when receipt_supplier=supplier and receipt_date=occurred_on and read_status='reviewed' and price_valid_from is not null then 'receipt_price_list' else 'preliminary_source' end
 when supplier is null and average_price is not null then 'average_estimate'
 else 'missing_price' end price_status
 from prices r
 ) select coalesce(jsonb_object_agg(id::text,jsonb_build_object(
 'rate',rate,'quantity',effective_quantity,'unit',lower(source_data->>'Enhet'),'amount',case when rate is not null and effective_quantity is not null then round(rate*effective_quantity,2) end,
 'margin',case when rate is not null and effective_quantity is not null and amount is not null then amount-round(rate*effective_quantity,2) end,
 'status',price_status,'supplier',supplier,'fraction',price_fraction,
 'price_source',case when supplier is not null then source_reference else 'Medelpris Johanssons / Schweden Splitt / Vambåsa' end,
 'price_sources',case when supplier is null then sources end,'price_sample_count',case when supplier is null then samples else case when net_price is null then 0 else 1 end end,
 'receipt_quantity',case when receipt_uses=1 and receipt_date=occurred_on and price_fraction=any(material_fractions) and receipt_quantity<=effective_quantity+0.01 and read_status='reviewed' then receipt_quantity end,
 'receipt_cost',case when receipt_uses=1 and receipt_date=occurred_on and price_fraction=any(material_fractions) and receipt_quantity<=effective_quantity+0.01 and read_status='reviewed' and rate is not null then round(receipt_quantity*rate,2) end,
 'receipt_reference',receipt_reference,'receipt_read_status',coalesce(read_status,case when nullif(source_data->>'FilUrl','') is null then 'missing_receipt' else 'not_read' end),
 'note',concat_ws('; ',receipt_note,price_note,case when receipt_uses>1 then 'Bilagan delas av flera rader; kvittomängden kräver fördelning' end,case when receipt_date is not null and receipt_date<>occurred_on then 'Kvittodatum skiljer sig från transaktionsdatum' end,
 case when rate is not null and effective_quantity is null then 'Mängd saknas' end)
 )),'{}'::jsonb) into result from selected;
 return result;
end $fn$;
revoke all on function public.hub_kpi_internal_purchase_costs_v1(uuid,uuid[]) from public,anon;
grant execute on function public.hub_kpi_internal_purchase_costs_v1(uuid,uuid[]) to authenticated;

create or replace function public.hub_kpi_internal_transfers_with_purchase_v1(p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
declare base jsonb; costs jsonb; enriched jsonb;
begin
 base:=public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months);
 costs:=public.hub_kpi_internal_purchase_costs_v1(p_tenant_id,array(select (r->>'row_id')::uuid from jsonb_array_elements(base->'rows')r));
 select coalesce(jsonb_agg(r||jsonb_build_object('purchase',costs->(r->>'row_id'))),'[]'::jsonb) into enriched from jsonb_array_elements(base->'rows')r;
 return base||jsonb_build_object('rows',enriched,'purchase_basis','Inköp beräknas i Hubben från kvitto/täkt och daterad nettoprislista. Okänd täkt: preliminärt medelpris för samma fraktion från Johanssons, Schweden Splitt och Vambåsa. Transportkostnad och tippkostnad utan separat prisunderlag lämnas tomma. Originalintäkter och omföringsstatus ändras inte.');
end $fn$;
revoke all on function public.hub_kpi_internal_transfers_with_purchase_v1(uuid,date,date,integer[]) from public,anon;
grant execute on function public.hub_kpi_internal_transfers_with_purchase_v1(uuid,date,date,integer[]) to authenticated;
