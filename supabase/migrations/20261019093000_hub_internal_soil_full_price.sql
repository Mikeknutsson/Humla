-- Approved exception: Matjord retains full internal debited price.
do $patch$
declare definition text; old_clause text; new_clause text;
begin
 definition:=pg_get_functiondef('private.hub_internal_economy_rows_v1(jsonb)'::regprocedure);
 old_clause:=$old$jsonb_build_object('status','missing_own_material_self_cost','price_source','Fastställd självkostnad för matjord saknas. Ange kostnad per ton i Hubben.')$old$;
 new_clause:=$new$jsonb_build_object(
  'status','internal_price_full','price_source','Matjord: fullt debiteringsbelopp enligt godkänd internregel.',
  'amount',round((r->>'amount')::numeric-case when coalesce((r->>'bundle')::boolean,false)then(r->>'bundle_transport')::numeric else 0 end,2),
  'quantity',(r->>'quantity')::numeric,
  'rate',round(((r->>'amount')::numeric-case when coalesce((r->>'bundle')::boolean,false)then(r->>'bundle_transport')::numeric else 0 end)/nullif((r->>'quantity')::numeric,0),4))$new$;
 if position(old_clause in definition)=0 then raise exception 'Expected Matjord rule missing';end if;
 definition:=replace(definition,old_clause,new_clause);
 definition:=replace(definition,'purchase->>''status''is distinct from''receipt_price_list''','coalesce(purchase->>''status'','''')not in(''receipt_price_list'',''internal_price_full'')');
 execute definition;
 definition:=pg_get_functiondef('public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])'::regprocedure);
 definition:=replace(definition,'Material värderas till Hubben-beräknad självkostnad utan materialpåslag.','Material värderas till Hubben-beräknad självkostnad utan materialpåslag, utom matjord som behåller fullt debiteringspris.');
 execute definition;
end $patch$;
notify pgrst,'reload schema';
