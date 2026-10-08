-- User-confirmed Workify customer policy. Preserve original source names and IDs.
create or replace function private.hub_workify_customer_is_internal_v1(p_name text)
returns boolean language sql immutable security invoker set search_path=pg_catalog as $$
 select lower(regexp_replace(btrim(coalesce(p_name,'')), '[[:space:]]+', ' ', 'g')) ~ '^elleholms maskin'
 and lower(regexp_replace(btrim(coalesce(p_name,'')), '[[:space:]]+', ' ', 'g')) <> 'elleholms maskin (stena)'
$$;
revoke all on function private.hub_workify_customer_is_internal_v1(text) from public,anon,authenticated;
do $$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_payment_outcome_source_v1(uuid,date)'::regprocedure);
 needle:=$needle$coalesce(f.original->>'Kundnamn','')~*'^elleholms[[:space:]]+maskin'$needle$;
 if position(needle in definition)=0 then raise exception 'Payment source customer classification changed';end if;
 execute replace(definition,needle,$replacement$private.hub_workify_customer_is_internal_v1(f.original->>'Kundnamn')$replacement$);
 definition:=pg_get_functiondef('private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer)'::regprocedure);
 needle:=$needle$coalesce(customer_name,'')~*'elleholms[[:space:]]+maskin'$needle$;
 if position(needle in definition)=0 then raise exception 'Invoice customer classification changed';end if;
 execute replace(definition,needle,'private.hub_workify_customer_is_internal_v1(customer_name)');
end $$;
notify pgrst,'reload schema';
