-- The existing canonical Övrigt collection also contains unresolved time.
-- Preserve an explicit unresolved-hour count so this is grouping, not a guessed identity.
do $migration$
declare d text;needle text:='coalesce(case when rel.n=1 then rel.unit_id end,r.source_unit) unit_id';
begin
 d:=pg_get_functiondef('private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected NEXT time unit projection';end if;
 d:=replace(d,needle,'coalesce(case when rel.n=1 then rel.unit_id end,r.source_unit,(select (array_agg(o.id))[1]from public.hub_objects o where o.tenant_id=p_tenant and o.object_type=''EconomicUnit''and o.data->>''report_fallback''=''unresolved''having count(*)=1)) unit_id');
 d:=replace(d,'from valid_work where unit_id is null','from valid_work where source_unit is null');
 execute d;
end $migration$;
