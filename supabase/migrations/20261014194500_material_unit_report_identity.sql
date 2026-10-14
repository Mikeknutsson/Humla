CREATE OR REPLACE FUNCTION private.hub_kpi_mapped_units_projection_v1(p_tenant uuid, p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb:=p_report; mapped jsonb; hidden jsonb; section text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if jsonb_typeof(result->'economic_units')='array' then
  select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where o.id is not null),'[]'::jsonb),
   jsonb_build_object('count',count(*) filter(where o.id is null),
    'revenue',coalesce(sum((e.value->>'revenue')::numeric) filter(where o.id is null),0),
    'cost',coalesce(sum((e.value->>'cost')::numeric) filter(where o.id is null),0))
  into mapped,hidden
  from jsonb_array_elements(result->'economic_units') with ordinality e(value,ordinality)
  left join public.hub_objects o on o.tenant_id=p_tenant and o.object_type='EconomicUnit' and o.id::text=e.value->>'key';
  result:=result||jsonb_build_object('economic_units',mapped,'economic_unit_scope','mapped','unmapped_economic_units',hidden);
 end if;
 foreach section in array array['month','ytd','previous'] loop
  if jsonb_typeof(result->section)='object' then
   result:=jsonb_set(result,array[section],private.hub_kpi_mapped_units_projection_v1(p_tenant,result->section));
  end if;
 end loop;
 result:=result||jsonb_build_object('material_unit_id',(select material_unit_id from private.hub_kpi_material_separation_settings where tenant_id=p_tenant and enabled));
 return result;
end $function$

