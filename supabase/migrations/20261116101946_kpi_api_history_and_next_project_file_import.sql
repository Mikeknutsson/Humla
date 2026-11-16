alter table public.kpi_import_batches drop constraint kpi_import_batches_data_kind_check;
alter table public.kpi_import_batches add constraint kpi_import_batches_data_kind_check
 check (data_kind in ('revenue','cost','fuel','vehicle_activity','driver_time','next_historical_time','next_projects'));
alter table public.kpi_next_project_register add column cost_center_name text, add column source_business_groups text;

do $migration$
declare definition text:=pg_get_functiondef('private.hub_kpi_import_history(uuid,text,integer)'::regprocedure);
begin
 if strpos(definition,'where b.tenant_id=t and (p_kind')=0 then raise exception 'Import history definition changed'; end if;
 execute replace(definition,'where b.tenant_id=t and (p_kind','where b.tenant_id=t and b.source_type<>''hub_api'' and (p_kind');
end $migration$;

create function private.hub_next_project_upload(t uuid,p_id uuid,p_file text,p_hash text,p_path text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare existing uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(t,'kpi.manage') then raise exception 'Access denied' using errcode='42501';end if;
 if p_id is null or p_file is null or length(p_file) not between 1 and 200 or p_hash is null or p_hash !~ '^[0-9a-f]{64}$'
  or p_path is null or split_part(p_path,'/',1)<>t::text or split_part(p_path,'/',2)<>p_id::text
  or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 10000
 then raise exception 'Invalid project file' using errcode='22023';end if;
 if exists(select 1 from jsonb_to_recordset(p_rows) as r(project_number text,project_name text,cost_center text)
  where nullif(trim(project_number),'') is null or length(project_number)>80 or nullif(trim(project_name),'') is null
   or (nullif(trim(cost_center),'') is not null and cost_center !~ '^[0-9]{1,8}$'))
  or (select count(distinct trim(r->>'project_number')) from jsonb_array_elements(p_rows) r)<>jsonb_array_length(p_rows)
 then raise exception 'Invalid or duplicate project' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('next-project-upload:'||t::text,0));
 select id into existing from public.kpi_import_batches where tenant_id=t and data_kind='next_projects' and file_hash=p_hash and status='completed' limit 1;
 if existing is not null then return jsonb_build_object('duplicate',true,'batch_id',existing);end if;
 insert into public.kpi_next_project_register as p(tenant_id,project_number,project_name,cost_center,cost_center_name,
  project_manager,project_status,project_category,source_business_groups)
 select t,trim(project_number),trim(project_name),nullif(trim(cost_center),''),nullif(trim(cost_center_name),''),
  nullif(trim(project_manager),''),nullif(trim(project_status),''),nullif(trim(project_category),''),nullif(trim(source_business_groups),'')
 from jsonb_to_recordset(p_rows) as r(project_number text,project_name text,cost_center text,cost_center_name text,
     project_manager text,project_status text,project_category text,source_business_groups text)
 on conflict(tenant_id,project_number) do update set
  project_name=excluded.project_name,cost_center=coalesce(excluded.cost_center,p.cost_center),
  cost_center_name=coalesce(excluded.cost_center_name,p.cost_center_name),
  project_manager=coalesce(excluded.project_manager,p.project_manager),project_status=coalesce(excluded.project_status,p.project_status),
  project_category=coalesce(excluded.project_category,p.project_category),
  source_business_groups=coalesce(excluded.source_business_groups,p.source_business_groups),imported_at=now();
 insert into public.kpi_import_batches(id,tenant_id,source_type,data_kind,file_name,file_hash,storage_path,status,
  row_count,valid_row_count,created_by,completed_at,provenance)
 values(p_id,t,'manual_excel','next_projects',p_file,p_hash,p_path,'completed',
  jsonb_array_length(p_rows),jsonb_array_length(p_rows),auth.uid(),now(),'{"channel":"manual_upload","original_preserved":true,"connector":"next_project_api"}');
 return jsonb_build_object('duplicate',false,'batch_id',p_id,'rows',jsonb_array_length(p_rows));
end $$;
revoke all on function private.hub_next_project_upload(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.hub_next_project_upload(uuid,uuid,text,text,text,jsonb) to authenticated;

create function public.hub_next_project_upload(t uuid,p_id uuid,p_file text,p_hash text,p_path text,p_rows jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.hub_next_project_upload(t,p_id,p_file,p_hash,p_path,p_rows)
$$;
revoke all on function public.hub_next_project_upload(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.hub_next_project_upload(uuid,uuid,text,text,text,jsonb) to authenticated;

create function private.hub_kpi_api_import_history(t uuid,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(t,'kpi.manage') then raise exception 'Access denied' using errcode='42501'; end if;
 if p_page is null or p_page not between 0 and 10000 then raise exception 'Invalid page' using errcode='22023'; end if;
 with recent as (
  select * from (
   select 'next:'||n.id::text as id,'NeXT'::text as source, n.status,
    coalesce(n.completed_at,n.started_at) as run_at,array(select jsonb_array_elements_text(n.entity_types)) as entities,
    n.fetched_count,n.upserted_count,null::date as period_start,null::date as period_end,false as latest_only
   from public.hub_next_sync_runs n where n.tenant_id=t
   union all
   select 'transpa:'||r.id::text,'TransPA',r.status,coalesce(r.completed_at,r.started_at),r.entity_types,
    r.fetched_count,r.upserted_count,null,null,false
   from public.hub_transpa_sync_runs r where r.tenant_id=t
   union all
   select 'connection:'||c.id::text,case c.connector_type when 'piusi_bsmart' then 'B.SMART / PIUSI'
    when 'fordonskontrollen' then 'Fordonskontroll' when 'scania_data_access' then 'Scania' else c.name end,
    case when c.last_success_at is not null and (c.last_error_at is null or c.last_success_at>=c.last_error_at)
      then 'completed' else 'failed' end,
    greatest(c.last_success_at,c.last_error_at),null,null,null,null,null,true
   from public.hub_connections c
   where c.tenant_id=t and c.connector_type not in ('next_project_api','transpa_public_api')
     and (c.last_success_at is not null or c.last_error_at is not null) and c.status<>'setup_required'
   union all
   select 'batch:'||b.id::text,coalesce(b.file_name,'API-import'),b.status,coalesce(b.completed_at,b.created_at),
    array[b.data_kind],b.row_count,b.valid_row_count,b.period_start,b.period_end,false
   from public.kpi_import_batches b where b.tenant_id=t and b.source_type='hub_api'
  ) runs order by run_at desc,id desc offset p_page*30 limit 31
 )
 select jsonb_build_object('runs',coalesce((select jsonb_agg(to_jsonb(v) order by v.run_at desc,v.id desc)
   from (select * from recent order by run_at desc,id desc limit 30) v),'[]'::jsonb),
  'has_more',(select count(*)>30 from recent)) into result;
 return result;
end $$;
revoke all on function private.hub_kpi_api_import_history(uuid,integer) from public,anon,authenticated;
grant execute on function private.hub_kpi_api_import_history(uuid,integer) to authenticated;
create function public.hub_kpi_api_import_history(t uuid,p_page integer default 0)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_kpi_api_import_history(t,p_page)
$$;
revoke all on function public.hub_kpi_api_import_history(uuid,integer) from public,anon,authenticated;
grant execute on function public.hub_kpi_api_import_history(uuid,integer) to authenticated;
