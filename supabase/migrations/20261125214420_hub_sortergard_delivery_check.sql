create or replace function private.hub_sortergard_delivery_check(p_tenant uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null or public.hub_has_permission(p_tenant, 'kpi.manage') is not true then
    raise exception 'Behörighet saknas' using errcode = '42501';
  end if;

  return (
    with weighings as materialized (
      select e.id, e.occurred_at, (e.occurred_at at time zone 'Europe/Stockholm')::date as day,
        e.ticket_number, e.source_record_id, e.vehicle_registration, e.net_weight_kg / 1000.0 as tonnes,
        e.material_code, e.material_name, nullif(upper(btrim(e.order_reference)), '') as order_number
      from public.hub_weighing_events e
      where e.tenant_id = p_tenant and e.direction = 'out'
        and e.measurement_status is distinct from 'void' and e.net_weight_kg > 0
        and e.occurred_at >= timestamp '2026-09-01' at time zone 'Europe/Stockholm'
    ), deliveries as (
      select order_number, max(day) as last_day, min(day) as first_day,
        sum(tonnes) as weighed_tonnes, count(*) as load_count,
        string_agg(distinct vehicle_registration, ', ' order by vehicle_registration) as vehicles,
        string_agg(distinct material_name, ', ' order by material_name) as materials,
        count(distinct coalesce(material_name, material_code)) as material_count,
        min(nullif(lower(btrim(material_name)),'')) as material_key,
        count(distinct nullif(lower(btrim(material_code)),'')) as material_code_count,
        min(nullif(lower(btrim(material_code)),'')) as material_code_key,
        jsonb_agg(to_jsonb(w) - 'order_number' - 'occurred_at' order by occurred_at, id) as tickets
      from weighings w
      group by order_number, case when order_number is null then id end
    ), order_rows as (
      select r.id, d.order_number, r.row_number, r.occurred_on as day, b.file_name,
        r.source_data->>'Kundnamn' as customer, coalesce(nullif(r.source_data->>'Artikelnamn',''),r.description) as article,
        nullif(btrim(r.source_data->>'Artikelnummer'),'') as article_code,
        lower(btrim(r.source_data->>'Enhet')) as unit, r.currency, r.amount,
        case when val.quantity ~ '^-?[0-9]{1,12}(\.[0-9]{1,8})?$' then val.quantity::numeric else r.quantity end as quantity,
        case when val.price ~ '^-?[0-9]{1,12}(\.[0-9]{1,8})?$' then val.price::numeric end as price,
        nullif(btrim(case when latest.source_data ? 'Fakturerad' then latest.source_data->>'Fakturerad'
          else r.source_data->>'Fakturerad' end),'') as billed_value
      from deliveries d
      join public.kpi_import_rows r on r.tenant_id = p_tenant
        and upper(btrim(r.source_data->>'Ordernummer')) = d.order_number
      join public.kpi_import_batches b on b.id = r.batch_id and b.tenant_id = p_tenant
      left join lateral (
        select o.source_data from private.hub_workify_row_observations o
        where o.tenant_id = p_tenant and o.canonical_row_id = r.id and o.decision in ('insert','duplicate')
        order by o.observed_at desc, o.batch_id desc, o.row_number desc limit 1
      ) latest on true
      cross join lateral (
        select replace(regexp_replace(r.source_data->>'Kvantitet', '[[:space:] ]', '', 'g'), ',', '.') as quantity,
          replace(regexp_replace(r.source_data->>'Kundpris', '[[:space:] ]', '', 'g'), ',', '.') as price
      ) val
      where r.is_valid and r.data_kind = 'revenue' and b.status in ('completed','needs_review')
        and (r.source_system = 'workify_file' or
          (r.source_system is null and r.source_data ?& array['Ordernummer','Artikelnummer','Artikeldatum']))
    ), lines as (
      select *, unit in ('ton','t') as is_ton,
        case
          when billed_value ~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}([ T].*)?$'
            or lower(billed_value) in ('ja','true','1','fakturerad') then true
          when lower(billed_value) in ('nej','false','0','ej fakturerad') then false
          else null
        end as billed
      from order_rows
    ), orders as (
      select order_number, string_agg(distinct customer, ', ' order by customer) as customers,
        count(*) as line_count, count(distinct nullif(lower(btrim(customer)),'')) as customer_count,
        min(day) filter (where is_ton) as first_ton_day, max(day) filter (where is_ton) as last_ton_day,
        count(*) filter (where is_ton) as ton_lines,
        count(*) filter (where is_ton and quantity > 0) as positive_ton_lines,
        count(distinct coalesce(article_code, nullif(lower(btrim(article)),''))) filter (where is_ton) as ton_articles,
        sum(quantity) filter (where is_ton) as order_tonnes,
        count(distinct regexp_replace(lower(btrim(article)), '^försäljning +', '')) filter (where is_ton) as ton_article_names,
        min(regexp_replace(lower(btrim(article)), '^försäljning +', '')) filter (where is_ton) as ton_article_key,
        min(lower(article_code)) filter (where is_ton) as ton_article_code,
        count(*) filter (where is_ton and price > 0 and currency = 'SEK') as sek_priced_lines,
        min(price) filter (where is_ton) as min_price, max(price) filter (where is_ton) as max_price,
        count(*) filter (where billed) as billed_lines, count(*) filter (where billed is false) as unbilled_lines,
        jsonb_agg(to_jsonb(l) - 'id' - 'order_number' - 'billed_value' order by day, row_number, id) as workify_lines
      from lines l
      group by order_number
    ), comparison as (
      select d.*, o.customers, o.workify_lines,
        case
          when o.line_count is null then 'missing_order'
          when o.billed_lines = o.line_count then 'billed'
          when o.unbilled_lines = o.line_count then 'unbilled'
          when o.billed_lines > 0 then 'partial'
          else 'unknown'
        end as billing_status,
        case
          when d.order_number is null then 'missing_reference'
          when o.line_count is null then 'missing_order'
          when o.ton_lines = 0 then 'no_ton_lines'
          when d.material_count <> 1 or o.ton_articles <> 1 or o.positive_ton_lines <> o.ton_lines
            or o.customer_count > 1 or o.first_ton_day is null
            or d.first_day < o.first_ton_day - 7 or d.last_day > o.last_ton_day + 7 then 'multiple_or_incomplete'
          when (o.ton_article_names = 1 and d.material_key = o.ton_article_key) is not true
            and (d.material_code_count = 1 and d.material_code_key = o.ton_article_code) is not true then 'material_mismatch'
          when exists (
            select 1 from public.hub_weighing_events e
            where e.tenant_id = p_tenant and upper(btrim(e.order_reference)) = d.order_number
              and e.measurement_status is distinct from 'void' and (
                e.direction = 'in' or (e.direction = 'out'
                  and e.occurred_at < timestamp '2026-09-01' at time zone 'Europe/Stockholm')
              )
          ) then 'multiple_or_incomplete'
          else 'comparable'
        end as comparison_status,
        case when o.ton_articles = 1 and o.positive_ton_lines = o.ton_lines then o.order_tonnes end as order_tonnes,
        case when o.min_price = o.max_price and o.sek_priced_lines = o.ton_lines then o.min_price end as price
      from deliveries d left join orders o using (order_number)
    ), results as (
      select c.*,
        case when comparison_status = 'comparable' then round(weighed_tonnes - order_tonnes, 3) end as difference_tonnes,
        case when comparison_status = 'comparable' then round((weighed_tonnes - order_tonnes) * price, 2) end as indicative_sek
      from comparison c
    )
    select coalesce(jsonb_agg((to_jsonb(r) - 'material_count' - 'material_key' - 'material_code_count'
      - 'material_code_key' - 'price') order by last_day desc, order_number nulls last, tickets->0->>'id'), '[]'::jsonb)
    from results r
  );
end;
$$;

revoke all on function private.hub_sortergard_delivery_check(uuid) from public, anon, authenticated;
grant execute on function private.hub_sortergard_delivery_check(uuid) to authenticated;

create or replace function public.hub_sortergard_delivery_check(p_tenant uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.hub_sortergard_delivery_check(p_tenant) $$;
revoke all on function public.hub_sortergard_delivery_check(uuid) from public, anon, authenticated;
grant execute on function public.hub_sortergard_delivery_check(uuid) to authenticated;
