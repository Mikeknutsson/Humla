-- A fraction average must include all three agreed quarries. Never silently
-- substitute a two-quarry average when one price is missing.
do $$ declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_separate_material_v1(uuid,uuid)'::regprocedure);
 needle:='if bundled and (part is null or (part<>0 and sign(part)<>sign(f.amount))) then';
 if position(needle in definition)=0 then raise exception 'Unexpected material price guard';end if;
 definition:=replace(definition,needle,
 'if bundled and (part is null or (part<>0 and sign(part)<>sign(f.amount)) or (evidence->>''status''=''average_estimate'' and coalesce((evidence->>''price_sample_count'')::int,0)<>3)) then');
 definition:=replace(definition,'coalesce(evidence->>''status'',''missing_purchase_price'')',
 'case when evidence->>''status''=''average_estimate'' and coalesce((evidence->>''price_sample_count'')::int,0)<>3 then ''insufficient_quarry_prices'' else coalesce(evidence->>''status'',''missing_purchase_price'') end');
 execute definition;
end $$;
