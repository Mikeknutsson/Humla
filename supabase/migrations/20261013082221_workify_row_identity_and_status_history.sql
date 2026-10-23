-- Workify export observations are not new revenue when only status changes.
-- Full source content is compared conservatively because this export has no row ID.
create or replace function private.hub_workify_content_key_v2(p_date date,p_amount numeric,p_quantity numeric,p_source jsonb)
returns text language sql immutable set search_path='' as $$
 select encode(extensions.digest(jsonb_build_array(
   private.hub_workify_import_key_v1(p_date,p_amount,p_quantity,p_source,true),
   (select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(coalesce(p_source,'{}'))
    where key not in ('Orderstatus','Fakturerad','Summa','Kvantitet','Artikeldatum')
      and left(key,7)<>'_humla_' and value not in ('null'::jsonb,'""'::jsonb))
 )::text,'sha256'),'hex');
$$;
revoke all on function private.hub_workify_content_key_v2(date,numeric,numeric,jsonb) from public,anon;
grant execute on function private.hub_workify_content_key_v2(date,numeric,numeric,jsonb) to authenticated,service_role;

create or replace function private.hub_workify_status_rank_v1(p_status text)
returns integer language sql immutable set search_path='' as $$
 select case p_status when 'Reported' then 1 when 'ReadyForInvoicing' then 2 when 'Invoiced' then 3 else 0 end;
$$;
revoke all on function private.hub_workify_status_rank_v1(text) from public,anon;
grant execute on function private.hub_workify_status_rank_v1(text) to authenticated,service_role;

-- Pure planner, shared by the write path and database regression tests.
-- p_known: [{fp, order_number, copies}]; copies counts canonical occurrences.
create or replace function private.hub_workify_import_plan_v2(p_rows jsonb,p_known jsonb)
returns table(row_number integer,fp text,order_number text,occurrence bigint,decision text)
language sql immutable set search_path='' as $$
 with incoming as materialized(
  select (r->>'row_number')::integer row_number,
   private.hub_workify_content_key_v2((r->>'occurred_on')::date,(r->>'amount')::numeric,(r->>'quantity')::numeric,r->'source_data') fp,
   nullif(trim(r#>>'{source_data,Ordernummer}'),'') order_number
  from jsonb_array_elements(p_rows)r where (r->>'amount')::numeric is distinct from 0
 ), known as materialized(select * from jsonb_to_recordset(p_known) as k(fp text,order_number text,copies bigint)),
 counts as(select fp,order_number,count(*) copies from incoming group by 1,2),
 incomplete_orders as(select distinct k.order_number from known k left join counts c using(fp)
  where coalesce(c.copies,0)<k.copies),
 unsafe_orders as(select distinct c.order_number from counts c left join known k using(fp)
  where c.copies>coalesce(k.copies,0) and c.order_number in(select order_number from incomplete_orders)),
 numbered as(select i.*,row_number()over(partition by i.fp order by i.row_number) occurrence from incoming i)
 select n.row_number,n.fp,n.order_number,n.occurrence,
  case when n.order_number is null or n.order_number in(select order_number from unsafe_orders) then 'blocked'
       when n.occurrence>coalesce(k.copies,0) then 'insert' else 'duplicate' end
 from numbered n left join known k on k.fp=n.fp;
$$;
revoke all on function private.hub_workify_import_plan_v2(jsonb,jsonb) from public,anon;
grant execute on function private.hub_workify_import_plan_v2(jsonb,jsonb) to authenticated,service_role;

create table if not exists private.hub_workify_row_observations (
 tenant_id uuid not null references public.hub_tenants(id),
 batch_id uuid not null references public.kpi_import_batches(id),
 row_number integer not null,
 content_key text not null,
 occurrence bigint not null,
 decision text not null check(decision in ('insert','duplicate','blocked')),
 canonical_row_id uuid references public.kpi_import_rows(id),
 source_data jsonb not null,
 amount numeric,
 observed_at timestamptz not null default now(),
 primary key(batch_id,row_number)
);
alter table private.hub_workify_row_observations enable row level security;
revoke all on private.hub_workify_row_observations from public,anon,authenticated;
create index if not exists kpi_workify_v2_lookup on public.kpi_import_rows
 (tenant_id,private.hub_workify_content_key_v2(occurred_on,amount,quantity,source_data)) where data_kind='revenue';

create or replace function public.hub_kpi_ingest_workify_file_v1(p_tenant_id uuid,p_batch_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='60s' set jit='off' set work_mem='64MB'
as $function$
declare result jsonb; known jsonb; plan jsonb; conflicts jsonb; received integer; inserted integer; valid integer; ignored integer; updated integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>50000 then raise exception 'Ogiltig Workify-leverans';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant_id::text,0));
 select provenance->'workify_import_result' into result from public.kpi_import_batches
 where tenant_id=p_tenant_id and id=p_batch_id and data_kind='revenue' for update;
 if not found then raise exception 'Intäktsimporten saknas';end if;
 if result is not null then return result;end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r
 where (r.vehicle_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.vehicle_object_id and o.tenant_id=p_tenant_id))
 or (r.employee_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.employee_object_id and o.tenant_id=p_tenant_id)))
 then raise exception 'Objektet tillhör inte arbetsytan' using errcode='42501';end if;
 if exists(select 1 from jsonb_array_elements(p_rows) r where (r->>'row_number')::int is null)
 or (select count(*) from jsonb_array_elements(p_rows))<>(select count(distinct r->>'row_number') from jsonb_array_elements(p_rows)r)
 then raise exception 'Varje källrad måste ha ett unikt radnummer inom filen';end if;
 received:=jsonb_array_length(p_rows);
 select count(*) into ignored from jsonb_array_elements(p_rows)r where (r->>'amount')::numeric=0;
 -- Include all older observations when deriving occurrence capacity, including
 -- retained duplicate originals. Incremental v2 inserts carry explicit ordinals.
 with orders as(select distinct r#>>'{source_data,Ordernummer}' number from jsonb_array_elements(p_rows)r),
 previous as materialized(select r.*,private.hub_workify_content_key_v2(r.occurred_on,r.amount,r.quantity,r.source_data) fp
  from public.kpi_import_rows r join orders o on o.number=r.source_data->>'Ordernummer'
  where r.tenant_id=p_tenant_id and r.data_kind='revenue'),
 batches as(select fp,source_data->>'Ordernummer' order_number,batch_id,count(*) copies,
  max(case when source_fingerprint like 'workify-file-v2:%' then split_part(source_fingerprint,':',3)::bigint else 0 end) ordinal
  from previous group by 1,2,3),
 capacity as(select fp,order_number,greatest(max(copies),max(ordinal)) copies from batches group by 1,2)
 select coalesce(jsonb_agg(to_jsonb(c)),'[]') into known from capacity c;
 select coalesce(jsonb_agg(to_jsonb(p)),'[]') into plan from private.hub_workify_import_plan_v2(p_rows,known)p;
 select coalesce(jsonb_agg(jsonb_build_object('row',p.row_number,'order',p.order_number,'amount',r->'amount',
  'reason','Radidentiteten är osäker: tidigare innehåll saknas samtidigt som nytt innehåll tillkommer. Hela leveransen väntar på granskning.')),'[]') into conflicts
 from jsonb_to_recordset(plan) as p(row_number int,order_number text,decision text)
 join jsonb_array_elements(p_rows) r on (r->>'row_number')::int=p.row_number where p.decision='blocked';
 if jsonb_array_length(conflicts)>0 then
  insert into private.hub_workify_row_observations(tenant_id,batch_id,row_number,content_key,occurrence,decision,source_data,amount)
  select p_tenant_id,p_batch_id,p.row_number,p.fp,p.occurrence,'blocked',coalesce(r->'source_data','{}'),(r->>'amount')::numeric
  from jsonb_to_recordset(plan) as p(row_number int,fp text,occurrence bigint)
  join jsonb_array_elements(p_rows)r on (r->>'row_number')::int=p.row_number;
  result:=jsonb_build_object('status','blocked_changes','receivedRows',received,'insertedRows',0,'changedRows',jsonb_array_length(conflicts),'changes',conflicts);
  update public.kpi_import_batches set status='needs_review',completed_at=now(),valid_row_count=0,invalid_row_count=received,
   error_summary=conflicts,provenance=coalesce(provenance,'{}')||jsonb_build_object('workify_import_result',result)
  where tenant_id=p_tenant_id and id=p_batch_id;
  return result;
 end if;
 with accepted as(select r.*,p.fp,p.occurrence from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows)r
  join jsonb_to_recordset(plan)as p(row_number int,fp text,occurrence bigint,decision text)using(row_number) where p.decision='insert'),
 saved as(insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,currency,available_hours,occupied_hours,paid_hours,billable_hours,is_valid,validation_errors,source_data,allocation,source_system,external_transaction_id,source_fingerprint)
  select p_tenant_id,p_batch_id,row_number,'revenue',occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,coalesce(currency,'SEK'),available_hours,occupied_hours,paid_hours,billable_hours,is_valid,coalesce(validation_errors,'[]'),source_data,allocation,'workify_file',
   'workify-file-v2:'||fp||':'||occurrence,'workify-file-v2:'||fp||':'||occurrence from accepted returning is_valid)
 select count(*),count(*)filter(where is_valid) into inserted,valid from saved;
 -- A status update retains monetary content, canonical ID and confirmed mappings.
 with incoming as(select distinct on(p.fp) p.fp,r->'source_data' data from jsonb_to_recordset(plan)as p(row_number int,fp text)
  join jsonb_array_elements(p_rows)r on (r->>'row_number')::int=p.row_number
  order by p.fp,private.hub_workify_status_rank_v1(r#>>'{source_data,Orderstatus}') desc),
 changed as(update public.kpi_import_rows x set source_data=x.source_data||jsonb_build_object(
  'Orderstatus',i.data->>'Orderstatus','Fakturerad',coalesce(nullif(i.data->>'Fakturerad',''),x.source_data->>'Fakturerad'),
  '_humla_status_history',coalesce(x.source_data->'_humla_status_history','[]')||jsonb_build_array(jsonb_build_object('from',x.source_data->>'Orderstatus','to',i.data->>'Orderstatus','batch_id',p_batch_id,'observed_at',now())))
  from incoming i where x.tenant_id=p_tenant_id and x.data_kind='revenue'
  and private.hub_workify_content_key_v2(x.occurred_on,x.amount,x.quantity,x.source_data)=i.fp
  and private.hub_workify_status_rank_v1(i.data->>'Orderstatus')>private.hub_workify_status_rank_v1(x.source_data->>'Orderstatus') returning x.id)
 select count(*) into updated from changed;
 insert into private.hub_workify_row_observations(tenant_id,batch_id,row_number,content_key,occurrence,decision,source_data,amount)
 select p_tenant_id,p_batch_id,p.row_number,p.fp,p.occurrence,p.decision,coalesce(r->'source_data','{}'),(r->>'amount')::numeric
 from jsonb_to_recordset(plan)as p(row_number int,fp text,occurrence bigint,decision text)
 join jsonb_array_elements(p_rows)r on (r->>'row_number')::int=p.row_number;
 with candidates as(
  select x.id,private.hub_workify_content_key_v2(x.occurred_on,x.amount,x.quantity,x.source_data) fp,
   row_number()over(partition by private.hub_workify_content_key_v2(x.occurred_on,x.amount,x.quantity,x.source_data)
    order by x.is_valid desc,x.created_at,x.row_number,x.id) occurrence
  from public.kpi_import_rows x where x.tenant_id=p_tenant_id and x.data_kind='revenue'
   and not(x.source_data?'_humla_workify_duplicate_of')
   and private.hub_workify_content_key_v2(x.occurred_on,x.amount,x.quantity,x.source_data) in(select p.fp from jsonb_to_recordset(plan)as p(fp text))
 )
 update private.hub_workify_row_observations o set canonical_row_id=c.id from candidates c
 where o.batch_id=p_batch_id and o.tenant_id=p_tenant_id and o.content_key=c.fp and o.occurrence=c.occurrence;
 result:=jsonb_build_object('status',case when inserted=valid then 'completed' else 'needs_review' end,'receivedRows',received,'insertedRows',inserted,'duplicateRowsSkipped',received-ignored-inserted,'ignoredZeroRows',ignored,'validRows',valid,'invalidRows',inserted-valid,'changedRows',0,'statusRowsUpdated',updated);
 update public.kpi_import_batches set row_count=inserted,valid_row_count=valid,invalid_row_count=inserted-valid,completed_at=now(),
  status=case when inserted=valid then 'completed' else 'needs_review' end,
  provenance=coalesce(provenance,'{}')||jsonb_build_object('workify_import_result',result)
 where tenant_id=p_tenant_id and id=p_batch_id;
 return result;
end $function$;
revoke execute on function public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';
