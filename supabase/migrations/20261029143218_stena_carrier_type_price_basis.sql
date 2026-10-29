alter table private.hub_stena_rows_v1 add column load_carrier_type text,add column previous_amount numeric;
create function private.hub_stena_price_basis_v1(p_type text,p_count numeric)returns text
language sql immutable set search_path='' as $$
select case
when coalesce(p_type,'')~*'pall|ibc|berglöfslåda|(^|[^a-z])fat([^a-z]|$)|dunk|batterilåda|plastlåda|säck|recytainer|lock' then 'line_total'
when coalesce(p_type,'')~*'flak|container|komprimator|^Egen Lastb - 8 kbm$' then 'per_load_carrier'
when p_count=1 then 'line_total_single'
else 'needs_review' end
$$;
create function private.hub_stena_amount_v2(p_kind text,p_price numeric,p_extra numeric,p_count numeric,p_settled numeric,p_type text)returns numeric
language sql immutable set search_path='' as $$
select case when p_kind='settled' then round(p_settled,2)
when p_price is null then null
when p_price+coalesce(p_extra,0)=0 then 0
when private.hub_stena_price_basis_v1(p_type,p_count)in('line_total','line_total_single')then round(p_price+coalesce(p_extra,0),2)
when private.hub_stena_price_basis_v1(p_type,p_count)='per_load_carrier'and p_count is not null then round((p_price+coalesce(p_extra,0))*p_count,2)
else null end
$$;
revoke all on function private.hub_stena_price_basis_v1(text,numeric),private.hub_stena_amount_v2(text,numeric,numeric,numeric,numeric,text)from public,anon,authenticated;
do $migration$
declare definition text;
begin
select pg_get_functiondef('private.hub_stena_ingest_v1(uuid,text,jsonb)'::regprocedure)into definition;
definition:=replace(definition,'load_count,settled_amount,amount)','load_count,settled_amount,amount,load_carrier_type)');
definition:=replace(definition,$old$case when f.source_kind='settled' then round(r.settled_amount,2)
 when r.price is null then null
 when coalesce(r.price,0)+coalesce(r.extra,0)=0 then 0
 when r.load_count is null then null else round((r.price+coalesce(r.extra,0))*r.load_count,2)end$old$,$new$private.hub_stena_amount_v2(f.source_kind,r.price,r.extra,r.load_count,r.settled_amount,r.load_carrier_type),r.load_carrier_type$new$);
definition:=replace(definition,'settled_amount numeric)','settled_amount numeric,load_carrier_type text)');
if position('r.load_carrier_type'in definition)=0 then raise exception 'Ingest anchor missing';end if;
execute definition;
select pg_get_functiondef('private.hub_apply_stena_priority_v1(uuid,uuid)'::regprocedure)into definition;
definition:=replace(definition,$old$'load_count',s.load_count,$old$,$new$'load_count',s.load_count,'load_carrier_type',s.load_carrier_type,'price_basis',case when s.source_kind='settled'then 'settled_line_total'else private.hub_stena_price_basis_v1(s.load_carrier_type,s.load_count)end,'previous_amount',s.previous_amount,$new$);
execute definition;
end $migration$;