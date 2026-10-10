-- Read-only projection. No ownership, source evidence, ledger or KPI facts are changed.
create function private.hub_register_depreciation_v1(p_evidence jsonb,p_as_of date,p_kind text,p_sold boolean)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare bought date; cost numeric; years numeric; months integer; ends date; days integer; elapsed integer; depreciation numeric;
begin
 if p_sold or p_kind<>'asset' then return jsonb_build_object('status','excluded','reason','Sålt, tillbehör eller gemensamt inköp');end if;
 bought:=(p_evidence->>'purchase_date')::date;cost:=(p_evidence->>'purchase_cost')::numeric;years:=(p_evidence->>'useful_life_years')::numeric;
 if bought is null or cost is null or cost<=0 or years is null or years<=0 or years>100 then return jsonb_build_object('status','missing','reason','Inköpsdatum, positivt inköpsbelopp eller avskrivningstid saknas');end if;
 if p_as_of is null or p_as_of<bought then return jsonb_build_object('status','before_purchase','reason','Valt datum är före inköpet');end if;
 months:=round(years*12)::integer;
 if months<1 then return jsonb_build_object('status','missing','reason','Avskrivningstiden är för kort');end if;
 ends:=(bought+make_interval(months=>months))::date;days:=ends-bought;elapsed:=least(p_as_of-bought,days);
 depreciation:=round(cost*elapsed/days,2);
 return jsonb_build_object('status','calculated','method','linear_to_zero_daily','as_of',p_as_of,'purchase_date',bought,'end_date',ends,'elapsed_days',p_as_of-bought,'depreciated_days',elapsed,'total_days',days,'purchase_cost',cost,'monthly_rate',round(cost/months,2),'depreciation',depreciation,'remaining_value',cost-depreciation,'fully_depreciated',p_as_of>=ends);
end $$;

create function public.hub_asset_register_projection_v1(p_tenant uuid,p_as_of date,p_asset uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare report jsonb; rows jsonb;
begin
 if p_as_of is null or p_as_of>(now() at time zone 'Europe/Stockholm')::date then raise exception 'Ogiltigt beräkningsdatum' using errcode='22023';end if;
 -- Existing RPC enforces authenticated tenant membership and fleet.read.
 report:=private.hub_asset_register_v1(p_tenant,p_asset);
 select coalesce(jsonb_agg(r||jsonb_build_object('projection',private.hub_register_depreciation_v1(r->'evidence',p_as_of,r->>'link_kind',(r->>'sold')::boolean)) order by r->>'source_key'),'[]'::jsonb) into rows from jsonb_array_elements(report->'rows') r;
 return jsonb_set(report||jsonb_build_object('as_of',p_as_of),'{rows}',rows);
end $$;
revoke all on function private.hub_register_depreciation_v1(jsonb,date,text,boolean),public.hub_asset_register_projection_v1(uuid,date,uuid) from public,anon;
grant execute on function private.hub_register_depreciation_v1(jsonb,date,text,boolean),public.hub_asset_register_projection_v1(uuid,date,uuid) to authenticated;
