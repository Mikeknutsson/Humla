create or replace function private.hub_asset_market_review_v1(p_tenant uuid,p_as_of date,p_asset uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='20s' as $$
declare report jsonb; register jsonb; vehicle jsonb; rows jsonb:='[]'; ctx jsonb; ref numeric; refbasis text; refkind text; year integer; v_meter numeric; metertype text; basis text; groups jsonb; estimate jsonb; sold jsonb; asking jsonb; acquisition jsonb; acquisition_count integer; total integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsbehörighet saknas' using errcode='42501';end if;
 report:=private.hub_asset_tco_v1(p_tenant,p_as_of,p_asset);
 register:=public.hub_asset_register_projection_v1(p_tenant,p_as_of,p_asset);
 for vehicle in select value from jsonb_array_elements(report->'assets') loop
  ctx:=null;select context into ctx from private.hub_asset_market_context where tenant_id=p_tenant and asset_id=(vehicle->>'id')::uuid;
  year:=coalesce((ctx->>'model_year')::integer,(vehicle#>>'{ownership,model_year}')::integer);
  basis:=coalesce(ctx->>'price_basis',vehicle#>>'{ownership,price_basis}');
  metertype:=coalesce(ctx->>'meter_type',vehicle#>>'{ownership,meter_type}',case when vehicle->>'source_meter_type'='K_OT_HOURS' then 'engine_hours' when vehicle->>'vehicle_type'='Släpvagn' then 'none' else 'odometer_km' end);
  v_meter:=case when metertype=coalesce(vehicle#>>'{ownership,meter_type}',case when vehicle->>'source_meter_type'='K_OT_HOURS' then 'engine_hours' else 'odometer_km' end) then (vehicle->>'current_meter')::numeric end;
  ref:=(vehicle->>'planned_value')::numeric;refbasis:=vehicle#>>'{ownership,price_basis}';refkind:='ownership_model';
  select count(*),jsonb_agg(r)->0 into acquisition_count,acquisition from jsonb_array_elements(register->'rows') r where r->>'asset_id'=vehicle->>'id' and r->>'link_kind'='asset' and not (r->>'sold')::boolean and r#>>'{projection,status}'='calculated';
  if ref is null then
   refkind:='register_model';ref:=case when acquisition_count=1 then (acquisition#>>'{projection,remaining_value}')::numeric end;refbasis:=ctx->>'register_price_basis';
  end if;
  select count(*) into total from private.hub_asset_comparables where tenant_id=p_tenant and asset_id=(vehicle->>'id')::uuid;
  with valid as (
   select c.* from private.hub_asset_comparables c where c.tenant_id=p_tenant and c.asset_id=(vehicle->>'id')::uuid and c.comparable_confirmed and c.price_basis=basis and c.observed_on between p_as_of-180 and p_as_of
   and abs(c.model_year-year)<=2 and (c.price_type='asking' or c.sale_confirmed)
   and (metertype='none' or (v_meter is not null and c.meter is not null and abs(c.meter-v_meter)<=greatest(case when metertype='engine_hours' then 1000 else 20000 end,v_meter*0.3)))
  ), stats as (
   select price_type,jsonb_build_object('basis',price_type,'n',count(*),'sources',count(distinct source),'median',percentile_cont(0.5) within group(order by price)::numeric,'mean',round(avg(price),2),'low',min(price),'high',max(price),'latest_date',max(observed_on),'ids',jsonb_agg(id)) result from valid group by price_type
  ) select jsonb_object_agg(price_type,result) into groups from stats;
  sold:=groups->'sold';asking:=groups->'asking';
  estimate:=case when (sold->>'n')::integer>=3 then sold when (asking->>'n')::integer>=3 then asking end;
  rows:=rows||jsonb_build_array(vehicle||jsonb_build_object('market_review',jsonb_build_object('context',ctx,'model_year',year,'meter_type',metertype,'meter',v_meter,'price_basis',basis,'reference',ref,'reference_basis',refbasis,'reference_kind',refkind,'total_rows',total,'sold_stats',sold,'asking_stats',asking,'estimate',estimate,'gap',private.hub_market_gap_v1(ref,refbasis,estimate,basis))));
 end loop;
 return jsonb_set(report||jsonb_build_object('register',register),'{assets}',rows);
end $$;
