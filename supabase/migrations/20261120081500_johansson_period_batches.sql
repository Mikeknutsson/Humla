create or replace function public.hub_johansson_material_control(p_tenant uuid, p_loads jsonb)
returns jsonb
language plpgsql stable security definer
set search_path = ''
set statement_timeout = '15s'
set jit = 'off'
as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant, 'kpi.manage') then
  raise exception 'Access denied' using errcode = '42501';
 end if;
 if jsonb_typeof(p_loads) is distinct from 'array' or jsonb_array_length(p_loads) > 3000 then
  raise exception 'Invalid material workbook' using errcode = '22023';
 end if;

 return (
  with material_names as (
   select '(stenmjöl|matjord|makadam|bergkross|bärlager|slitlager|förstärkningslager)' as pattern
  ), loads as materialized (
   select x.sheet, x.row, x.date, x."order", x.article, x.fraction, x.kg, x.ticket,
    regexp_replace(lower(btrim(x.quarry)), '[^a-zåäö]', '', 'g') as quarry,
    lower(regexp_replace(btrim(x.article), '[[:space:]]+', ' ', 'g')) as article_key,
    case (regexp_match(lower(x.article),pattern))[1]
     when 'bärlager' then 'bergkross' when 'slitlager' then 'bergkross'
     when 'förstärkningslager' then 'bergkross'
     else (regexp_match(lower(x.article),pattern))[1] end as material_kind
   from jsonb_to_recordset(p_loads) as x(sheet text, row integer, "order" text, date date, quarry text, article text, fraction text, kg integer, ticket text) cross join material_names
  ), order_numbers as materialized (
   select distinct "order" from loads where "order" ~ '^[0-9]+$'
  ), workify as materialized (
   -- Keep Workify import evidence even when a material line has zero revenue.
   select distinct n."order", btrim(coalesce(nullif(r.source_data->>'Artikelnamn',''),r.description,'')) as article,
    r.occurred_on as delivery_date, coalesce(r.quantity,
     case when btrim(r.source_data->>'Kvantitet') ~ '^-?[0-9]+([,.][0-9]+)?$'
      then replace(btrim(r.source_data->>'Kvantitet'),',','.')::numeric end) as quantity, r.amount,
    lower(btrim(r.source_data->>'Enhet')) as unit,
    btrim(r.source_data->>'Artikelnummer') as article_number,
    btrim(r.source_data->>'Kundnamn') as customer,
    btrim(r.source_data->>'Littranummer') as littra,
    case when reg.value in ('INHYRDLASTBIL','INHYRDALASTBILAR') then 'LASTBIL' else reg.value end as registration,
    (regexp_match(coalesce(nullif(r.source_data->>'Artikelnamn',''),r.description,''), '(?<![0-9/-])([0-9]+)[[:space:]]*[/–-][[:space:]]*([0-9]+)(?![0-9/-])')) as size
   from public.kpi_import_rows r join order_numbers n on n."order" = btrim(r.source_data->>'Ordernummer')
   cross join lateral (select upper(regexp_replace(r.source_data->>'RegNr', '[^A-Za-z0-9]', '', 'g')) as value) reg
   where r.tenant_id = p_tenant and r.data_kind = 'revenue' and r.is_valid
    and (r.source_system = 'workify_file' or r.source_system is null)
  ), receipt_evidence as (
   select distinct n."order",e.receipt_url,e.receipt_reference,e.receipt_date,e.material_fractions
   from public.kpi_import_rows r join order_numbers n on n."order"=btrim(r.source_data->>'Ordernummer')
   join private.hub_kpi_internal_receipt_reads e on e.tenant_id=r.tenant_id
    and e.receipt_url=nullif(r.source_data->>'FilUrl','')
   where r.tenant_id=p_tenant and r.data_kind='revenue' and r.is_valid
    and (r.source_system='workify_file' or r.source_system is null)
    and e.read_status in ('ocr','reviewed') and e.supplier_key='KYLLINGE'
  ), supplier_groups as (
   select "order", fraction, date as batch_date, sum(kg) as kg, count(*) as load_count,
    min(date) as first_date,max(date) as last_date,
    case when count(material_kind)=count(*) and count(distinct material_kind)=1 then min(material_kind) end as material_kind,
    case when count(distinct regexp_replace(article_key,'[^a-zåäö0-9]','','g'))=1
     then min(regexp_replace(article_key,'[^a-zåäö0-9]','','g')) end as normalized_article
   from loads where fraction<>'' and "order" ~ '^[0-9]+$'
   group by grouping sets (("order",fraction),("order",fraction,date)) having count(*)>1 and bool_and(kg>0)
  ), workify_lines as (
   select distinct w."order",concat_ws('-',w.size[1],w.size[2]) as fraction,
    w.delivery_date,w.article_number,w.article,w.quantity,w.amount,
    case (regexp_match(lower(w.article),pattern))[1]
     when 'bärlager' then 'bergkross' when 'slitlager' then 'bergkross'
     when 'förstärkningslager' then 'bergkross'
     else (regexp_match(lower(w.article),pattern))[1] end as material_kind
   from workify w cross join material_names
   where w.unit='ton' and w.quantity is not null
    and w.article !~* 'tipp|deponi|uttaget.*kund|lastvikt|ekipage|lastbil|enkelbil'
  ), combined_candidates as (
   select g."order",g.fraction,g.batch_date,g.kg,g.load_count,w.quantity*1000 as workify_kg,
    w.delivery_date,w.article_number,w.article,w.quantity,w.amount,g.first_date,g.last_date,
    case when w.quantity=g.kg::numeric/1000 and w.amount>0
     then round(w.amount/nullif(w.quantity,0),2) end as rate,
    count(*) over (partition by g."order",g.fraction,g.batch_date) as line_count
   from supplier_groups g join workify_lines w using ("order",fraction)
   where (g.batch_date is null or w.delivery_date=g.batch_date) and (
    g.normalized_article=regexp_replace(lower(w.article),'[^a-zåäö0-9]','','g')
    or (g.material_kind=w.material_kind
     and w.article !~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus'
     and not exists (select 1 from loads l where l."order"=g."order" and l.fraction=g.fraction
      and (g.batch_date is null or l.date=g.batch_date) and l.article ~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus'))
   )
  ), period_totals as (
   select "order",fraction,kg,load_count,first_date,last_date,sum(workify_kg) as workify_kg,count(*) as workify_lines,
    array_agg(distinct round(amount/nullif(quantity,0),2) order by round(amount/nullif(quantity,0),2)) as rates
   from combined_candidates where batch_date is null
   group by "order",fraction,kg,load_count,first_date,last_date
   having count(*)>1 and first_date<last_date and sum(workify_kg)=kg
    and bool_and(coalesce(quantity>0 and amount>0 and delivery_date between first_date-1 and last_date+1,false))
  ), period_days as (
   select p."order",p.fraction,days.day,sum(days.supplier_kg) as supplier_kg,sum(days.workify_kg) as workify_kg
   from period_totals p cross join lateral (
    select l.date as day,l.kg::numeric as supplier_kg,0::numeric as workify_kg
    from loads l where l."order"=p."order" and l.fraction=p.fraction
    union all
    select c.delivery_date,0::numeric,c.workify_kg from combined_candidates c
    where c."order"=p."order" and c.fraction=p.fraction and c.batch_date is null
   ) days group by p."order",p.fraction,days.day
  ), period_matches as (
   select p.*,jsonb_agg(jsonb_build_object('date',d.day,'supplier_kg',d.supplier_kg,'workify_kg',d.workify_kg)
    order by d.day) filter (where d.supplier_kg<>d.workify_kg) as day_differences
   from period_totals p join period_days d using ("order",fraction)
   group by p."order",p.fraction,p.kg,p.load_count,p.first_date,p.last_date,p.workify_kg,p.workify_lines,p.rates
   having bool_or(d.supplier_kg<>d.workify_kg)
  ), combined as (
   select c.* from combined_candidates c where c.line_count=1 and (c.batch_date is null or not exists (
    select 1 from combined_candidates whole
    where whole."order"=c."order" and whole.fraction=c.fraction and whole.batch_date is null and whole.line_count=1
   ))
  ), direct_candidates as (
   select l.sheet,l.row,w."order",w.delivery_date,w.article_number,w.article,w.quantity,w.amount,
    abs(w.delivery_date-l.date) as date_gap
   from loads l join workify_lines w on w."order"=l."order" and w.quantity=l.kg::numeric/1000
    and w.delivery_date between l.date-1 and l.date+1
   where l.kg>0 and not exists (select 1 from period_matches p where p."order"=l."order" and p.fraction=l.fraction) and not exists (
    select 1 from combined c where c."order"=l."order" and c.fraction=l.fraction
     and ((c.batch_date is null or c.batch_date=l.date)
      or ((c.delivery_date,c.article_number,c.article,c.quantity,c.amount)
       is not distinct from (w.delivery_date,w.article_number,w.article,w.quantity,w.amount)))
   ) and (
    regexp_replace(lower(w.article),'[^a-zåäö0-9]','','g')=regexp_replace(l.article_key,'[^a-zåäö0-9]','','g')
    or (l.fraction<>'' and l.fraction=w.fraction and l.material_kind=w.material_kind
     and concat_ws(' ',l.article,w.article) !~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus')
   )
  ), direct_ranked as (
   select d.*,
    rank() over (partition by sheet,row order by date_gap) as supplier_rank,
    rank() over (partition by "order",delivery_date,article_number,article,quantity,amount order by date_gap) as workify_rank,
    count(*) over (partition by sheet,row,date_gap) as supplier_count,
    count(*) over (partition by "order",delivery_date,article_number,article,quantity,amount,date_gap) as workify_count
   from direct_candidates d
  ), direct_matches as (
   select sheet,row,delivery_date,round(amount/nullif(quantity,0),2) as rate
   from direct_ranked
   where supplier_rank=1 and workify_rank=1 and supplier_count=1 and workify_count=1 and amount>0

  )
  select coalesce(jsonb_agg(jsonb_build_object(
   'sheet', l.sheet, 'row', l.row,
   'match', case when l."order" !~ '^[0-9]+$' then 'order_unspecified' when w.matched then 'matched' when w.equivalent then 'equivalent'
    when w.line_count = 0 then 'order_missing' else 'article_missing' end,
   'workify_articles', coalesce(w.matches, w.materials, '[]'::jsonb),
   'workify_rates', case when p.load_count is not null then p.rates when c.load_count is null then case when d.rate is null then array[]::numeric[] else array[d.rate] end
    when c.rate is null then array[]::numeric[] else array[c.rate] end,
   'workify_article_date',case when c.load_count is null then d.delivery_date end,
   'workify_receipts', coalesce(receipts.evidence,'[]'::jsonb),
   'workify_period', case when p.load_count is not null then jsonb_build_object(
    'kg',p.kg,'workify_kg',p.workify_kg,'load_count',p.load_count,
    'workify_lines',p.workify_lines,'days',p.day_differences) end,
   'workify_combined', case when p.load_count is null and c.load_count is not null
    then jsonb_build_object('kg',c.kg,'workify_kg',c.workify_kg,'load_count',c.load_count,'date',c.batch_date) end,
   'workify_registrations', coalesce(w.registrations, array[]::text[]),
   'rate', coalesce(project_price.net_price, standard_price.net_price),
   'amount', round(l.kg * coalesce(project_price.net_price, standard_price.net_price) / 1000, 2),
   'price_source', coalesce(project_price.source_reference, standard_price.source_reference)
  ) order by l.sheet,l.row), '[]'::jsonb)
  from loads l
  left join period_matches p on p."order"=l."order" and p.fraction=l.fraction
  left join direct_matches d on d.sheet=l.sheet and d.row=l.row
  left join combined c on c."order"=l."order" and c.fraction=l.fraction and (c.batch_date is null or c.batch_date=l.date)
  left join lateral (
   select jsonb_agg(distinct jsonb_build_object('reference',e.receipt_reference,'date',e.receipt_date)) as evidence
   from receipt_evidence e where e."order"=l."order" and l.quarry in ('kylinge','kyllinge')
    and l.fraction=any(e.material_fractions)
    and (e.receipt_date=l.date or (l.ticket<>'' and e.receipt_reference=l.ticket))
  ) receipts on true
  cross join lateral (
   select count(*) as line_count, bool_or(t.matches) as matched,
    bool_or(t.equivalent) as equivalent,
    -- LASTBIL is the Workify registration for hired trucks.
    array_agg(distinct t.registration order by t.registration)
     filter (where t.registration = 'LASTBIL' or (t.registration ~ '[A-Z]' and t.registration ~ '[0-9]')) as registrations,
    jsonb_agg(distinct t.display order by t.display) filter (where t.matches or t.equivalent) as matches,
    jsonb_agg(distinct t.display order by t.display) filter (where t.size is not null and t.article !~* 'lastvikt|ekipage|lastbil|enkelbil') as materials,
    case when count(distinct (t.customer,t.littra)) = 1 then min(t.customer) end as customer,
    case when count(distinct (t.customer,t.littra)) = 1 then min(t.littra) end as littra
   from (
    select w.*,
     concat_ws(' · ',nullif(w.article_number,''),nullif(w.article,'')) as display,
     (
      lower(regexp_replace(w.article,'[[:space:]]+',' ','g')) = l.article_key
      or (l.fraction <> '' and concat_ws('-',w.size[1],w.size[2]) = l.fraction
        and w.article !~* 'tipp|deponi|uttaget.*kund|tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus'
        and (l.article !~* 'makadam' or w.article !~* 'bergkross|stenmjöl|slitlager|bärlager|förstärkningslager')
        and (l.article !~* 'bergkross' or w.article !~* 'makadam|stenmjöl')
        and (l.article !~* 'matjord' or w.article !~* 'stenmjöl|makadam|bergkross|bärlager|slitlager')
        and (l.article !~* 'stenmjöl' or w.article !~* 'makadam|bergkross|bärlager|slitlager|matjord'))
     ) as matches,
     (
      l.fraction in ('4-8','5-8') and l.article ~* 'makadam' and w.article ~* 'makadam'
      and concat_ws('-',w.size[1],w.size[2]) in ('4-8','5-8')
      and w.article !~* 'tvättad|torr|uttaget.*kund'
      and l.quarry in ('kylinge','kyllinge')
      and exists (
       select 1 from private.hub_kpi_internal_purchase_prices p
       where p.tenant_id = p_tenant and p.supplier_key = 'KYLLINGE' and p.standard_material and p.unit = 'ton'
        and p.material_name ~* '4[-/]8.*eller.*5[-/]8'
        and (p.valid_from is null or p.valid_from <= l.date) and (p.valid_to is null or p.valid_to >= l.date)
      )
     ) as equivalent
    from workify w where w."order" = l."order"
   ) t
  ) w
  left join lateral (
   select p.net_price, p.source_reference from private.hub_kpi_internal_project_purchase_prices p
   where l.quarry in ('kylinge','kyllinge') and p.tenant_id = p_tenant and p.enabled
    and p.customer_name = w.customer and p.littra_number = w.littra and p.material_fraction = l.fraction
    and p.unit = 'ton' and p.valid_from <= l.date and (p.valid_to is null or p.valid_to >= l.date)
   order by p.valid_from desc,p.source_reference limit 1
  ) project_price on true
  left join lateral (
   select p.net_price, p.source_reference from private.hub_kpi_internal_purchase_prices p
   where l.quarry in ('kylinge','kyllinge') and p.tenant_id = p_tenant and p.supplier_key = 'KYLLINGE'
    and p.material_fraction = l.fraction and p.standard_material and p.unit = 'ton'
    and l.article !~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus'
    and (p.valid_from is null or p.valid_from <= l.date) and (p.valid_to is null or p.valid_to >= l.date)
   order by p.valid_from desc nulls last,p.source_key limit 1
  ) standard_price on true
 );
end
$$;

revoke all on function public.hub_johansson_material_control(uuid,jsonb) from public, anon;
grant execute on function public.hub_johansson_material_control(uuid,jsonb) to authenticated;
