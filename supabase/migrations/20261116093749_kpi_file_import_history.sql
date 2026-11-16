create function private.hub_kpi_import_history(t uuid, p_kind text, p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(t,'kpi.manage') then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if p_page is null or p_page not between 0 and 10000 then
  raise exception 'Invalid page' using errcode='22023';
 end if;

 with recent as materialized (
  select * from (
   select 'kpi:'||b.id::text as entry_id,b.id as batch_id,null::text as stena_hash,b.file_name,b.data_kind as kind,
    b.status,coalesce(b.completed_at,b.created_at) as imported_at,b.period_start,b.period_end,
    b.row_count,b.invalid_row_count as review_rows
   from public.kpi_import_batches b
   where b.tenant_id=t and (p_kind is null or p_kind=b.data_kind)
   union all
   select 'stena:'||f.file_hash,null,f.file_hash,f.file_name,'stena_'||f.source_kind,
     case when f.complete then 'completed' else 'incomplete' end,
     f.uploaded_at,null,null,f.expected_rows,null
   from private.hub_stena_files_v1 f
   where f.tenant_id=t and (p_kind is null or p_kind='stena' or p_kind='stena_'||f.source_kind)
  ) files
  order by imported_at desc,files.entry_id desc
  offset p_page*30 limit 31
 ), visible as (
  select q.entry_id,q.file_name,q.kind,
   case when q.status='completed' and s.review_rows>0 then 'needs_review' else q.status end as status,
   q.imported_at,coalesce(q.period_start,s.period_start) as period_start,coalesce(q.period_end,s.period_end) as period_end,
   q.row_count,coalesce(s.review_rows,q.review_rows,0) as review_rows,
   case when q.stena_hash is not null then array['stena_portal'] else array(
    select distinct r.source_system from public.kpi_import_rows r
    where r.tenant_id=t and r.batch_id=q.batch_id and r.source_system is not null order by r.source_system
   ) end as sources
  from (select * from recent order by imported_at desc,entry_id desc limit 30) q
  left join lateral (
   select min(r.occurred_on) as period_start,max(r.occurred_on) as period_end,
    count(*) filter(where r.amount is null)::int as review_rows
   from private.hub_stena_rows_v1 r where q.stena_hash is not null and r.tenant_id=t and r.file_hash=q.stena_hash
  ) s on q.stena_hash is not null
 )
 select jsonb_build_object('imports',coalesce(jsonb_agg(to_jsonb(v) order by v.imported_at desc,v.entry_id desc),'[]'::jsonb),
  'has_more',(select count(*)>30 from recent)) into result from visible v;
 return result;
end $$;
revoke all on function private.hub_kpi_import_history(uuid,text,integer) from public,anon,authenticated;
grant execute on function private.hub_kpi_import_history(uuid,text,integer) to authenticated;

create function public.hub_kpi_import_history(t uuid,p_kind text default null,p_page integer default 0)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_kpi_import_history(t,p_kind,p_page)
$$;
revoke all on function public.hub_kpi_import_history(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.hub_kpi_import_history(uuid,text,integer) to authenticated;
