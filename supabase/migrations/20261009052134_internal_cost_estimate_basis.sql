CREATE OR REPLACE FUNCTION public.hub_kpi_internal_transfers_with_purchase_v1(p_tenant_id uuid, p_from date, p_to date, p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET statement_timeout TO '45s'
AS $function$
declare base jsonb; costs jsonb; enriched jsonb;
begin
 base:=public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months);
 costs:=public.hub_kpi_internal_purchase_costs_v1(p_tenant_id,array(select (r->>'row_id')::uuid from jsonb_array_elements(base->'rows')r));
 select coalesce(jsonb_agg(r||jsonb_build_object('purchase',costs->(r->>'row_id'))),'[]'::jsonb) into enriched from jsonb_array_elements(base->'rows')r;
 return base||jsonb_build_object('rows',enriched,'purchase_basis','Material: säkra inköpspriser behålls; osäkra rader inkluderas med tydligt märkt överslag från Johanssons/Kylinge, Schweden Splitt och Vambåsa. I första hand samma fraktion, annars grovt medelpris per samma enhet. Mängder gissas inte. Intern tippkostnad: 80 % av satt pris. Transport räknas separat. Originalintäkter och omföringsstatus ändras inte.');
end $function$;

notify pgrst,'reload schema';

