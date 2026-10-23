do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_internal_economy_rows_v1(jsonb)'::regprocedure);
 definition:=replace(definition,'''estimated'',category=''material''and purchase->>''status''is distinct from''receipt_price_list''',
  '''estimated'',category=''material''and transfer_amount is not null and purchase->>''status''is distinct from''receipt_price_list''');
 execute definition;
end $patch$;
