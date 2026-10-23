-- Sources are approved separately; this migration never imports or posts costs.
create table private.hub_workshop_time_sources(
 tenant_id uuid not null,batch_id uuid not null references public.kpi_import_batches(id),
 file_hash text not null,approval_reference text not null,created_at timestamptz not null default now(),
 primary key(tenant_id,batch_id)
);
alter table private.hub_workshop_time_sources enable row level security;
revoke all on private.hub_workshop_time_sources from public,anon,authenticated;
create function public.hub_kpi_workshop_time_v1(p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period';end if;
 if p_months is not null and (cardinality(p_months)=0 or exists(select 1 from unnest(p_months)m where m is null or m<1 or m>12))then raise exception 'Invalid months';end if;
 with rows as materialized(
 select r.*,nullif(trim(r.source_data->>'Kostnadsställe nr'),'') target_center,
 (r.project_reference='99999' or lower(trim(r.source_data->>'Projektnamn'))='frånvaro') absence,
 lower(trim(coalesce(r.source_data->>'Godkänd','')))in('true','1','ja') approved,
 row_number()over(partition by r.batch_id,(r.source_data-array['Godkännandedatum','Godkänd av','Godkänd','Fakturadatum'])::text order by r.row_number,r.id)occurrence,
 (r.source_data-array['Godkännandedatum','Godkänd av','Godkänd','Fakturadatum'])::text fingerprint
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 join private.hub_workshop_time_sources s on s.tenant_id=r.tenant_id and s.batch_id=b.id and s.file_hash=b.file_hash
 where r.tenant_id=p_tenant_id and r.data_kind='next_historical_time' and b.status='completed'
 and r.occurred_on between p_from and p_to and (p_months is null or extract(month from r.occurred_on)::integer=any(p_months))
 ), ranked as(
 select *,row_number()over(partition by fingerprint,occurrence order by approved desc,is_valid desc,created_at,id) copy_rank from rows
 ), facts as(
 select *,case when not is_valid or not approved or paid_hours is null or paid_hours<0 then 'review'
 when absence then 'absence' when target_center='40' then 'non_billable'
 when target_center in('10','20','30','50','60','90')then 'billable'else 'review'end status from ranked where copy_rank=1
 ), totals as(
 select count(*) rows,coalesce(sum(paid_hours)filter(where status='absence'),0) absence_hours,
 coalesce(sum(paid_hours)filter(where status='billable'),0)billable_hours,
 coalesce(sum(paid_hours)filter(where status='non_billable'),0)non_billable_hours,
 count(*)filter(where status='review')review_rows from facts
 ), people as(
 select source_data->>'Namn' name,coalesce(sum(paid_hours)filter(where status='absence'),0)absence_hours,
 coalesce(sum(paid_hours)filter(where status='billable'),0)billable_hours,
 coalesce(sum(paid_hours)filter(where status='non_billable'),0)non_billable_hours,count(*)filter(where status='review')review_rows
 from facts group by 1
 ), centers as(
 select target_center code,source_data->>'Namn' name,sum(paid_hours) hours from facts where status in('billable','non_billable') group by 1,2
 )select to_jsonb(t)||jsonb_build_object('available',t.rows>0,'work_hours',t.billable_hours+t.non_billable_hours,
 'billing_rate',round(100*t.billable_hours/nullif(t.billable_hours+t.non_billable_hours,0),1),
 'duplicate_rows',(select count(*)from ranked where copy_rank>1),
 'people',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('work_hours',p.billable_hours+p.non_billable_hours,'billing_rate',round(100*p.billable_hours/nullif(p.billable_hours+p.non_billable_hours,0),1))order by name)from people p),'[]'::jsonb),
 'centers',coalesce((select jsonb_agg(to_jsonb(c)order by code,name)from centers c),'[]'::jsonb))into answer from totals t;
 return answer;
end $$;
revoke all on function public.hub_kpi_workshop_time_v1(uuid,date,date,integer[])from public,anon;
grant execute on function public.hub_kpi_workshop_time_v1(uuid,date,date,integer[])to authenticated,service_role;
