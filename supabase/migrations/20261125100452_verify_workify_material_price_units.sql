alter table public.hub_workify_standard_material_prices
  add column unit_verified boolean not null default false;

with evidence as (
  select p.tenant_id,p.article_number,
    bool_or(e.unit='ton') as has_ton,
    bool_or(e.unit is not null and e.unit<>'ton') as has_other_unit,
    bool_or(e.unit='ton' and case when e.unit_price ~ '^[0-9]+(\.[0-9]+)?$'
      then e.unit_price::numeric=p.price else false end) as same_ton_price
  from public.hub_workify_standard_material_prices p
  join public.kpi_import_rows r on r.tenant_id=p.tenant_id and btrim(r.source_data->>'Artikelnummer')=p.article_number
  cross join lateral (select nullif(lower(btrim(r.source_data->>'Enhet')),'') as unit,
    replace(btrim(r.source_data->>'Kundpris'),',','.') as unit_price) e
  where r.is_valid and (r.source_system='workify_file' or r.source_system is null)
  group by p.tenant_id,p.article_number
)
update public.hub_workify_standard_material_prices p set unit_verified=true
from evidence e where p.tenant_id=e.tenant_id and p.article_number=e.article_number
  and e.has_ton and (not e.has_other_unit or e.same_ton_price);
