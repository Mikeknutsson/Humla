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
  with loads as materialized (
   select x.sheet, x.row, x.date, x."order", x.article, x.fraction, x.kg,
    regexp_replace(lower(btrim(x.quarry)), '[^a-zåäö]', '', 'g') as quarry,
    lower(regexp_replace(btrim(x.article), '[[:space:]]+', ' ', 'g')) as article_key
   from jsonb_to_recordset(p_loads) as x(sheet text, row integer, "order" text, date date, quarry text, article text, fraction text, kg integer)
  ), order_numbers as materialized (
   select distinct "order" from loads where "order" ~ '^[0-9]+$'
  ), workify as materialized (
   -- Keep Workify import evidence even when a material line has zero revenue.
   select distinct n."order", btrim(coalesce(nullif(r.source_data->>'Artikelnamn',''),r.description,'')) as article,
    r.occurred_on as delivery_date, r.quantity, r.amount,
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
  )
  select coalesce(jsonb_agg(jsonb_build_object(
   'sheet', l.sheet, 'row', l.row,
   'match', case when l."order" !~ '^[0-9]+$' then 'order_unspecified' when w.matched then 'matched' when w.equivalent then 'equivalent'
    when w.line_count = 0 then 'order_missing' else 'article_missing' end,
   'workify_articles', coalesce(w.matches, w.materials, '[]'::jsonb),
   'workify_rates', coalesce(w.rates, array[]::numeric[]),
   'workify_registrations', coalesce(w.registrations, array[]::text[]),
   'rate', coalesce(project_price.net_price, standard_price.net_price),
   'amount', round(l.kg * coalesce(project_price.net_price, standard_price.net_price) / 1000, 2),
   'price_source', coalesce(project_price.source_reference, standard_price.source_reference)
  ) order by l.sheet,l.row), '[]'::jsonb)
  from loads l
  cross join lateral (
   select count(*) as line_count, bool_or(t.matches) as matched,
    bool_or(t.equivalent) as equivalent,
    array_agg(distinct t.rate order by t.rate) filter (where t.rate is not null) as rates,
    -- LASTBIL is the Workify registration for hired trucks.
    array_agg(distinct t.registration order by t.registration)
     filter (where t.registration = 'LASTBIL' or (t.registration ~ '[A-Z]' and t.registration ~ '[0-9]')) as registrations,
    jsonb_agg(distinct t.display order by t.display) filter (where t.matches or t.equivalent) as matches,
    jsonb_agg(distinct t.display order by t.display) filter (where t.size is not null and t.article !~* 'lastvikt|ekipage|lastbil|enkelbil') as materials,
    case when count(distinct (t.customer,t.littra)) = 1 then min(t.customer) end as customer,
    case when count(distinct (t.customer,t.littra)) = 1 then min(t.littra) end as littra
   from (
    select w.*,
     case when w.delivery_date=l.date and w.unit='ton' and w.quantity=l.kg::numeric/1000
       and w.amount<>0 and w.quantity<>0 and regexp_replace(lower(w.article),'[^a-zåäö0-9]','','g')
        = regexp_replace(l.article_key,'[^a-zåäö0-9]','','g')
      then round(w.amount/nullif(w.quantity,0),2) end as rate,
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
