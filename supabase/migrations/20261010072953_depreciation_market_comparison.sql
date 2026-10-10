create table private.hub_asset_market_context (
 tenant_id uuid not null references public.hub_tenants(id),asset_id uuid not null references public.hub_objects(id),
 context jsonb not null,history jsonb not null default '[]',updated_at timestamptz not null default now(),updated_by uuid not null,
 primary key(tenant_id,asset_id)
);
alter table private.hub_asset_market_context enable row level security;
revoke all on private.hub_asset_market_context from public,anon,authenticated;

create function private.hub_market_gap_v1(p_reference numeric,p_reference_basis text,p_estimate jsonb,p_market_basis text)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare median numeric; low numeric; high numeric; delta numeric; direction text; dependable boolean;
begin
 if p_reference is null then return jsonb_build_object('status','missing_reference');end if;
 if p_estimate is null or coalesce((p_estimate->>'n')::integer,0)<3 then return jsonb_build_object('status','missing_market');end if;
 if p_reference_basis is null or p_reference_basis not in ('net','gross') or p_reference_basis<>p_market_basis then return jsonb_build_object('status','basis_unconfirmed');end if;
 median:=(p_estimate->>'median')::numeric;low:=(p_estimate->>'low')::numeric;high:=(p_estimate->>'high')::numeric;
 if median is null or low is null or high is null or low<=0 or high<low or median<low or median>high then return jsonb_build_object('status','missing_market');end if;
 delta:=round(median-p_reference,2);
 dependable:=coalesce((p_estimate->>'sources')::integer,0)>=2 and high/low<=1.5;
 direction:=case when not dependable then 'weak_evidence' when p_reference=0 then 'fully_depreciated'
 when median<p_reference*0.8 and high<p_reference then 'review_below'
 when median>p_reference*1.2 and low>p_reference then 'review_above' else 'within_or_uncertain' end;
 return jsonb_build_object('status','compared','delta',delta,'percent',round(delta/nullif(p_reference,0)*100,1),'direction',direction,'quality',case when not dependable then 'low' when p_estimate->>'basis'='sold' then 'moderate' else 'low_asking' end);
end $$;

create function private.hub_market_context_save_v1(p_tenant uuid,p_asset uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare clean jsonb; year integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.manage') or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsadministratör krävs' using errcode='42501';end if;
 if not exists(select 1 from public.hub_objects where tenant_id=p_tenant and id=p_asset and object_type='Vehicle') or public.hub_resolve_canonical_object_v1(p_tenant,p_asset)<>p_asset then raise exception 'Verifierat Humla-ID krävs';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'Ogiltigt underlag';end if;
 year:=nullif(p_data->>'model_year','')::integer;
 if year is null or year<1900 or year>extract(year from now())+1 or coalesce(p_data->>'price_basis','') not in ('net','gross') or coalesce(p_data->>'register_price_basis','') not in ('unknown','net','gross') or coalesce(p_data->>'meter_type','') not in ('odometer_km','engine_hours','none') then raise exception 'Kontrollera årsmodell, mätartyp och momsgrund';end if;
 clean:=jsonb_build_object('model_year',year,'meter_type',p_data->>'meter_type','price_basis',p_data->>'price_basis','register_price_basis',p_data->>'register_price_basis','variant',left(coalesce(p_data->>'variant',''),300));
 insert into private.hub_asset_market_context(tenant_id,asset_id,context,updated_by) values(p_tenant,p_asset,clean,auth.uid())
 on conflict(tenant_id,asset_id) do update set history=hub_asset_market_context.history||jsonb_build_array(jsonb_build_object('context',hub_asset_market_context.context,'updated_at',hub_asset_market_context.updated_at,'updated_by',hub_asset_market_context.updated_by)),context=excluded.context,updated_at=now(),updated_by=auth.uid();
 return jsonb_build_object('saved',true);
end $$;

create function private.hub_asset_market_review_v1(p_tenant uuid,p_as_of date,p_asset uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='20s' as $$
declare report jsonb; register jsonb; vehicle jsonb; rows jsonb:='[]'; ctx jsonb; ref numeric; refbasis text; refkind text; year integer; meter numeric; metertype text; basis text; groups jsonb; estimate jsonb; sold jsonb; asking jsonb; acquisition jsonb; acquisition_count integer; total integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsbehörighet saknas' using errcode='42501';end if;
 report:=private.hub_asset_tco_v1(p_tenant,p_as_of,p_asset);
 register:=public.hub_asset_register_projection_v1(p_tenant,p_as_of,p_asset);
 for vehicle in select value from jsonb_array_elements(report->'assets') loop
  ctx:=null;select context into ctx from private.hub_asset_market_context where tenant_id=p_tenant and asset_id=(vehicle->>'id')::uuid;
  year:=coalesce((ctx->>'model_year')::integer,(vehicle#>>'{ownership,model_year}')::integer);
  basis:=coalesce(ctx->>'price_basis',vehicle#>>'{ownership,price_basis}');
  metertype:=coalesce(ctx->>'meter_type',vehicle#>>'{ownership,meter_type}',case when vehicle->>'source_meter_type'='K_OT_HOURS' then 'engine_hours' when vehicle->>'vehicle_type'='Släpvagn' then 'none' else 'odometer_km' end);
  meter:=null;select m.reading_value into meter from public.hub_vehicle_meter_readings m where m.tenant_id=p_tenant and public.hub_resolve_canonical_object_v1(p_tenant,m.vehicle_id)=(vehicle->>'id')::uuid and m.reading_type=metertype and m.recorded_at<((p_as_of+1)::timestamp at time zone 'Europe/Stockholm') order by recorded_at desc limit 1;
  ref:=(vehicle->>'planned_value')::numeric;refbasis:=vehicle#>>'{ownership,price_basis}';refkind:='ownership_model';
  select count(*),jsonb_agg(r)->0 into acquisition_count,acquisition from jsonb_array_elements(register->'rows') r where r->>'asset_id'=vehicle->>'id' and r->>'link_kind'='asset' and not (r->>'sold')::boolean and r#>>'{projection,status}'='calculated';
  if ref is null then
   refkind:='register_model';ref:=case when acquisition_count=1 then (acquisition#>>'{projection,remaining_value}')::numeric end;refbasis:=ctx->>'register_price_basis';
  end if;
  select count(*) into total from private.hub_asset_comparables where tenant_id=p_tenant and asset_id=(vehicle->>'id')::uuid;
  with valid as (
   select c.* from private.hub_asset_comparables c where c.tenant_id=p_tenant and c.asset_id=(vehicle->>'id')::uuid and c.comparable_confirmed and c.price_basis=basis and c.observed_on between p_as_of-180 and p_as_of
   and abs(c.model_year-year)<=2 and (c.price_type='asking' or c.sale_confirmed)
   and (metertype='none' or (meter is not null and c.meter is not null and abs(c.meter-meter)<=greatest(case when metertype='engine_hours' then 1000 else 20000 end,meter*0.3)))
  ), stats as (
   select price_type,jsonb_build_object('basis',price_type,'n',count(*),'sources',count(distinct source),'median',percentile_cont(0.5) within group(order by price)::numeric,'mean',round(avg(price),2),'low',min(price),'high',max(price),'latest_date',max(observed_on),'ids',jsonb_agg(id)) result from valid group by price_type
  ) select jsonb_object_agg(price_type,result) into groups from stats;
  sold:=groups->'sold';asking:=groups->'asking';
  estimate:=case when (sold->>'n')::integer>=3 then sold when (asking->>'n')::integer>=3 then asking end;
  rows:=rows||jsonb_build_array(vehicle||jsonb_build_object('market_review',jsonb_build_object('context',ctx,'model_year',year,'meter_type',metertype,'meter',meter,'price_basis',basis,'reference',ref,'reference_basis',refbasis,'reference_kind',refkind,'total_rows',total,'sold_stats',sold,'asking_stats',asking,'estimate',estimate,'gap',private.hub_market_gap_v1(ref,refbasis,estimate,basis))));
 end loop;
 return jsonb_set(report||jsonb_build_object('register',register),'{assets}',rows);
end $$;
create function public.hub_asset_market_review_v1(p_tenant uuid,p_as_of date,p_asset uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select private.hub_asset_market_review_v1(p_tenant,p_as_of,p_asset)$$;
create function public.hub_market_context_save_v1(p_tenant uuid,p_asset uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.hub_market_context_save_v1(p_tenant,p_asset,p_data)$$;
revoke all on function private.hub_market_gap_v1(numeric,text,jsonb,text),private.hub_market_context_save_v1(uuid,uuid,jsonb),private.hub_asset_market_review_v1(uuid,date,uuid),public.hub_market_context_save_v1(uuid,uuid,jsonb),public.hub_asset_market_review_v1(uuid,date,uuid) from public,anon;
grant execute on function private.hub_market_gap_v1(numeric,text,jsonb,text),private.hub_market_context_save_v1(uuid,uuid,jsonb),private.hub_asset_market_review_v1(uuid,date,uuid),public.hub_market_context_save_v1(uuid,uuid,jsonb),public.hub_asset_market_review_v1(uuid,date,uuid) to authenticated;
