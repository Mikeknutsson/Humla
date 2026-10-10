-- Confirmed comparison groups are canonical Hub objects; revisions retain actor/time.
create function private.hub_fleet_comparison_save_v1(p_tenant uuid,p_group uuid,p_name text,p_class text,p_members uuid[],p_notes text,p_revision integer default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare group_id uuid; current_version integer; snapshot jsonb; bad boolean;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.manage') or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsadministratör krävs' using errcode='42501';end if;
 if p_name is null or length(trim(p_name)) not between 1 and 120 or p_class is null or p_class not in ('Personbil','Lastbil','Släpvagn','Maskin') or coalesce(cardinality(p_members),0) not between 2 and 100 or length(coalesce(p_notes,''))>2000 then raise exception 'Ange namn, kategori och 2–100 likvärdiga fordon';end if;
 if (select count(distinct id) from unnest(p_members) id)<>cardinality(p_members) then raise exception 'Dubbletter i gruppen';end if;
 select exists(select 1 from unnest(p_members) id left join public.hub_objects o on o.id=id and o.tenant_id=p_tenant and o.object_type='Vehicle'
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

-- Each asset is compared with OTHER members, not with a median including itself.
create function private.hub_fleet_compare_rows_v1(p_assets jsonb,p_members jsonb)
returns jsonb language sql immutable set search_path='' as $$
with members as materialized(select a from jsonb_array_elements(p_assets) a where p_members ? (a->>'id')),
metrics as materialized(select a->>'id' id,m.key,m.value from members cross join lateral (values
 ('cost_per_unit',(a->>'cost_per_unit')::numeric),('fuel_per_unit',(a->>'fuel_per_unit')::numeric),
 ('repair_per_unit',(a->>'service_repair')::numeric/nullif(case when a->>'meter_type'='engine_hours' then (a->>'usage')::numeric else (a->>'usage')::numeric/10 end,0))) m(key,value)
 where (a->>'missing_months')::integer=0 and (a->>'usage')::numeric>0 and m.value>=0),
comparisons as(select a,mkey.key,m.value,ref.n,ref.median from members cross join (values('cost_per_unit'),('fuel_per_unit'),('repair_per_unit')) mkey(key)
 left join metrics m on m.id=a->>'id' and m.key=mkey.key
 left join lateral(select count(*) n,percentile_cont(0.5) within group(order by x.value)::numeric median from metrics x join members other on other.a->>'id'=x.id
 where x.id<>a->>'id' and x.key=mkey.key and other.a->>'meter_type'=a->>'meter_type') ref on true),
per_asset as(select a,jsonb_object_agg(coalesce(key,'unavailable'),jsonb_build_object('value',round(value,2),'peers',n,'median',case when n>=3 then round(median,2) end,
 'change_pct',case when n>=3 and median>0 and value is not null then round((value-median)/median*100,1) end,
 'outlier',coalesce(n>=3 and median>0 and value>median*1.3,false))) metrics from comparisons group by a)
select coalesce(jsonb_agg(jsonb_build_object('id',a->>'id','registration',a->>'registration','description',a->>'description','model',a->>'model','meter_type',a->>'meter_type','cost',a->'cost','service_repair',a->'service_repair','usage',a->'usage','metrics',metrics) order by a->>'registration'),'[]'::jsonb) from per_asset
$$;

create function private.hub_fleet_comparison_v1(p_tenant uuid,p_year integer,p_months integer[],p_asset uuid default null,p_department text default null)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='15s' as $$
declare report jsonb;groups jsonb;
begin
 report:=private.hub_fleet_kpi_v1(p_tenant,p_year,p_months,p_asset,p_department);
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'revision',o.version,'name',o.data->>'name','class',o.data->>'class','notes',o.data->>'notes','members',o.data->'members','confirmed_at',o.data->>'confirmed_at',
 'rows',private.hub_fleet_compare_rows_v1(report->'assets',o.data->'members')) order by o.data->>'name'),'[]') into groups
 from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='FleetComparisonGroup' and o.status='active';
 return report||jsonb_build_object('comparison_groups',groups,'can_manage',public.hub_has_permission(p_tenant,'fleet.manage'));
end $$;
create function public.hub_fleet_comparison_v1(p_tenant uuid,p_year integer,p_months integer[],p_asset uuid default null,p_department text default null)
returns jsonb language sql stable security invoker set search_path='' as $$select private.hub_fleet_comparison_v1(p_tenant,p_year,p_months,p_asset,p_department)$$;
create function public.hub_fleet_comparison_save_v1(p_tenant uuid,p_group uuid,p_name text,p_class text,p_members uuid[],p_notes text,p_revision integer default null)
returns uuid language sql security invoker set search_path='' as $$select private.hub_fleet_comparison_save_v1(p_tenant,p_group,p_name,p_class,p_members,p_notes,p_revision)$$;
revoke all on function private.hub_fleet_compare_rows_v1(jsonb,jsonb),private.hub_fleet_comparison_v1(uuid,integer,integer[],uuid,text),public.hub_fleet_comparison_v1(uuid,integer,integer[],uuid,text),private.hub_fleet_comparison_save_v1(uuid,uuid,text,text,uuid[],text,integer),public.hub_fleet_comparison_save_v1(uuid,uuid,text,text,uuid[],text,integer) from public,anon;
grant execute on function private.hub_fleet_comparison_v1(uuid,integer,integer[],uuid,text),public.hub_fleet_comparison_v1(uuid,integer,integer[],uuid,text),private.hub_fleet_comparison_save_v1(uuid,uuid,text,text,uuid[],text,integer),public.hub_fleet_comparison_save_v1(uuid,uuid,text,text,uuid[],text,integer) to authenticated;
