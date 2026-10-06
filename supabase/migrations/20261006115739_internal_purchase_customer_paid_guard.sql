-- Purchases explicitly charged to the customer need an ownership decision.
-- Special products must not silently use a standard-fraction price.
DO $migration$
DECLARE definition text;
BEGIN
 definition:=pg_get_functiondef('public.hub_kpi_internal_purchase_costs_v1(uuid,uuid[])'::regprocedure);
 IF strpos(definition,$old$case when category='material' and not ambiguous_fraction then$old$)=0 THEN
  RAISE EXCEPTION 'Unexpected purchase reader; review customer-paid guard';
 END IF;
 definition:=replace(definition,
 $old$case when category='material' and not ambiguous_fraction then$old$,
 $new$case when category='material' and not ambiguous_fraction
 and coalesce(source_data->>'Artikelnamn',description,'') !~* 'uttaget.*kund|tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus' then$new$);
 definition:=replace(definition,
 $old$case when category is distinct from 'material' then$old$,
 $new$case when category='material' and coalesce(source_data->>'Artikelnamn',description,'') ~* 'uttaget.*kund' then 'customer_paid_review'
 when category='material' and coalesce(source_data->>'Artikelnamn',description,'') ~* 'tvättad|torr|ridbana|sandlåda|murgrus|kabelsand|rörgrus' then 'special_material_review'
 when category is distinct from 'material' then$new$);
 EXECUTE definition;
END $migration$;
