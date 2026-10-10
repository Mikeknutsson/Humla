create or replace function private.hub_fleet_comparison_save_v1(p_tenant uuid,p_group uuid,p_name text,p_class text,p_members uuid[],p_notes text,p_revision integer default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare group_id uuid; current_version integer; snapshot jsonb; bad boolean;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.manage') or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsadministratör krävs' using errcode='42501';end if;
 if p_name is null or length(trim(p_name)) not between 1 and 120 or p_class is null or p_class not in ('Personbil','Lastbil','Släpvagn','Maskin') or coalesce(cardinality(p_members),0) not between 2 and 100 or length(coalesce(p_notes,''))>2000 then raise exception 'Ange namn, kategori och 2–100 likvärdiga fordon';end if;
 if (select count(distinct id) from unnest(p_members) id)<>cardinality(p_members) then raise exception 'Dubbletter i gruppen';end if;
 select exists(select 1 from unnest(p_members) member_id left join public.hub_objects o on o.id=member_id and o.tenant_id=p_tenant and o.object_type='Vehicle'
 where o.id is null or public.hub_resolve_canonical_object_v1(p_tenant,o.id)<>o.id or
 case when o.data->>'vehicle_type' in ('Personbil','Lastbil','Släpvagn') then o.data->>'vehicle_type'<>p_class
 when o.data->>'vehicle_type' in ('Motorredskap','Traktor','Terrängvagn') or o.data->>'odometer_type'='K_OT_HOURS' then p_class<>'Maskin' else false end) into bad;
 if bad then raise exception 'Gruppen innehåller okänt fordon eller olika fordonskategorier';end if;
 group_id:=coalesce(p_group,gen_random_uuid());
 perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||group_id::text,0));
 if p_group is not null then
  select version into current_version from public.hub_objects where id=p_group and tenant_id=p_tenant and object_type='FleetComparisonGroup' for update;
  if current_version is null or p_revision is distinct from current_version then raise exception 'Gruppen har ändrats. Uppdatera vyn innan du sparar';end if;
 else current_version:=0;end if;
 snapshot:=jsonb_build_object('name',trim(p_name),'class',p_class,'members',to_jsonb(p_members),'notes',coalesce(p_notes,''),'confirmed_by',auth.uid(),'confirmed_at',now());
 insert into public.hub_objects(id,tenant_id,object_type,data,source_of_truth,version) values(group_id,p_tenant,'FleetComparisonGroup',snapshot,'humla',1)
 on conflict(id) do update set data=excluded.data,version=current_version+1,updated_at=now();
 insert into public.hub_object_versions(object_id,version,data) values(group_id,current_version+1,snapshot);
 return group_id;
end $$;
