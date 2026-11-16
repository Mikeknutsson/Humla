-- The register exposes source evidence independently of the project's KPI allocation.
create function private.hub_kpi_project_register_overview(t uuid,p_from date,p_to date,p_months integer[],p_search text,p_page integer,p_exact boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(t,'kpi.read') then
  raise exception 'Not authorized' using errcode='42501';
 end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>1096 or p_page is null or p_page not between 0 and 10000
  or length(p_search)>150 or cardinality(p_months)>12 or array_position(p_months,null) is not null
  or exists(select 1 from unnest(p_months) m where m not between 1 and 12) then
  raise exception 'Invalid project selection' using errcode='22023';
 end if;
 with latest as (
  select file_name,row_count,completed_at,created_at from public.kpi_import_batches
  where tenant_id=t and data_kind='next_projects' and status='completed'
  order by created_at desc,id desc limit 1
 ), matches as materialized (
  select r.project_number,r.project_name,r.project_manager,r.cost_center as source_center,r.cost_center_name,
   r.source_business_groups,r.imported_at
  from public.kpi_next_project_register r
  where r.tenant_id=t and (
   (p_exact and r.project_number=p_search) or
   (not p_exact and (nullif(p_search,'') is null or strpos(lower(concat_ws(' ',r.project_number,r.project_name,r.project_manager,r.source_business_groups)),lower(p_search))>0))
  )
 ), page as materialized (
  select * from matches order by project_number offset p_page*50 limit 50
 ), visible as (
  select p.*,c.cost_center,c.business_group,
   case when c.cost_center is not null then ident.id end as kpi_project_id,
   ident.id is not null as has_identity,
   evidence.booked_amount,evidence.booked_rows
  from page p
  left join lateral (
   select c.cost_center,c.business_group from public.kpi_project_classification_periods c
   where c.tenant_id=t and c.project_reference=p.project_number and c.valid_from<=current_date
    and (c.valid_to is null or c.valid_to>=current_date)
   order by c.valid_from desc limit 1
  ) c on c.cost_center in ('10','20','30','40','50','60','90')
  left join lateral (
   select min(canonical.id::text)::uuid as id
   from public.hub_identity_keys k
   cross join lateral (select public.hub_resolve_canonical_object_v1(t,k.object_id) id) canonical
   where k.tenant_id=t and k.identity_type='next_project_number' and k.identity_value=p.project_number and k.confidence=1
   having count(distinct canonical.id)=1
  ) ident on true
  left join lateral (
   select sum(r.amount) as booked_amount,count(*) as booked_rows
   from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=t
   where r.tenant_id=t and r.occurred_on between p_from and p_to and trim(r.project_reference)=p.project_number
    and r.source_data?'Projektnr' and r.source_data?'Bokf datum' and r.data_kind='revenue'
    and r.amount is not null and r.is_valid and b.status in ('completed','needs_review')
    and not coalesce(b.provenance,'{}'::jsonb)?'withdrawal'
    and (p_months is null or extract(month from r.occurred_on)::int=any(p_months))
  ) evidence on true
 )
 select jsonb_build_object(
  'latest',(select to_jsonb(l) from latest l),'matched',(select count(*) from matches),
  'projects',coalesce((select jsonb_agg(to_jsonb(v) order by v.project_number) from visible v),'[]'::jsonb)
 ) into result;
 return result;
end $$;
revoke all on function private.hub_kpi_project_register_overview(uuid,date,date,integer[],text,integer,boolean) from public,anon,authenticated;
grant execute on function private.hub_kpi_project_register_overview(uuid,date,date,integer[],text,integer,boolean) to authenticated;

create function public.hub_kpi_project_register_overview(t uuid,p_from date,p_to date,p_months integer[],p_search text default '',p_page integer default 0,p_exact boolean default false)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_kpi_project_register_overview(t,p_from,p_to,p_months,p_search,p_page,p_exact)
$$;
revoke all on function public.hub_kpi_project_register_overview(uuid,date,date,integer[],text,integer,boolean) from public,anon,authenticated;
grant execute on function public.hub_kpi_project_register_overview(uuid,date,date,integer[],text,integer,boolean) to authenticated;
